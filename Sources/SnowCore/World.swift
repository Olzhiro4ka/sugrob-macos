/// Owns the whole simulation. The app feeds it inputs and reads render data back.
public final class World {
    public private(set) var flakes = FlakePool()
    public let windows = WindowRegistry()
    /// Caps of tracked windows, back to front (render order).
    public private(set) var caps: [SnowCap] = []
    /// Snow that left caps during the last step (consumed by debris in a later phase).
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

    private var rng: SplitMix64
    private var screens: [Rect] = []
    private var capsByID: [UInt32: SnowCap] = [:]

    public init(seed: UInt64 = Config.defaultSeed) {
        rng = SplitMix64(seed: seed)
        spills.reserveCapacity(Config.maxSpillsPerStep)
    }

    private var density: Float { Config.flakeDensity * intensity.densityMultiplier }

    /// Updates the screen layout. No-op when nothing changed.
    public func setScreens(_ rects: [Rect]) {
        guard rects != screens else { return }
        screens = rects
        flakes.setRegions(rects, density: density, rng: &rng)
    }

    /// Feeds a window-list poll (front to back, AppKit global points) taken now.
    public func ingestWindows(_ samples: [WindowSample]) {
        let changes = windows.ingest(samples, time: time)
        for id in changes.appeared where capsByID[id] == nil && capsByID.count < Config.maxCaps {
            guard let entry = windows.entries[id] else { continue }
            let cap = SnowCap(id: id, frame: entry.frame, cornerRadius: windowCornerRadius,
                              lumpPhase: rng.nextUnit() * 2 * Float.pi)
            if instantSnow { cap.fill(fraction: Config.instantSnowFill) }
            capsByID[id] = cap
        }
        for entry in changes.disappeared {
            guard let cap = capsByID.removeValue(forKey: entry.id) else { continue }
            cap.shedAll(velocity: .zero, spills: &spills)
        }
        rebuildCapOrder()
    }

    /// Seconds since a window last moved, resized, appeared, disappeared or changed z-order.
    public var timeSinceWindowChange: Float { time - windows.lastChangeTime }

    /// Removes all settled snow.
    public func clearSnow() {
        for cap in caps { cap.clear() }
    }

    /// Advances the simulation by `dt` seconds (clamped to `Config.maxStep`).
    public func step(dt: Float) {
        let dt = min(max(dt, 0), Config.maxStep)
        time += dt
        wind = Wind.velocity(at: time)
        spills.removeAll(keepingCapacity: true)

        updateCapGeometry()

        let amount = Config.snowPerFlake
        let collect = snowOnWindows && !caps.isEmpty
        flakes.step(dt: dt, wind: wind, rng: &rng) { previous, current, _ in
            collect && self.absorb(from: previous, to: current, amount: amount)
        }

        for cap in caps where cap.isPresent {
            cap.relax(spills: &spills)
        }
    }

    // MARK: Private

    private func rebuildCapOrder() {
        // `order` is front to back; render back to front.
        caps = windows.order.reversed().compactMap { capsByID[$0] }
    }

    private func updateCapGeometry() {
        // Front-to-back frames for occlusion.
        let ids = windows.order
        var frames: [Rect] = []
        var present: [Bool] = []
        frames.reserveCapacity(ids.count)
        present.reserveCapacity(ids.count)
        for id in ids {
            frames.append(windows.frame(of: id, at: time) ?? Rect(x: 0, y: 0, width: 0, height: 0))
            present.append(windows.entries[id]?.isPresent ?? false)
        }
        let visible = Occlusion.visibleIntervals(frames: frames, present: present)
        for (index, id) in ids.enumerated() {
            guard let cap = capsByID[id] else { continue }
            cap.update(frame: frames[index], spills: &spills)
            cap.isPresent = present[index]
            cap.visible = visible[index]
        }
    }

    /// Absorbs a flake that crossed a visible cap surface between `previous` and `current`.
    /// Caps are checked front to back so the topmost surface wins.
    private func absorb(from previous: SIMD2<Float>, to current: SIMD2<Float>, amount: Float) -> Bool {
        for cap in caps.reversed() where cap.isPresent && !cap.visible.isEmpty {
            let frame = cap.frame
            guard current.x >= frame.minX, current.x <= frame.maxX,
                  previous.y >= frame.maxY - cap.cornerRadius,
                  current.y <= frame.maxY + Config.capMaxHeight,
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
