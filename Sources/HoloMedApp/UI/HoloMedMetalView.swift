import SwiftUI
import MetalKit
import HoloMedMetal

public struct HoloMedMetalView: UIViewRepresentable {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.backgroundColor = .black
        mtkView.isMultipleTouchEnabled = true

        if let renderer = MetalRenderer(metalView: mtkView) {
            context.coordinator.renderer = renderer
            let controller = SceneController(renderer: renderer)
            context.coordinator.sceneController = controller
            appState.sceneController = controller

            // Gestures
            let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
            pan.maximumNumberOfTouches = 2
            mtkView.addGestureRecognizer(pan)

            let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
            mtkView.addGestureRecognizer(pinch)

            let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
            mtkView.addGestureRecognizer(tap)
        }

        return mtkView
    }

    public func updateUIView(_ uiView: MTKView, context: Context) {}

    public final class Coordinator: NSObject {
        var parent: HoloMedMetalView
        var renderer: MetalRenderer?
        var sceneController: SceneController?

        private var previousPanTranslation: CGPoint = .zero

        init(_ parent: HoloMedMetalView) {
            self.parent = parent
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let renderer = renderer, let view = gesture.view else { return }

            if gesture.numberOfTouches == 2 {
                // Two-finger Pan
                let translation = gesture.translation(in: view)
                let deltaX = Float(translation.x - previousPanTranslation.x)
                let deltaY = Float(translation.y - previousPanTranslation.y)
                renderer.cameraRig.pan(deltaX: deltaX, deltaY: deltaY)
                previousPanTranslation = translation
            } else {
                // One-finger Orbit
                let translation = gesture.translation(in: view)
                let deltaX = Float(translation.x - previousPanTranslation.x)
                let deltaY = Float(translation.y - previousPanTranslation.y)
                renderer.cameraRig.rotate(deltaX: deltaX, deltaY: deltaY)
                previousPanTranslation = translation
            }

            if gesture.state == .ended || gesture.state == .cancelled {
                previousPanTranslation = .zero
            }
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let renderer = renderer else { return }
            let scaleDelta = Float(gesture.scale)
            renderer.cameraRig.zoom(scaleDelta: scaleDelta)
            gesture.scale = 1.0
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let renderer = renderer, let view = gesture.view else { return }
            let location = gesture.location(in: view)
            let normPoint = CGPoint(x: location.x / view.bounds.width, y: location.y / view.bounds.height)

            if let hitNode = renderer.hitTest(normalizedPoint: normPoint) {
                DispatchQueue.main.async { [weak self] in
                    self?.parent.appState.inspectedStructure = hitNode
                    self?.renderer?.activeHighlightFmaId = hitNode.fmaId
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.parent.appState.inspectedStructure = nil
                    self?.renderer?.activeHighlightFmaId = nil
                }
            }
        }
    }
}
