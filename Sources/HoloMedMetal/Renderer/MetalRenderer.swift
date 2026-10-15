import Foundation
import Metal
import MetalKit
import simd

public final class MetalRenderer: NSObject, MTKViewDelegate {
    public let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    // 120 FPS ProMotion Triple-Buffering Semaphore
    private let inFlightSemaphore = DispatchSemaphore(value: 3)
    private var currentBufferIndex: Int = 0
    private static let maxBuffersInFlight = 3

    // Pipeline States
    private var computePipelineState: MTLComputePipelineState!
    private var bloodCellPipelineState: MTLRenderPipelineState!
    private var genericMeshPipelineState: MTLRenderPipelineState!
    private var tissuePipelineState: MTLRenderPipelineState!
    private var blockagePipelineState: MTLRenderPipelineState!
    private var depthStencilState: MTLDepthStencilState!

    // UMA Zero-Copy Buffers
    private var dynamicUniformBuffers: [MTLBuffer] = []
    private var bloodCellBuffer: MTLBuffer!
    private var splineNodeBuffer: MTLBuffer!
    private var blockageParamsBuffer: MTLBuffer!
    private var tissueParamsBuffer: MTLBuffer!

    // Geometry & Scene Assets
    public var meshNodes: [AnatomicalMeshNode] = []
    private var erythrocyteVertexBuffer: MTLBuffer!
    private var erythrocyteIndexBuffer: MTLBuffer!
    private var erythrocyteIndexCount: Int = 0

    // Particle Count (Mad-Scientist Choice: 100,000 Cells in UMA)
    public let cellCount: Int = 100_000
    public var splineWaypoints: [SplineWaypoint] = []

    // Camera Rig
    public let cameraRig: CameraRig = CameraRig()

    // Dynamic State
    public var currentBlockage = BlockageParams(
        center: simd_float3(-0.04, 0.04, 0.18),
        stenosisSeverity: 0.0, // Patent by default
        vesselDirection: simd_float3(0, -1, 0),
        splineProgress: 0.88,  // Proximal LAD location
        plaqueRadius: 0.024,
        thrombusLength: 0.035,
        warningPulse: 0.0,
        padding: 0.0
    )

    public var currentTissue = TissueParams(
        state: TissueStateNormal.rawValue,
        ischemicRatio: 0.0,
        necroticRatio: 0.0,
        inflammationFactor: 0.0,
        lesionCentroid: simd_float3(-0.08, -0.16, 0.04), // LV Apex
        lesionRadius: 0.18,
        hypoxicPulseSpeed: 3.5,
        time: 0.0,
        padding: (0.0, 0.0)
    )

    public var activeHighlightFmaId: String? = nil
    public var isolatedFmaIds: Set<String>? = nil

    private var startTime: CFTimeInterval = 0.0

    public init?(metalView: MTKView) {
        guard let device = metalView.device ?? MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        self.device = device
        self.commandQueue = commandQueue
        super.init()

        // Configure Metal View for 120 FPS ProMotion
        metalView.device = device
        metalView.delegate = self
        metalView.depthStencilPixelFormat = .depth32Float
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.sampleCount = 1
        metalView.preferredFramesPerSecond = 120

        self.startTime = CACurrentMediaTime()

        setupPipelines(metalView: metalView)
        setupBuffers()
        loadGeometry()
    }

