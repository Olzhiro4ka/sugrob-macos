import MetalKit
import SnowCore

/// Matches `Uniforms` in Shaders.swift.
struct RenderUniforms {
    var originAndSize: SIMD4<Float>
    var scaleAndPad: SIMD4<Float>
}

/// GPU objects shared by all overlays: compiled once per process.
@MainActor
final class SnowGPU {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let flakePipeline: MTLRenderPipelineState
    let capPipeline: MTLRenderPipelineState
    let debrisPipeline: MTLRenderPipelineState
    let rectPipeline: MTLRenderPipelineState
    let plowPipeline: MTLRenderPipelineState
    let plowTexture: MTLTexture

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            return nil
        }
        do {
            let library = try device.makeLibrary(source: Shaders.source, options: nil)
            func pipeline(_ vertex: String, _ fragment: String) throws -> MTLRenderPipelineState {
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = library.makeFunction(name: vertex)
                descriptor.fragmentFunction = library.makeFunction(name: fragment)
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
                return try device.makeRenderPipelineState(descriptor: descriptor)
            }
            flakePipeline = try pipeline("flakeVertex", "flakeFragment")
            capPipeline = try pipeline("capVertex", "capFragment")
            debrisPipeline = try pipeline("debrisVertex", "debrisFragment")
            rectPipeline = try pipeline("rectVertex", "rectFragment")
            plowPipeline = try pipeline("plowVertex", "plowFragment")
            let spriteURL = Bundle.main.url(forResource: "SnowplowVariant2", withExtension: "png")
                ?? URL(fileURLWithPath: "Resources/SnowplowVariant2.png")
            plowTexture = try MTKTextureLoader(device: device).newTexture(
                URL: spriteURL,
                options: [.SRGB: false, .origin: MTKTextureLoader.Origin.topLeft]
            )
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
    /// Cap column segments per frame per overlay (each 32 B).
    private static let maxCapSegments = 32_768
    /// Debug rectangles per frame per overlay (each 32 B).
    private static let maxDebugRects = 4096

    private struct Slot {
        let flakes: MTLBuffer
        let caps: MTLBuffer
        let debris: MTLBuffer
        let debug: MTLBuffer
        let plows: MTLBuffer
    }

    private let gpu: SnowGPU
    private let world: World
    private let screenRect: Rect
    private let scale: Float
    private let slots: [Slot]
    private let inFlight = DispatchSemaphore(value: SnowRenderer.ringSize)
    private var ringIndex = 0
    /// Whether the last presented frame had anything in it; lets us skip redundant empty frames.
    private var lastFrameHadContent = true

    var debugSurfaces = false

    /// CPU time spent encoding the last frame (s), for the HUD.
    private(set) var lastEncodeSeconds: Double = 0
    private(set) var lastCapSegments = 0
    /// Frames skipped because every ring buffer was still in flight (count, for the HUD).
    private(set) var droppedFrames = 0
    /// Frames committed to the GPU since launch (count); used to prove pauses do no GPU work.
    private(set) var presentedFrames = 0

    init?(gpu: SnowGPU, world: World, screen: NSScreen) {
        self.gpu = gpu
        self.world = world
        screenRect = CoordinateSpace.core(screen.frame)
        scale = Float(screen.backingScaleFactor)
        let vectorSize = MemoryLayout<SIMD4<Float>>.stride
        var slots: [Slot] = []
        for _ in 0..<Self.ringSize {
            guard let flakes = gpu.device.makeBuffer(length: vectorSize * Config.flakeCapacity, options: .storageModeShared),
                  let caps = gpu.device.makeBuffer(length: vectorSize * 2 * Self.maxCapSegments, options: .storageModeShared),
                  let debris = gpu.device.makeBuffer(length: vectorSize * 2 * Config.debrisCapacity, options: .storageModeShared),
                  let debug = gpu.device.makeBuffer(length: vectorSize * 2 * Self.maxDebugRects, options: .storageModeShared),
                  let plows = gpu.device.makeBuffer(length: vectorSize * 32, options: .storageModeShared)
            else { return nil }
            slots.append(Slot(flakes: flakes, caps: caps, debris: debris, debug: debug,
                              plows: plows))
        }
        self.slots = slots
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let start = CACurrentMediaTime()
        defer { lastEncodeSeconds = CACurrentMediaTime() - start }

        // Never block the main thread on the GPU: drop the frame if all buffers are in flight.
        guard inFlight.wait(timeout: .now()) == .success else {
            droppedFrames += 1
            return
        }

        let slot = slots[ringIndex]
        let flakeCount = writeFlakes(into: slot.flakes)
        let capCount = writeCapSegments(into: slot.caps)
        let debrisCount = writeDebris(into: slot.debris)
        let debugCount = debugSurfaces ? writeDebugRects(into: slot.debug) : 0
        let plowCount = writePlows(into: slot.plows, time: start)
        lastCapSegments = capCount
        let hasContent = flakeCount + capCount + debrisCount + debugCount + plowCount > 0
        if !hasContent && !lastFrameHadContent {
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

        var uniforms = RenderUniforms(
            originAndSize: SIMD4(screenRect.minX, screenRect.minY, screenRect.width, screenRect.height),
            scaleAndPad: SIMD4(scale, 0, 0, 0)
        )
        let uniformLength = MemoryLayout<RenderUniforms>.stride
        func draw(_ pipeline: MTLRenderPipelineState, _ buffer: MTLBuffer, _ count: Int) {
            guard count > 0 else { return }
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: uniformLength, index: 1)
            encoder.setFragmentBytes(&uniforms, length: uniformLength, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
        }
        draw(gpu.capPipeline, slot.caps, capCount)
        draw(gpu.flakePipeline, slot.flakes, flakeCount)
        draw(gpu.debrisPipeline, slot.debris, debrisCount)
        encoder.setFragmentTexture(gpu.plowTexture, index: 0)
        draw(gpu.plowPipeline, slot.plows, plowCount)
        draw(gpu.rectPipeline, slot.debug, debugCount)

        encoder.endEncoding()
        commandBuffer.present(drawable)
        let semaphore = inFlight
        // `@Sendable` so the closure does not inherit main-actor isolation: Metal calls it on its own queue.
        commandBuffer.addCompletedHandler { @Sendable _ in semaphore.signal() }
        commandBuffer.commit()
        presentedFrames += 1
        lastFrameHadContent = hasContent
    }

    /// Forces the next frame to be presented even if empty (used after resuming from pause).
    func invalidate() {
        lastFrameHadContent = true
    }

    // MARK: Instance data

    private func writePlows(into buffer: MTLBuffer, time: CFTimeInterval) -> Int {
        let destination = buffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: 32)
        var count = 0
        for plow in world.plows where plow.screenIndex < 16 {
            let size = Config.plowSize
            guard screenRect.intersects(circleAt: SIMD2(plow.x + size.x / 2, plow.y + size.y / 2),
                                        radius: size.x) else { continue }
            destination[count * 2] = SIMD4(plow.x, plow.y, size.x, size.y)
            destination[count * 2 + 1] = SIMD4(plow.bladeLoad, Float(time.truncatingRemainder(dividingBy: 1.5) / 1.5), 0, 0)
            count += 1
        }
        return count
    }

    /// Copies flakes that touch this overlay's screen; returns how many.
    private func writeFlakes(into buffer: MTLBuffer) -> Int {
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

    /// Copies debris particles that touch this overlay's screen as (sprite, velocity) pairs.
    private func writeDebris(into buffer: MTLBuffer) -> Int {
        let debris = world.debris
        guard debris.count > 0 else { return 0 }
        let destination = buffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: Config.debrisCapacity * 2)
        var written = 0
        debris.sprites.withUnsafeBufferPointer { sprites in
            debris.velocities.withUnsafeBufferPointer { velocities in
                for i in 0..<debris.count {
                    let sprite = sprites[i]
                    // Streaks reach up to ~16 pt behind the particle.
                    guard screenRect.intersects(circleAt: SIMD2(sprite.x, sprite.y), radius: 20) else { continue }
                    let velocity = velocities[i]
                    destination[written * 2] = sprite
                    destination[written * 2 + 1] = SIMD4(velocity.x, velocity.y, 0, 0)
                    written += 1
                }
            }
        }
        return written
    }

    /// One instance per heightmap column segment inside a visible interval, clipped to it.
    private func writeCapSegments(into buffer: MTLBuffer) -> Int {
        let destination = buffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: Self.maxCapSegments * 2)
        var written = 0
        let screen = screenRect
        for cap in world.caps where cap.isPresent && !cap.visible.isEmpty {
            let frame = cap.frame
            guard frame.maxX > screen.minX, frame.minX < screen.maxX,
                  frame.maxY + cap.maxHeight + 2 > screen.minY,
                  frame.maxY - cap.cornerRadius - 2 < screen.maxY
            else { continue }
            let heights = cap.heights
            let base = cap.base
            let spacing = cap.spacing
            let edge = cap.edgeY
            let last = cap.columnCount - 1
            for interval in cap.visible {
                let lower = max(interval.lower, screen.minX)
                let upper = min(interval.upper, screen.maxX)
                guard upper > lower else { continue }
                let first = max(0, Int((lower - frame.minX) / spacing))
                let end = min(last, Int(((upper - frame.minX) / spacing).rounded(.up)))
                guard end > first else { continue }
                for column in first..<end {
                    let h0 = heights[column]
                    let h1 = heights[column + 1]
                    guard h0 > 0.05 || h1 > 0.05 else { continue }
                    guard written < Self.maxCapSegments else { return written }
                    let xa = frame.minX + Float(column) * spacing
                    let xb = xa + spacing
                    let x0 = max(xa, lower)
                    let x1 = min(xb, upper)
                    let t0 = (x0 - xa) / spacing
                    let t1 = (x1 - xa) / spacing
                    let base0 = edge + base[column] + (base[column + 1] - base[column]) * t0
                    let base1 = edge + base[column] + (base[column + 1] - base[column]) * t1
                    let top0 = base0 + h0 + (h1 - h0) * t0
                    let top1 = base1 + h0 + (h1 - h0) * t1
                    destination[written * 2] = SIMD4(x0, x1, base0, base1)
                    destination[written * 2 + 1] = SIMD4(top0, top1, x0 - frame.minX, x1 - frame.minX)
                    written += 1
                }
            }
        }
        return written
    }

    /// `--debug-surfaces`: window outlines (blue), the Dock estimate (yellow), whole top edges
    /// (red), visible intervals (green).
    private func writeDebugRects(into buffer: MTLBuffer) -> Int {
        let destination = buffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: Self.maxDebugRects * 2)
        var written = 0
        func add(_ rect: SIMD4<Float>, _ color: SIMD4<Float>) {
            guard written < Self.maxDebugRects else { return }
            destination[written * 2] = rect
            destination[written * 2 + 1] = color * SIMD4(color.w, color.w, color.w, 1) // premultiply
            written += 1
        }
        let blue = SIMD4<Float>(0.3, 0.6, 1, 0.8)
        let red = SIMD4<Float>(1, 0.25, 0.25, 0.9)
        let green = SIMD4<Float>(0.2, 1, 0.4, 0.95)
        let yellow = SIMD4<Float>(1, 0.85, 0.1, 0.95)
        for cap in world.caps where cap.isPresent {
            let f = cap.frame
            let outline = cap.id == World.dockCapID ? yellow : blue
            add(SIMD4(f.minX, f.minY, f.width, 1), outline)
            add(SIMD4(f.minX, f.minY, 1, f.height), outline)
            add(SIMD4(f.maxX - 1, f.minY, 1, f.height), outline)
            add(SIMD4(f.minX, f.maxY - 1, f.width, 1), red)
            for interval in cap.visible {
                add(SIMD4(interval.lower, f.maxY - 3, interval.length, 2), green)
            }
        }
        return written
    }
}
