/// Owns the whole simulation. The app feeds it inputs and reads render data back.
public final class World {
    /// Cap id reserved for the Dock (window numbers never reach it).
    public static let dockCapID = UInt32.max

    public private(set) var flakes = FlakePool()
    public private(set) var debris = DebrisPool()
    public let windows = WindowRegistry()
    /// Caps of tracked windows, back to front (render order).
    public private(set) var caps: [SnowCap] = []
    /// Snow that left caps and has not yet been turned into debris (consumed at the end of `step`).
    public private(set) var spills: [SnowSpill] = []
    /// Simulation time (s) since creation, excluding paused time.
    public private(set) var time: Float = 0
    public private(set) var wind: Float = 0

    public var intensity: Intensity = .medium {
        didSet { flakes.setDensity(density) }
    }
    /// Window corner radius for new caps (pt); per-OS, set by the app.
    public var windowCornerRadius: Float = Config.windowCornerRadiusLegacy
    /// `--instant-snow`: new caps start full.
    public var instantSnow = false
    /// Whether flakes settle on windows.
    public var snowOnWindows = true
    /// Maximum drift height (pt), clamped to `Config.capMaxHeightRange`.
    public var maxDriftHeight: Float = Config.capMaxHeight {
        didSet {
            maxDriftHeight = min(max(maxDriftHeight, Config.capMaxHeightRange.lowerBound), Config.capMaxHeightRange.upperBound)
            for cap in caps { cap.setMaxHeight(maxDriftHeight) }
        }
    }
    /// Wind multiplier, clamped to `Config.windScaleRange`.
    public var windScale: Float = 1 {
        didSet { windScale = min(max(windScale, Config.windScaleRange.lowerBound), Config.windScaleRange.upperBound) }
    }
    /// Whether the Dock carries snow. Turning it off drops the Dock's snow.
    public var snowOnDock = true {
        didSet { if !snowOnDock { setDock(nil) } }
    }
    /// The Dock's current frame (AppKit global points), nil when it has no surface.
    public private(set) var dockFrame: Rect?
    private var dockCap: SnowCap?

    private var rng: SplitMix64
    private var screens: [Rect] = []
    private var capsByID: [UInt32: SnowCap] = [:]
    /// Lowest screen edge (pt); debris below it is gone.
    private var floor: Float = 0
    private var cursor: SIMD2<Float>?
    private var previousCursor: SIMD2<Float>?

    public init(seed: UInt64 = Config.defaultSeed) {
        rng = SplitMix64(seed: seed)
        spills.reserveCapacity(Config.maxSpillsPerStep)
    }

    private var density: Float { Config.flakeDensity * intensity.densityMultiplier }

    /// Updates the screen layout. No-op when nothing changed.
    public func setScreens(_ rects: [Rect]) {
        guard rects != screens else { return }
        screens = rects
        floor = (rects.map(\.minY).min() ?? 0) - 40
        flakes.setRegions(rects, density: density, rng: &rng)
    }

    /// Feeds a window-list poll (front to back, AppKit global points) taken now.
    public func ingestWindows(_ samples: [WindowSample]) {
        let changes = windows.ingest(samples, time: time)
        for id in changes.appeared where capsByID[id] == nil && capsByID.count < Config.maxCaps {
            guard let entry = windows.entries[id] else { continue }
            let cap = SnowCap(id: id, frame: entry.frame, cornerRadius: windowCornerRadius,
                              lumpPhase: rng.nextUnit() * 2 * Float.pi, maxHeight: maxDriftHeight)
            if instantSnow { cap.fill(fraction: Config.instantSnowFill) }
            capsByID[id] = cap
        }
        for entry in changes.disappeared {
            guard let cap = capsByID.removeValue(forKey: entry.id) else { continue }
            cap.shedAll(velocity: .zero, spills: &spills)
        }
        rebuildCapOrder()
    }

    /// Updates the Dock frame. nil (Dock hidden, on the side, or disabled) drops its snow.
    public func setDock(_ frame: Rect?) {
        let frame = snowOnDock ? frame : nil
        guard frame != dockFrame else { return }
        dockFrame = frame
        if let frame {
            if dockCap == nil {
                let cap = SnowCap(id: Self.dockCapID, frame: frame, cornerRadius: Config.dockCornerRadius,
                                  lumpPhase: rng.nextUnit() * 2 * Float.pi, maxHeight: maxDriftHeight)
                if instantSnow { cap.fill(fraction: Config.instantSnowFill) }
                dockCap = cap
            }
        } else if let cap = dockCap {
            cap.shedAll(velocity: .zero, spills: &spills)
            dockCap = nil
        }
        rebuildCapOrder()
    }

    /// Current cursor position (AppKit global points), polled by the app every tick.
    public func setCursor(_ position: SIMD2<Float>) {
        cursor = position
    }

    /// Seconds since a window last moved, resized, appeared, disappeared or changed z-order.
    public var timeSinceWindowChange: Float { time - windows.lastChangeTime }

    /// All settled snow (pt²), for the HUD.
    public var settledMass: Float { caps.reduce(0) { $0 + $1.mass } }