    private func setupPipelines(metalView: MTKView) {
        let library: MTLLibrary
        do {
            if let defaultLib = device.makeDefaultLibrary() {
                library = defaultLib
            } else {
                // If compiled via xtool / bundle resource
                guard let bundleLibURL = Bundle.main.url(forResource: "default", withExtension: "metallib"),
                      let bundleLib = try? device.makeLibrary(URL: bundleLibURL) else {
                    fatalError("Unable to load Metal shader library")
                }
                library = bundleLib
            }
        }

        // 1. Compute Pipeline (100,000 Particle Simulation Kernel)
        guard let computeFunc = library.makeFunction(name: "simulate_blood_cells_kernel") else {
            fatalError("Failed to find simulate_blood_cells_kernel in Metal library")
        }
        self.computePipelineState = try! device.makeComputePipelineState(function: computeFunc)

        // 2. Depth Stencil State
        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .less
        depthDesc.isDepthWriteEnabled = true
        self.depthStencilState = device.makeDepthStencilState(descriptor: depthDesc)!

        // 3. Blood Cell Render Pipeline
        let bcDesc = MTLRenderPipelineDescriptor()
        bcDesc.vertexFunction = library.makeFunction(name: "blood_cell_vertex")
        bcDesc.fragmentFunction = library.makeFunction(name: "blood_cell_fragment")
        bcDesc.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        bcDesc.colorAttachments[0].isBlendingEnabled = true
        bcDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        bcDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        bcDesc.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat
        self.bloodCellPipelineState = try! device.makeRenderPipelineState(descriptor: bcDesc)

        // 4. Generic Mesh Pipeline (Organs & Vessels)
        let gmDesc = MTLRenderPipelineDescriptor()
        gmDesc.vertexFunction = library.makeFunction(name: "generic_mesh_vertex")
        gmDesc.fragmentFunction = library.makeFunction(name: "generic_mesh_fragment")
        gmDesc.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        gmDesc.colorAttachments[0].isBlendingEnabled = true
        gmDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        gmDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        gmDesc.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat
        self.genericMeshPipelineState = try! device.makeRenderPipelineState(descriptor: gmDesc)

        // 5. Tissue Ischemia & Necrosis Pipeline
        let tisDesc = MTLRenderPipelineDescriptor()
        tisDesc.vertexFunction = library.makeFunction(name: "tissue_state_vertex")
        tisDesc.fragmentFunction = library.makeFunction(name: "tissue_state_fragment")
        tisDesc.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        tisDesc.colorAttachments[0].isBlendingEnabled = true
        tisDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        tisDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        tisDesc.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat
        self.tissuePipelineState = try! device.makeRenderPipelineState(descriptor: tisDesc)

        // 6. Arterial Blockage Pipeline
        let blkDesc = MTLRenderPipelineDescriptor()
        blkDesc.vertexFunction = library.makeFunction(name: "arterial_blockage_vertex")
        blkDesc.fragmentFunction = library.makeFunction(name: "arterial_blockage_fragment")
        blkDesc.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        blkDesc.colorAttachments[0].isBlendingEnabled = true
        blkDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        blkDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        blkDesc.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat
        self.blockagePipelineState = try! device.makeRenderPipelineState(descriptor: blkDesc)
    }

    private func setupBuffers() {
        // Triple-buffered Uniforms for zero CPU-GPU contention
        for _ in 0..<Self.maxBuffersInFlight {
            let buf = device.makeBuffer(length: MemoryLayout<Uniforms>.stride, options: .storageModeShared)!
            dynamicUniformBuffers.append(buf)
        }

        // Catmull-Rom Spline Waypoints
        self.splineWaypoints = SplineMath.generateCardiovascularCircuit()
        var splinePoints: [SplinePoint] = []
        for (i, wp) in splineWaypoints.enumerated() {
            let tangent: simd_float3
            if i == 0 {
                tangent = simd_normalize(splineWaypoints[1].position - splineWaypoints[0].position)
            } else if i == splineWaypoints.count - 1 {
                tangent = simd_normalize(splineWaypoints[i].position - splineWaypoints[i - 1].position)
            } else {
                tangent = simd_normalize(splineWaypoints[i + 1].position - splineWaypoints[i - 1].position)
            }

            var up = simd_float3(0, 1, 0)
            if abs(simd_dot(tangent, up)) > 0.9 { up = simd_float3(1, 0, 0) }
            let normal = simd_normalize(simd_cross(tangent, up))

            splinePoints.append(SplinePoint(
                position: wp.position,
                lumenRadius: wp.lumenRadius,
                tangent: tangent,
                arcLength: Float(i),
                normal: normal,
                targetSpeed: 0.12
            ))
        }

        self.splineNodeBuffer = device.makeBuffer(
            bytes: splinePoints,
            length: splinePoints.count * MemoryLayout<SplinePoint>.stride,
            options: .storageModeShared
        )!

        // 100,000 Instanced Blood Cells in Apple Silicon UMA (7.63 MB total)
        var cells: [BloodCellInstance] = []
        cells.reserveCapacity(cellCount)

        for i in 0..<cellCount {
            let u = Float(i) / Float(cellCount)
            let radialOffset = sqrtf(Float.random(in: 0.0...0.95)) // Uniform cross-section distribution
            let radialAngle = Float.random(in: 0.0...(Float.pi * 2.0))
            let spinPhase = Float.random(in: -1.0...1.0)
            let scale = Float.random(in: 0.85...1.15)

            cells.append(BloodCellInstance(
                position: simd_float3(0),
                splineProgress: u,
                velocity: simd_float3(0),
                radialOffset: radialOffset,
                orientation: simd_float3(0, 0, 1),
                radialAngle: radialAngle,
                color: simd_float4(0.9, 0.1, 0.1, 1.0),
                scale: scale,
                isBlocked: 0,
                cellType: 0,
                spinPhase: spinPhase
            ))
        }

        self.bloodCellBuffer = device.makeBuffer(
            bytes: cells,
            length: cells.count * MemoryLayout<BloodCellInstance>.stride,
            options: .storageModeShared
        )!

        // Blockage & Tissue Buffers
        self.blockageParamsBuffer = device.makeBuffer(length: MemoryLayout<BlockageParams>.stride, options: .storageModeShared)!
        self.tissueParamsBuffer = device.makeBuffer(length: MemoryLayout<TissueParams>.stride, options: .storageModeShared)!
    }

