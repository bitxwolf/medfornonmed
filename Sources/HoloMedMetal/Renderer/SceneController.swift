import Foundation
import simd

public enum SceneAction: String, Codable {
    case focusStructure = "FOCUS_STRUCTURE"
    case isolateStructures = "ISOLATE_STRUCTURES"
    case focusAndIsolate = "FOCUS_AND_ISOLATE"
    case highlightStructures = "HIGHLIGHT_STRUCTURES"
    case applyPathology = "APPLY_PATHOLOGY"
    case animateFlow = "ANIMATE_FLOW"
    case placeAnnotation = "PLACE_ANNOTATION"
    case resetScene = "RESET_SCENE"
}

public struct SceneCommandPayload: Codable {
    public var step: Int?
    public var action: SceneAction
    public var targetId: String?
    public var targetIds: [String]?
    public var fadeOccluders: Bool?
    public var cameraPreset: String?
    public var pathologyType: String?
    public var severity: Float?
    public var downstreamIschemicIds: [String]?
    public var annotationTitle: String?
    public var annotationBody: String?

    enum CodingKeys: String, CodingKey {
        case step
        case action
        case targetId = "target_id"
        case targetIds = "target_ids"
        case fadeOccluders = "fade_occluders"
        case cameraPreset = "camera_preset"
        case pathologyType = "pathology_type"
        case severity
        case downstreamIschemicIds = "downstream_ischemic_ids"
        case annotationTitle = "annotation_title"
        case annotationBody = "annotation_body"
    }

    public init(step: Int? = nil,
                action: SceneAction,
                targetId: String? = nil,
                targetIds: [String]? = nil,
                fadeOccluders: Bool? = nil,
                cameraPreset: String? = nil,
                pathologyType: String? = nil,
                severity: Float? = nil,
                downstreamIschemicIds: [String]? = nil,
                annotationTitle: String? = nil,
                annotationBody: String? = nil) {
        self.step = step
        self.action = action
        self.targetId = targetId
        self.targetIds = targetIds
        self.fadeOccluders = fadeOccluders
        self.cameraPreset = cameraPreset
        self.pathologyType = pathologyType
        self.severity = severity
        self.downstreamIschemicIds = downstreamIschemicIds
        self.annotationTitle = annotationTitle
        self.annotationBody = annotationBody
    }
}

public final class SceneController {
    public weak var renderer: MetalRenderer?

    public init(renderer: MetalRenderer? = nil) {
        self.renderer = renderer
    }

    /// Executes structured 3D scene command dispatched from AI tutor stream or UI touch
    public func executeCommand(_ cmd: SceneCommandPayload) {
        guard let renderer = renderer else { return }

        switch cmd.action {
        case .focusStructure, .focusAndIsolate:
            var ids: [String] = []
            if let tIds = cmd.targetIds { ids.append(contentsOf: tIds) }
            if let tId = cmd.targetId { ids.append(tId) }

            focusOnStructures(ids: ids, presetString: cmd.cameraPreset)

            if cmd.action == .focusAndIsolate || cmd.fadeOccluders == true {
                renderer.isolatedFmaIds = Set(ids)
            }

        case .isolateStructures:
            var ids: [String] = []
            if let tIds = cmd.targetIds { ids.append(contentsOf: tIds) }
            if let tId = cmd.targetId { ids.append(tId) }
            renderer.isolatedFmaIds = Set(ids)

        case .highlightStructures:
            let targetId = cmd.targetId ?? cmd.targetIds?.first
            renderer.activeHighlightFmaId = targetId

        case .applyPathology:
            let severity = cmd.severity ?? 0.85
            let pType = cmd.pathologyType ?? "vascular_occlusion"

            if pType == "vascular_occlusion" || pType == "myocardial_infarction" {
                // 1. Constrict LAD coronary artery at proximal segment
                renderer.currentBlockage.stenosisSeverity = severity
                renderer.currentBlockage.splineProgress = 0.88 // Proximal LAD waypoint

                // 2. Transition downstream Left Ventricle myocardium to ischemic/necrotic state
                if severity >= 0.80 {
                    renderer.currentTissue.state = TissueStateNecrotic.rawValue
                    renderer.currentTissue.ischemicRatio = 1.0
                    renderer.currentTissue.necroticRatio = min(1.0, (severity - 0.70) / 0.30)
                } else {
                    renderer.currentTissue.state = TissueStateIschemic.rawValue
                    renderer.currentTissue.ischemicRatio = severity
                    renderer.currentTissue.necroticRatio = 0.0
                }

                // 3. Zoom camera to LAD lesion and ischemic anterior myocardium
                focusOnStructures(ids: ["FMA_7101", "FMA_7097"], presetString: "anterior_oblique")
            }

        case .animateFlow:
            break

        case .placeAnnotation:
            break

        case .resetScene:
            resetScene()
        }
    }

    private func focusOnStructures(ids: [String], presetString: String?) {
        guard let renderer = renderer else { return }

        var centroids: [simd_float3] = []
        var radii: [Float] = []

        for id in ids {
            if let node = renderer.meshNodes.first(where: { $0.fmaId.caseInsensitiveCompare(id) == .orderedSame }) {
                centroids.append(node.centroid)
                radii.append(node.boundingRadius)
            } else {
                print("[SceneController] Defensive warning: Unresolved fma_id: \(id), continuing.")
            }
        }

        if centroids.isEmpty {
            centroids.append(simd_float3(0, 0, 0))
            radii.append(0.35)
        }

        let preset: CameraPreset
        if let ps = presetString, let match = CameraPreset(rawValue: ps) {
            preset = match
        } else {
            preset = .anteriorOblique
        }

        renderer.cameraRig.frameTargets(centroids: centroids, radii: radii, preset: preset)
    }

    public func resetScene() {
        guard let renderer = renderer else { return }
        renderer.activeHighlightFmaId = nil
        renderer.isolatedFmaIds = nil
        renderer.currentBlockage.stenosisSeverity = 0.0
        renderer.currentTissue.state = TissueStateNormal.rawValue
        renderer.currentTissue.ischemicRatio = 0.0
        renderer.currentTissue.necroticRatio = 0.0
        renderer.cameraRig.frameTargets(
            centroids: [simd_float3(0, 0, 0)],
            radii: [0.45],
            preset: .anteriorOblique
        )
    }
}