    /// Whether anything is moving fast enough to deserve the high frame rate.
    public var isBusy: Bool { debris.count > 0 || windows.anyMoving }

    /// Removes all settled snow and debris.
    public func clearSnow() {
        for cap in caps { cap.clear() }
        debris.removeAll()
        spills.removeAll(keepingCapacity: true)
    }

    /// Advances the simulation by `dt` seconds (clamped to `Config.maxStep`).
    public func step(dt: Float) {
        let dt = min(max(dt, 0), Config.maxStep)
        time += dt
        wind = Wind.velocity(at: time) * windScale

        updateCapGeometry()
        applyBrush(dt: dt)

        let amount = Config.snowPerFlake
        let collect = snowOnWindows && !caps.isEmpty
        flakes.step(dt: dt, wind: wind, rng: &rng) { previous, current, _ in
            collect && self.absorb(from: previous, to: current, amount: amount, excluding: 0)
        }
        debris.step(dt: dt, floor: floor) { previous, current, source, mass in
            self.absorb(from: previous, to: current, amount: mass, excluding: source)
        }

        for cap in caps where cap.isPresent {
            cap.relax(dt: dt, spills: &spills)
        }

        for spill in spills {
            debris.spawn(spill, rng: &rng)
        }
        spills.removeAll(keepingCapacity: true)
    }

    // MARK: Private

    private func rebuildCapOrder() {
        // `order` is front to back; render back to front. The Dock is in front of all windows.
        caps = windows.order.reversed().compactMap { capsByID[$0] }
        if let dockCap { caps.append(dockCap) }
    }

    /// Moves caps with their windows, re-anchors on resize, sheds snow off moving windows and
    /// recomputes occlusion.
    private func updateCapGeometry() {
        // Front-to-back frames for occlusion; the Dock (when present) is frontmost.
        let ids = windows.order
        let dockOffset = dockFrame == nil ? 0 : 1
        var frames: [Rect] = []
        var present: [Bool] = []
        frames.reserveCapacity(ids.count + dockOffset)
        present.reserveCapacity(ids.count + dockOffset)
        if let dockFrame {
            frames.append(dockFrame)
            present.append(true)
        }
        for id in ids {
            frames.append(windows.frame(of: id) ?? Rect(x: 0, y: 0, width: 0, height: 0))
            present.append(windows.entries[id]?.isPresent ?? false)
        }
        let visible = Occlusion.visibleIntervals(frames: frames, present: present, band: maxDriftHeight)
        if let dockCap, let dockFrame {
            dockCap.update(frame: dockFrame, spills: &spills)
            dockCap.visible = visible[0]
        }
        for (position, id) in ids.enumerated() {
            let index = position + dockOffset
            guard let cap = capsByID[id] else { continue }
            let displacement = cap.update(frame: frames[index], spills: &spills)
            cap.isPresent = present[index]
            cap.visible = visible[index]

            // Snow does not ride along with a moving window: it falls off in proportion to how
            // far the window moved this step, carrying part of the window's velocity.
            let distance = (displacement * displacement).sum().squareRoot()
            guard distance > Config.shedDeadZone else { continue }
            cap.lastMoveTime = time
            let fraction = (distance - Config.shedDeadZone) / Config.shedDistance
            let velocity = (windows.entries[id]?.velocity ?? .zero) * Config.shedVelocityInherit
            cap.shed(fraction: fraction, velocity: velocity, spills: &spills)
        }
    }

    /// Cursor brush: snow touched by the cursor's path since the last step breaks off.
    private func applyBrush(dt: Float) {
        defer { previousCursor = cursor }
        guard let from = previousCursor, let to = cursor, dt > 0 else { return }
        let delta = to - from
        guard (delta * delta).sum() >= Config.brushMinMove * Config.brushMinMove else { return }
        let velocity = delta / dt * Config.brushVelocityInherit + SIMD2(0, Config.brushKick)
        for cap in caps where cap.isPresent && !cap.visible.isEmpty {
            cap.brush(from: from, to: to, radius: Config.brushRadius, velocity: velocity, spills: &spills)
        }
    }

    /// Absorbs snow (a flake or a debris particle) that crossed a visible, resting cap surface
    /// between `previous` and `current`. Caps are checked front to back so the topmost wins.
    private func absorb(from previous: SIMD2<Float>, to current: SIMD2<Float>,
                        amount: Float, excluding source: UInt32) -> Bool {
        for cap in caps.reversed() where cap.isPresent && !cap.visible.isEmpty && cap.id != source {
            let frame = cap.frame
            guard current.x >= frame.minX, current.x <= frame.maxX,
                  previous.y >= frame.maxY - cap.cornerRadius,
                  current.y <= frame.maxY + cap.maxHeight,
                  time - cap.lastMoveTime >= Config.settleDelay,
                  Intervals.contains(cap.visible, current.x),
                  let surface = cap.surfaceY(at: current.x),
                  previous.y >= surface, current.y <= surface
            else { continue }
            cap.deposit(at: current.x, amount: amount)
            return true
        }
        return false
    }
}