    private func loadGeometry() {
        let builder = AnatomyMeshBuilder(device: device)
        (self.erythrocyteVertexBuffer, self.erythrocyteIndexBuffer, self.erythrocyteIndexCount) = builder.buildErythrocyteMesh()
        self.meshNodes = builder.buildAnatomicalScene()
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        // Wait for next slot in 120 FPS triple-buffer queue
        _ = inFlightSemaphore.wait(timeout: .distantFuture)

        guard let drawable = view.currentDrawable,
              let renderPassDesc = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            inFlightSemaphore.signal()
            return
        }

        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.inFlightSemaphore.signal()
        }

        let currentTime = CACurrentMediaTime()
        let elapsedTime = Float(currentTime - startTime)
        cameraRig.update(currentTime: currentTime)

        // 1. Zero-Copy Uniform Updates
        currentBufferIndex = (currentBufferIndex + 1) % Self.maxBuffersInFlight
        let uniformBuffer = dynamicUniformBuffers[currentBufferIndex]

        let aspect = Float(view.drawableSize.width / max(1.0, view.drawableSize.height))
        let projMatrix = cameraRig.getProjectionMatrix(aspect: aspect)
        let viewMatrix = cameraRig.getViewMatrix()
        let modelMatrix = matrix_identity_float4x4
        let normMatrix = MatrixMath.normalMatrix(from: modelMatrix)

        var uniforms = Uniforms(
            projectionMatrix: projMatrix,
            viewMatrix: viewMatrix,
            modelMatrix: modelMatrix,
            normalMatrix: normMatrix,
            cameraPosition: cameraRig.eye,
            time: elapsedTime,
            lightDirection: simd_normalize(simd_float3(0.5, 1.0, 0.7)),
            ambientIntensity: 0.35,
            highlightColor: simd_float4(0.2, 0.85, 1.0, 1.0),
            highlightIntensity: 0.0,
            occlusionAlpha: 1.0,
            padding: (0.0, 0.0)
        )

        let uPtr = uniformBuffer.contents().bindMemory(to: Uniforms.self, capacity: 1)
        uPtr.pointee = uniforms

        // Update Blockage & Tissue Uniforms
        currentBlockage.warningPulse = elapsedTime
        let bPtr = blockageParamsBuffer.contents().bindMemory(to: BlockageParams.self, capacity: 1)
        bPtr.pointee = currentBlockage

        currentTissue.time = elapsedTime
        let tPtr = tissueParamsBuffer.contents().bindMemory(to: TissueParams.self, capacity: 1)
        tPtr.pointee = currentTissue

        // 2. DISPATCH COMPUTE PASS: 100,000 Blood Cell Simulation on GPU
        if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
            computeEncoder.setComputePipelineState(computePipelineState)
            computeEncoder.setBuffer(bloodCellBuffer, offset: 0, index: Int(BufferIndexBloodCells.rawValue))
            computeEncoder.setBuffer(splineNodeBuffer, offset: 0, index: Int(BufferIndexSplineNodes.rawValue))
            computeEncoder.setBuffer(blockageParamsBuffer, offset: 0, index: Int(BufferIndexBlockageParams.rawValue))
            computeEncoder.setBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))

            var nodeCount = UInt32(splineWaypoints.count)
            computeEncoder.setBytes(&nodeCount, length: MemoryLayout<UInt32>.stride, index: 4)

            var totalCells = UInt32(cellCount)
            computeEncoder.setBytes(&totalCells, length: MemoryLayout<UInt32>.stride, index: 5)

            let threadGroupSize = MTLSize(width: min(computePipelineState.maxTotalThreadsPerThreadgroup, 256), height: 1, depth: 1)
            let threadGroups = MTLSize(width: (cellCount + threadGroupSize.width - 1) / threadGroupSize.width, height: 1, depth: 1)
            computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
            computeEncoder.endEncoding()
        }

        // 3. DISPATCH RENDER PASS: Organs, Blockage, Tissue, and 100,000 Instanced Cells
        if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) {
            renderEncoder.setDepthStencilState(depthStencilState)

            // A. Draw Anatomical Organs
            for node in meshNodes {
                let isIsolated = isolatedFmaIds == nil || isolatedFmaIds!.contains(node.fmaId)
                let isHighlighted = activeHighlightFmaId == node.fmaId

                // Determine pipeline: Left Ventricle gets TissueStateShader when in pathology mode
                if node.fmaId == "FMA_7097" && currentTissue.state != TissueStateNormal.rawValue {
                    renderEncoder.setRenderPipelineState(tissuePipelineState)
                    renderEncoder.setVertexBuffer(node.vertexBuffer, offset: 0, index: Int(BufferIndexMeshPositions.rawValue))
                    renderEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))
                    renderEncoder.setVertexBuffer(tissueParamsBuffer, offset: 0, index: Int(BufferIndexTissueParams.rawValue))
                    renderEncoder.setFragmentBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))
                    renderEncoder.setFragmentBuffer(tissueParamsBuffer, offset: 0, index: Int(BufferIndexTissueParams.rawValue))
                } else {
                    renderEncoder.setRenderPipelineState(genericMeshPipelineState)
                    renderEncoder.setVertexBuffer(node.vertexBuffer, offset: 0, index: Int(BufferIndexMeshPositions.rawValue))
                    renderEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))
                    renderEncoder.setFragmentBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))

                    // Update per-mesh uniforms (occlusion alpha & highlights)
                    var nodeUniforms = uniforms
                    nodeUniforms.highlightIntensity = isHighlighted ? 0.95 : 0.0
                    nodeUniforms.occlusionAlpha = isIsolated ? (node.isOccluder ? node.currentOpacity : 1.0) : 0.06
                    uPtr.pointee = nodeUniforms
                }

                renderEncoder.drawIndexedPrimitives(
                    type: .triangle,
                    indexCount: node.indexCount,
                    indexType: .uint16,
                    indexBuffer: node.indexBuffer,
                    indexBufferOffset: 0
                )
            }

            // B. Draw Arterial Plaque / Thrombus Blockage if present
            if currentBlockage.stenosisSeverity > 0.05 {
                renderEncoder.setRenderPipelineState(blockagePipelineState)
                renderEncoder.setVertexBuffer(erythrocyteVertexBuffer, offset: 0, index: Int(BufferIndexMeshPositions.rawValue))
                renderEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))
                renderEncoder.setVertexBuffer(blockageParamsBuffer, offset: 0, index: Int(BufferIndexBlockageParams.rawValue))
                renderEncoder.setFragmentBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))
                renderEncoder.setFragmentBuffer(blockageParamsBuffer, offset: 0, index: Int(BufferIndexBlockageParams.rawValue))

                renderEncoder.drawIndexedPrimitives(
                    type: .triangle,
                    indexCount: erythrocyteIndexCount,
                    indexType: .uint16,
                    indexBuffer: erythrocyteIndexBuffer,
                    indexBufferOffset: 0
                )
            }

            // C. Draw 100,000 Instanced Erythrocytes along Spline
            renderEncoder.setRenderPipelineState(bloodCellPipelineState)
            renderEncoder.setVertexBuffer(erythrocyteVertexBuffer, offset: 0, index: Int(BufferIndexMeshPositions.rawValue))
            renderEncoder.setVertexBuffer(bloodCellBuffer, offset: 0, index: Int(BufferIndexBloodCells.rawValue))
            renderEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))
            renderEncoder.setFragmentBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))

            renderEncoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: erythrocyteIndexCount,
                indexType: .uint16,
                indexBuffer: erythrocyteIndexBuffer,
                indexBufferOffset: 0,
                instanceCount: cellCount
            )

            renderEncoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Raycast Hit Testing for Tap-to-Inspect

    public func hitTest(normalizedPoint: CGPoint) -> AnatomicalMeshNode? {
        let viewMatrix = cameraRig.getViewMatrix()
        let projMatrix = cameraRig.getProjectionMatrix(aspect: 1.0)
        let invVP = (projMatrix * viewMatrix).inverse

        let ndcX = Float(normalizedPoint.x * 2.0 - 1.0)
        let ndcY = Float((1.0 - normalizedPoint.y) * 2.0 - 1.0)

        let nearPt = invVP * simd_float4(ndcX, ndcY, 0.0, 1.0)
        let farPt = invVP * simd_float4(ndcX, ndcY, 1.0, 1.0)
        let rayOrigin = simd_float3(nearPt.x / nearPt.w, nearPt.y / nearPt.w, nearPt.z / nearPt.w)
        let rayEnd = simd_float3(farPt.x / farPt.w, farPt.y / farPt.w, farPt.z / farPt.w)
        let rayDir = simd_normalize(rayEnd - rayOrigin)

        var closestNode: AnatomicalMeshNode? = nil
        var closestDist: Float = Float.infinity

        for node in meshNodes where !node.isOccluder {
            let toCenter = node.centroid - rayOrigin
            let proj = simd_dot(toCenter, rayDir)
            if proj < 0 { continue }

            let perp = toCenter - rayDir * proj
            let distSq = simd_dot(perp, perp)

            if distSq <= (node.boundingRadius * node.boundingRadius) {
                if proj < closestDist {
                    closestDist = proj
                    closestNode = node
                }
            }
        }

        return closestNode
    }
}
