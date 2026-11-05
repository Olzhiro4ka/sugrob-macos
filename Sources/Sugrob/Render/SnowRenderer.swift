import MetalKit
import SnowCore

/// GPU objects shared by all overlays: compiled once per process.
@MainActor
final class SnowGPU {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let flakePipeline: MTLRenderPipelineState

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            return nil
        }
        do {
            let library = try device.makeLibrary(source: Shaders.source, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "flakeVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "flakeFragment")
            let attachment = descriptor.colorAttachments[0]
            attachment?.pixelFormat = .bgra8Unorm
            // Premultiplied alpha.
            attachment?.isBlendingEnabled = true
            attachment?.rgbBlendOperation = .add
            attachment?.alphaBlendOperation = .add
            attachment?.sourceRGBBlendFactor = .one
            attachment?.sourceAlphaBlendFactor = .one
            attachment?.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            flakePipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            NSLog("Sugrob: failed to build Metal pipeline: \(error)")
            return nil
        }
        self.device = device
        self.queue = queue
    }
}

/// Draws one overlay. Owns a triple-buffered ring of instance buffers; never allocates per frame.
@MainActor
final class SnowRenderer: NSObject, MTKViewDelegate {
    private static let ringSize = 3

    private let gpu: SnowGPU
    private let world: World
    private let screenRect: Rect
    private let buffers: [MTLBuffer]
    private let inFlight = DispatchSemaphore(value: SnowRenderer.ringSize)
    private var ringIndex = 0
    /// Whether the last presented frame had anything in it; lets us skip redundant empty frames.
    private var lastFrameHadContent = true

    /// CPU time spent encoding the last frame (s), for the HUD.
    private(set) var lastEncodeSeconds: Double = 0
    private(set) var lastSpriteCount = 0

    init?(gpu: SnowGPU, world: World, screenFrame: CGRect) {
        self.gpu = gpu
        self.world = world
        screenRect = CoordinateSpace.core(screenFrame)
        let length = MemoryLayout<SIMD4<Float>>.stride * Config.flakeCapacity
        var buffers: [MTLBuffer] = []
        for _ in 0..<Self.ringSize {
            guard let buffer = gpu.device.makeBuffer(length: length, options: .storageModeShared) else { return nil }
            buffers.append(buffer)
        }
        self.buffers = buffers
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let start = CACurrentMediaTime()
        defer { lastEncodeSeconds = CACurrentMediaTime() - start }

        // Never block the main thread on the GPU: drop the frame if all buffers are in flight.
        guard inFlight.wait(timeout: .now()) == .success else { return }

        let buffer = buffers[ringIndex]
        let count = copyVisibleSprites(into: buffer)
        lastSpriteCount = count
        if count == 0 && !lastFrameHadContent {
            inFlight.signal()
            return
        }

        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = gpu.queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass)
        else {
            inFlight.signal()
            return
        }
        ringIndex = (ringIndex + 1) % Self.ringSize

        if count > 0 {
            var uniforms = SIMD4<Float>(screenRect.minX, screenRect.minY, screenRect.width, screenRect.height)
            encoder.setRenderPipelineState(gpu.flakePipeline)
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
        }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        let semaphore = inFlight
        // `@Sendable` so the closure does not inherit main-actor isolation: Metal calls it on its own queue.
        commandBuffer.addCompletedHandler { @Sendable _ in semaphore.signal() }
        commandBuffer.commit()
        lastFrameHadContent = count > 0
    }

    /// Forces the next frame to be presented even if empty (used after resuming from pause).
    func invalidate() {
        lastFrameHadContent = true
    }

    /// Copies flakes that touch this overlay's screen into `buffer`; returns how many.
    private func copyVisibleSprites(into buffer: MTLBuffer) -> Int {
        let flakes = world.flakes
        let destination = buffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: Config.flakeCapacity)
        var written = 0
        flakes.sprites.withUnsafeBufferPointer { sprites in
            for i in 0..<flakes.count {
                let sprite = sprites[i]
                // Generous radius covers the soft halo drawn around the core.
                if screenRect.intersects(circleAt: SIMD2(sprite.x, sprite.y), radius: sprite.z * 2 + 1) {
                    destination[written] = sprite
                    written += 1
                }
            }
        }
        return written
    }
}
