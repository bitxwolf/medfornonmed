import Foundation
import Metal
import simd

public struct AnatomicalMeshNode {
    public let fmaId: String
    public let commonName: String
    public let latinName: String
    public let organSystem: String
    public let vertexBuffer: MTLBuffer
    public let indexBuffer: MTLBuffer
    public let indexCount: Int
    public let centroid: simd_float3
    public let boundingRadius: Float
    public var isOccluder: Bool
    public var currentOpacity: Float
    public var isHighlighted: Bool

    public init(fmaId: String,
                commonName: String,
                latinName: String,
                organSystem: String,
                vertexBuffer: MTLBuffer,
                indexBuffer: MTLBuffer,
                indexCount: Int,
                centroid: simd_float3,
                boundingRadius: Float,
                isOccluder: Bool = false,
                currentOpacity: Float = 1.0,
                isHighlighted: Bool = false) {
        self.fmaId = fmaId
        self.commonName = commonName
        self.latinName = latinName
        self.organSystem = organSystem
        self.vertexBuffer = vertexBuffer
        self.indexBuffer = indexBuffer
        self.indexCount = indexCount
        self.centroid = centroid
        self.boundingRadius = boundingRadius
        self.isOccluder = isOccluder
        self.currentOpacity = currentOpacity
        self.isHighlighted = isHighlighted
    }
}

public final class AnatomyMeshBuilder {
    private let device: MTLDevice

    public init(device: MTLDevice) {
        self.device = device
    }

    /// Generates Evans-Fung biconcave erythrocyte geometry
    public func buildErythrocyteMesh() -> (MTLBuffer, MTLBuffer, Int) {
        var vertices: [VertexIn] = []
        var indices: [UInt16] = []

        let rings = 12
        let segments = 24
        let radius: Float = 0.015

        for r in 0...rings {
            let u = Float(r) / Float(rings)
            let currRadius = u * radius
            // Evans-Fung biconcave shape factor: thinner in the center (dimple) and thicker at the rim
            let dimple = 0.35 + 1.8 * (u * u) - 1.2 * (u * u * u * u)
            let halfThickness = 0.005 * dimple * sqrt(max(0.0, 1.0 - u * u))

            for s in 0..<segments {
                let theta = (Float(s) / Float(segments)) * Float.pi * 2.0
                let cosT = cosf(theta)
                let sinT = sinf(theta)

                // Top surface vertex
                let posTop = simd_float3(currRadius * cosT, halfThickness, currRadius * sinT)
                let normTop = simd_normalize(simd_float3(0, 1.0, 0) + posTop * 0.5)
                vertices.append(VertexIn(position: posTop, normal: normTop, texCoords: simd_float2(u, Float(s) / Float(segments))))

                // Bottom surface vertex
                let posBot = simd_float3(currRadius * cosT, -halfThickness, currRadius * sinT)
                let normBot = simd_normalize(simd_float3(0, -1.0, 0) + posBot * 0.5)
                vertices.append(VertexIn(position: posBot, normal: normBot, texCoords: simd_float2(u, Float(s) / Float(segments))))
            }
        }

        // Build triangle indices
        for r in 0..<rings {
            for s in 0..<segments {
                let nextS = (s + 1) % segments
                let currentRingOffset = r * segments * 2
                let nextRingOffset = (r + 1) * segments * 2

                // Top face triangle 1 & 2
                let t0 = UInt16(currentRingOffset + s * 2)
                let t1 = UInt16(nextRingOffset + s * 2)
                let t2 = UInt16(nextRingOffset + nextS * 2)
                let t3 = UInt16(currentRingOffset + nextS * 2)

                indices.append(t0); indices.append(t1); indices.append(t2)
                indices.append(t0); indices.append(t2); indices.append(t3)

                // Bottom face triangle 1 & 2
                let b0 = UInt16(currentRingOffset + s * 2 + 1)
                let b1 = UInt16(nextRingOffset + s * 2 + 1)
                let b2 = UInt16(nextRingOffset + nextS * 2 + 1)
                let b3 = UInt16(currentRingOffset + nextS * 2 + 1)

                indices.append(b0); indices.append(b2); indices.append(b1)
                indices.append(b0); indices.append(b3); indices.append(b2)
            }
        }

        let vBuf = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<VertexIn>.stride, options: .storageModeShared)!
        let iBuf = device.makeBuffer(bytes: indices, length: indices.count * MemoryLayout<UInt16>.stride, options: .storageModeShared)!

        return (vBuf, iBuf, indices.count)
    }

    /// Generates complete anatomical multi-organ scene mapped to canonical FMA identifiers
    public func buildAnatomicalScene() -> [AnatomicalMeshNode] {
        var nodes: [AnatomicalMeshNode] = []

        // 1. Left Ventricle (FMA_7097) - Primary systemic pump & site of myocardial infarction
        let (lvV, lvI, lvC) = buildEllipsoidMesh(radius: simd_float3(0.12, 0.18, 0.12), center: simd_float3(-0.08, -0.16, 0.04))
        nodes.append(AnatomicalMeshNode(
            fmaId: "FMA_7097",
            commonName: "Left Ventricle",
            latinName: "Ventriculus sinister cordis",
            organSystem: "cardiovascular",
            vertexBuffer: lvV,
            indexBuffer: lvI,
            indexCount: lvC,
            centroid: simd_float3(-0.08, -0.16, 0.04),
            boundingRadius: 0.18
        ))

        // 2. Right Ventricle (FMA_7098) - Pumps to pulmonary bed
        let (rvV, rvI, rvC) = buildEllipsoidMesh(radius: simd_float3(0.10, 0.15, 0.10), center: simd_float3(0.06, -0.14, 0.10))
        nodes.append(AnatomicalMeshNode(
            fmaId: "FMA_7098",
            commonName: "Right Ventricle",
            latinName: "Ventriculus dexter cordis",
            organSystem: "cardiovascular",
            vertexBuffer: rvV,
            indexBuffer: rvI,
            indexCount: rvC,
            centroid: simd_float3(0.06, -0.14, 0.10),
            boundingRadius: 0.15
        ))

        // 3. Right Atrium (FMA_7096) - Receives deoxygenated venous return
        let (raV, raI, raC) = buildEllipsoidMesh(radius: simd_float3(0.09, 0.10, 0.09), center: simd_float3(0.14, 0.10, 0.08))
        nodes.append(AnatomicalMeshNode(
            fmaId: "FMA_7096",
            commonName: "Right Atrium",
            latinName: "Atrium dextrum cordis",
            organSystem: "cardiovascular",
            vertexBuffer: raV,
            indexBuffer: raI,
            indexCount: raC,
            centroid: simd_float3(0.14, 0.10, 0.08),
            boundingRadius: 0.11
        ))

        // 4. Left Atrium (FMA_7099) - Receives oxygenated pulmonary return
        let (laV, laI, laC) = buildEllipsoidMesh(radius: simd_float3(0.085, 0.095, 0.085), center: simd_float3(-0.06, 0.08, -0.08))
        nodes.append(AnatomicalMeshNode(
            fmaId: "FMA_7099",
            commonName: "Left Atrium",
            latinName: "Atrium sinistrum cordis",
            organSystem: "cardiovascular",
            vertexBuffer: laV,
            indexBuffer: laI,
            indexCount: laC,
            centroid: simd_float3(-0.06, 0.08, -0.08),
            boundingRadius: 0.10
        ))

        // 5. Ascending Aorta & Arch (FMA_3734) - High-pressure systemic trunk
        let aortaPoints = [
            simd_float3(0.00, 0.02, 0.02),
            simd_float3(0.04, 0.18, 0.00),
            simd_float3(0.02, 0.32, -0.06),
            simd_float3(-0.04, 0.38, -0.12),
            simd_float3(-0.08, 0.28, -0.16)
        ]
        let (aoV, aoI, aoC) = buildTubeMesh(controlPoints: aortaPoints, radius: 0.045)
        nodes.append(AnatomicalMeshNode(
            fmaId: "FMA_3734",
            commonName: "Aorta",
            latinName: "Aorta ascendens et arcus aortae",
            organSystem: "cardiovascular",
            vertexBuffer: aoV,
            indexBuffer: aoI,
            indexCount: aoC,
            centroid: simd_float3(0.0, 0.22, -0.05),
            boundingRadius: 0.24
        ))

        // 6. Left Anterior Descending (LAD) Coronary Artery (FMA_7101) - "The Widowmaker"
        let ladPoints = [
            simd_float3(-0.02, 0.14, 0.14),
            simd_float3(-0.04, 0.04, 0.18),
            simd_float3(-0.06, -0.08, 0.17),
            simd_float3(-0.07, -0.20, 0.12)
        ]
        let (ladV, ladI, ladC) = buildTubeMesh(controlPoints: ladPoints, radius: 0.012)
        nodes.append(AnatomicalMeshNode(
            fmaId: "FMA_7101",
            commonName: "Left Anterior Descending Coronary Artery",
            latinName: "Ramus interventricularis anterior arteriae coronariae sinistrae",
            organSystem: "cardiovascular",
            vertexBuffer: ladV,
            indexBuffer: ladI,
            indexCount: ladC,
            centroid: simd_float3(-0.05, -0.02, 0.16),
            boundingRadius: 0.14
        ))

        // 7. Right Coronary Artery (FMA_7100)
        let rcaPoints = [
            simd_float3(0.04, 0.12, 0.10),
            simd_float3(0.12, 0.02, 0.11),
            simd_float3(0.14, -0.10, 0.08),
            simd_float3(0.08, -0.22, 0.02)
        ]
        let (rcaV, rcaI, rcaC) = buildTubeMesh(controlPoints: rcaPoints, radius: 0.012)
        nodes.append(AnatomicalMeshNode(
            fmaId: "FMA_7100",
            commonName: "Right Coronary Artery",
            latinName: "Arteria coronaria dextra",
            organSystem: "cardiovascular",
            vertexBuffer: rcaV,
            indexBuffer: rcaI,
            indexCount: rcaC,
            centroid: simd_float3(0.10, -0.04, 0.08),
            boundingRadius: 0.15
        ))

        // 8. Left Lung (FMA_7310) - Bilobed pulmonary structure flanking heart
        let (llV, llI, llC) = buildEllipsoidMesh(radius: simd_float3(0.18, 0.32, 0.18), center: simd_float3(-0.42, 0.02, -0.04))
        nodes.append(AnatomicalMeshNode(
            fmaId: "FMA_7310",
            commonName: "Left Lung",
            latinName: "Pulmo sinister",
            organSystem: "respiratory",
            vertexBuffer: llV,
            indexBuffer: llI,
            indexCount: llC,
            centroid: simd_float3(-0.42, 0.02, -0.04),
            boundingRadius: 0.35,
            isOccluder: true,
            currentOpacity: 0.15
        ))

        // 9. Right Lung (FMA_7309) - Trilobed pulmonary structure
        let (rlV, rlI, rlC) = buildEllipsoidMesh(radius: simd_float3(0.20, 0.34, 0.20), center: simd_float3(0.44, 0.04, -0.04))
        nodes.append(AnatomicalMeshNode(
            fmaId: "FMA_7309",
            commonName: "Right Lung",
            latinName: "Pulmo dexter",
            organSystem: "respiratory",
            vertexBuffer: rlV,
            indexBuffer: rlI,
            indexCount: rlC,
            centroid: simd_float3(0.44, 0.04, -0.04),
            boundingRadius: 0.38,
            isOccluder: true,
            currentOpacity: 0.15
        ))

        // 10. Ribcage & Sternum (FMA_7480) - Superficial thoracic cage (Occluder)
        let (ribV, ribI, ribC) = buildRibcageMesh()
        nodes.append(AnatomicalMeshNode(
            fmaId: "FMA_7480",
            commonName: "Thoracic Ribcage and Sternum",
            latinName: "Cavea thoracis et sternum",
            organSystem: "skeletal",
            vertexBuffer: ribV,
            indexBuffer: ribI,
            indexCount: ribC,
            centroid: simd_float3(0.0, 0.0, 0.30),
            boundingRadius: 0.60,
            isOccluder: true,
            currentOpacity: 0.08 // X-ray mode by default
        ))

        return nodes
    }

    /// Procedural procedural parametric ellipsoid mesh
    private func buildEllipsoidMesh(radius: simd_float3, center: simd_float3, rings: Int = 18, sectors: Int = 24) -> (MTLBuffer, MTLBuffer, Int) {
        var vertices: [VertexIn] = []
        var indices: [UInt16] = []

        let rInv = 1.0 / Float(rings)
        let sInv = 1.0 / Float(sectors)

        for r in 0...rings {
            let phi = Float.pi * Float(r) * rInv
            let y = cosf(phi) * radius.y
            let sinPhi = sinf(phi)

            for s in 0...sectors {
                let theta = 2.0 * Float.pi * Float(s) * sInv
                let x = sinPhi * cosf(theta) * radius.x
                let z = sinPhi * sinf(theta) * radius.z

                let pos = center + simd_float3(x, y, z)
                let norm = simd_normalize(simd_float3(x / (radius.x * radius.x), y / (radius.y * radius.y), z / (radius.z * radius.z)))
                let uv = simd_float2(Float(s) * sInv, Float(r) * rInv)

                vertices.append(VertexIn(position: pos, normal: norm, texCoords: uv))
            }
        }

        for r in 0..<rings {
            for s in 0..<sectors {
                let first = UInt16((r * (sectors + 1)) + s)
                let second = UInt16(first + UInt16(sectors + 1))

                indices.append(first)
                indices.append(second)
                indices.append(first + 1)

                indices.append(second)
                indices.append(second + 1)
                indices.append(first + 1)
            }
        }

        let vBuf = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<VertexIn>.stride, options: .storageModeShared)!
        let iBuf = device.makeBuffer(bytes: indices, length: indices.count * MemoryLayout<UInt16>.stride, options: .storageModeShared)!
        return (vBuf, iBuf, indices.count)
    }

    /// Extrudes tube geometry along 3D centerline path (for vessels)
    private func buildTubeMesh(controlPoints: [simd_float3], radius: Float, sides: Int = 16) -> (MTLBuffer, MTLBuffer, Int) {
        var vertices: [VertexIn] = []
        var indices: [UInt16] = []

        guard controlPoints.count >= 2 else {
            return buildEllipsoidMesh(radius: simd_float3(radius), center: simd_float3(0))
        }

        for (i, p) in controlPoints.enumerated() {
            let tangent: simd_float3
            if i == 0 {
                tangent = simd_normalize(controlPoints[1] - controlPoints[0])
            } else if i == controlPoints.count - 1 {
                tangent = simd_normalize(controlPoints[i] - controlPoints[i - 1])
            } else {
                tangent = simd_normalize(controlPoints[i + 1] - controlPoints[i - 1])
            }

            var up = simd_float3(0, 1, 0)
            if abs(simd_dot(tangent, up)) > 0.9 {
                up = simd_float3(1, 0, 0)
            }
            let right = simd_normalize(simd_cross(tangent, up))
            let normal = simd_cross(right, tangent)

            for s in 0...sides {
                let angle = (Float(s) / Float(sides)) * Float.pi * 2.0
                let offset = (cosf(angle) * right + sinf(angle) * normal) * radius
                let pos = p + offset
                let norm = simd_normalize(offset)
                let uv = simd_float2(Float(s) / Float(sides), Float(i) / Float(controlPoints.count - 1))
                vertices.append(VertexIn(position: pos, normal: norm, texCoords: uv))
            }
        }

        for i in 0..<(controlPoints.count - 1) {
            for s in 0..<sides {
                let current = UInt16(i * (sides + 1) + s)
                let next = UInt16((i + 1) * (sides + 1) + s)

                indices.append(current)
                indices.append(next)
                indices.append(current + 1)

                indices.append(next)
                indices.append(next + 1)
                indices.append(current + 1)
            }
        }

        let vBuf = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<VertexIn>.stride, options: .storageModeShared)!
        let iBuf = device.makeBuffer(bytes: indices, length: indices.count * MemoryLayout<UInt16>.stride, options: .storageModeShared)!
        return (vBuf, iBuf, indices.count)
    }

    /// Procedural ribcage and sternum cage
    private func buildRibcageMesh() -> (MTLBuffer, MTLBuffer, Int) {
        var vertices: [VertexIn] = []
        var indices: [UInt16] = []

        // Sternum in center
        let sternumTop = simd_float3(0, 0.30, 0.26)
        let sternumBottom = simd_float3(0, -0.15, 0.28)
        let sternumPts = [sternumTop, sternumBottom]
        let (stV, stI, stC) = buildTubeMesh(controlPoints: sternumPts, radius: 0.025, sides: 8)

        // Multiple bilateral rib rings curving around the thoracic cage
        let ribLevels: [Float] = [0.25, 0.18, 0.10, 0.02, -0.06, -0.14]
        for yLevel in ribLevels {
            // Right rib
            var rPts: [simd_float3] = []
            for a in 0...12 {
                let theta = (Float(a) / 12.0) * Float.pi * 0.75
                let x = sinf(theta) * 0.38
                let z = cosf(theta) * 0.28
                rPts.append(simd_float3(x, yLevel - Float(a) * 0.008, z))
            }
            let (rV, rI, rC) = buildTubeMesh(controlPoints: rPts, radius: 0.012, sides: 6)
            appendMesh(toVertices: &vertices, toIndices: &indices, fromBuffer: rV, fromIndexBuffer: rI, count: rC)

            // Left rib
            var lPts: [simd_float3] = []
            for a in 0...12 {
                let theta = (Float(a) / 12.0) * Float.pi * 0.75
                let x = -sinf(theta) * 0.38
                let z = cosf(theta) * 0.28
                lPts.append(simd_float3(x, yLevel - Float(a) * 0.008, z))
            }
            let (lV, lI, lC) = buildTubeMesh(controlPoints: lPts, radius: 0.012, sides: 6)
            appendMesh(toVertices: &vertices, toIndices: &indices, fromBuffer: lV, fromIndexBuffer: lI, count: lC)
        }

        appendMesh(toVertices: &vertices, toIndices: &indices, fromBuffer: stV, fromIndexBuffer: stI, count: stC)

        let vBuf = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<VertexIn>.stride, options: .storageModeShared)!
        let iBuf = device.makeBuffer(bytes: indices, length: indices.count * MemoryLayout<UInt16>.stride, options: .storageModeShared)!
        return (vBuf, iBuf, indices.count)
    }

    private func appendMesh(toVertices: inout [VertexIn], toIndices: inout [UInt16], fromBuffer: MTLBuffer, fromIndexBuffer: MTLBuffer, count: Int) {
        let vCount = fromBuffer.length / MemoryLayout<VertexIn>.stride
        let baseIndex = UInt16(toVertices.count)

        let vPtr = fromBuffer.contents().bindMemory(to: VertexIn.self, capacity: vCount)
        for i in 0..<vCount {
            toVertices.append(vPtr[i])
        }

        let iPtr = fromIndexBuffer.contents().bindMemory(to: UInt16.self, capacity: count)
        for i in 0..<count {
            toIndices.append(baseIndex + iPtr[i])
        }
    }
}
