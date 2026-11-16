/// Owns the whole simulation. The app feeds it inputs and reads render data back.
public enum BottomSurface: String, CaseIterable, Sendable {
    case dock
    case screen
}

public struct SnowPlow: Equatable, Sendable {
    public let screenIndex: Int
    public var x: Float
    public let y: Float
    /// Snow swept sideways out of the screen-edge cross-section (pt²).
    public var dischargedSnow: Float = 0
    public var bladeLoad: Float = 0
    public var bladeX: Float { x + Config.plowBladeOffset }
}

public final class World {
    /// Cap id reserved for the Dock (window numbers never reach it).
    public static let dockCapID = UInt32.max
    public static let screenCapID = UInt32.max - 1

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
            for cap in screenCaps { cap.setMaxHeight(maxDriftHeight) }
        }
    }
    /// Wind multiplier, clamped to `Config.windScaleRange`.
    public var windScale: Float = 1 {
        didSet { windScale = min(max(windScale, Config.windScaleRange.lowerBound), Config.windScaleRange.upperBound) }
    }
    /// Whether the Dock carries snow. Turning it off clears the Dock's snow.
    public var snowOnDock = true {
        didSet { if !snowOnDock { setDock(nil) } }
    }
    /// The Dock's current frame (AppKit global points), nil when it has no surface.
    public private(set) var dockFrame: Rect?
    private var dockCap: SnowCap?
    private var screenCaps: [SnowCap] = []
    public private(set) var plows: [SnowPlow] = []
    private var plowLastRun: [Float] = []
    /// Whether snowplows may appear on screen-edge snow.
    public var snowplowEnabled = true {
        didSet {
            if !snowplowEnabled { plows.removeAll(keepingCapacity: true) }
        }
    }
    public var bottomSurface: BottomSurface = .dock {
        didSet {
            if bottomSurface != .screen {
                plows.removeAll(keepingCapacity: true)
            }
            rebuildCapOrder()
        }
    }
    private var fullscreenWindowIDs: Set<UInt32> = []

    private var rng: SplitMix64
    private var screens: [Rect] = []
    private var capsByID: [UInt32: SnowCap] = [:]
    private var dormantCaps: [UInt32: (cap: SnowCap, expiry: Float)] = [:]
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
        screenCaps = rects.enumerated().map { index, screen in
            let cap = SnowCap(id: Self.screenCapID - UInt32(index),
                              frame: Rect(x: screen.minX, y: screen.minY - 2, width: screen.width, height: 2),
                              cornerRadius: 0, lumpPhase: Float(index) * 1.7,
                              maxHeight: maxDriftHeight)
            if instantSnow { cap.fill(fraction: Config.instantSnowFill) }
            cap.visible = [Interval(screen.minX, screen.maxX)]
            return cap
        }
        plows = []
        plowLastRun = Array(repeating: -Float.infinity, count: rects.count)
        rebuildCapOrder()
    }

    /// Feeds a window-list poll (front to back, AppKit global points) taken now.
    public func ingestWindows(_ samples: [WindowSample]) {
        if !dormantCaps.isEmpty {
            dormantCaps = dormantCaps.filter { $0.value.expiry > time }
        }
        let changes = windows.ingest(samples, time: time)
        for id in changes.appeared where capsByID[id] == nil && capsByID.count < Config.maxCaps {
            if let dormant = dormantCaps.removeValue(forKey: id), dormant.expiry > time {
                dormant.cap.isPresent = false
                capsByID[id] = dormant.cap
                continue
            }
            guard let entry = windows.entries[id] else { continue }
            let cap = SnowCap(id: id, frame: entry.frame, cornerRadius: windowCornerRadius,
                              lumpPhase: rng.nextUnit() * 2 * Float.pi, maxHeight: maxDriftHeight)
            if instantSnow { cap.fill(fraction: Config.instantSnowFill) }
            capsByID[id] = cap
        }
        for entry in changes.disappeared {
            guard let cap = capsByID.removeValue(forKey: entry.id) else { continue }
            cap.isPresent = false
            cap.visible = []
            dormantCaps[entry.id] = (cap, time + Config.hiddenWindowSnowLifetime)
        }
        // Presence must be recorded per poll, even if no simulation step runs between polls.
        for id in windows.order where windows.entries[id]?.isPresent == false {
            capsByID[id]?.isPresent = false
            capsByID[id]?.visible = []
        }
        rebuildCapOrder()
    }

    /// Rebase the next stable window snapshot after a Space / Mission Control transition.
    /// Animation coordinates are not physical window movement.
    public func beginWindowTransition() {
        for cap in capsByID.values {
            cap.isPresent = false
            cap.visible = []
        }
        debris.removeAll()
        spills.removeAll(keepingCapacity: true)
        previousCursor = nil
    }

    /// Updates the Dock frame. A hidden or disabled Dock loses its snow immediately.
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
            cap.clear()
            dockCap = nil
        }
        rebuildCapOrder()
    }

    /// Current cursor position (AppKit global points), polled by the app every tick.
    public func setCursor(_ position: SIMD2<Float>) {
        cursor = position
    }

    /// Fullscreen windows cannot collect or retain a cap while they cover a display.
    public func setFullscreenWindows(_ ids: Set<UInt32>) {
        fullscreenWindowIDs = ids
        for id in ids {
            guard let cap = capsByID[id] else { continue }
            cap.clear()
            cap.isPresent = false
            cap.visible = []
        }
        for (index, screen) in screens.enumerated() {
            let covered = ids.contains { id in
                guard let frame = windows.frame(of: id) else { return false }
                return FullscreenCoverage.covers(frame, screen: screen)
            }
            screenCaps[index].isPresent = !covered
            screenCaps[index].visible = covered ? [] : [Interval(screen.minX, screen.maxX)]
        }
        plows.removeAll { !screenCaps[$0.screenIndex].isPresent }
    }

    /// Seconds since a window last moved, resized, appeared, disappeared or changed z-order.
    public var timeSinceWindowChange: Float { time - windows.lastChangeTime }

    /// All settled snow (pt²), for the HUD.
    public var settledMass: Float { caps.reduce(0) { $0 + $1.mass } }

    /// Whether anything is moving fast enough to deserve the high frame rate.
    public var isBusy: Bool { debris.count > 0 || windows.anyMoving || !plows.isEmpty }

    /// Removes window snow without affecting the Dock or screen-edge snow.
    public func clearWindowSnow() {
        for cap in capsByID.values { cap.clear() }
        for dormant in dormantCaps.values { dormant.cap.clear() }
    }

    /// Removes all settled snow and debris.
    public func clearSnow() {
        for cap in caps { cap.clear() }
        for dormant in dormantCaps.values { dormant.cap.clear() }
        plows.removeAll(keepingCapacity: true)
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
        let collect = !caps.isEmpty
        flakes.step(dt: dt, wind: wind, rng: &rng) { previous, current, _ in
            collect && self.absorb(from: previous, to: current, amount: amount,
                                   restDelay: Config.settleDelay, allowWindows: self.snowOnWindows)
        }
        debris.step(dt: dt, floor: floor) { previous, current, _, mass in
            self.absorb(from: previous, to: current, amount: mass,
                        restDelay: Config.debrisLandingDelay, allowWindows: true)
        }

        for cap in caps where cap.isPresent {
            cap.relax(dt: dt, spills: &spills)
        }

        updatePlows(dt: dt)

        for spill in spills {
            debris.spawn(spill, rng: &rng)
        }
        spills.removeAll(keepingCapacity: true)
    }

    // MARK: Private

    private func rebuildCapOrder() {
        // `order` is front to back; render back to front. The Dock is in front of all windows.
        caps = windows.order.reversed().compactMap { capsByID[$0] }
        if bottomSurface == .screen {
            caps.append(contentsOf: screenCaps)
        } else if let dockCap { caps.append(dockCap) }
    }

    /// Moves caps with their windows, re-anchors on resize, sheds snow off moving windows and
    /// recomputes occlusion.
    private func updateCapGeometry() {
        // Front-to-back frames for occlusion; the Dock (when present) is frontmost.
        let ids = windows.order
        let dockOffset = bottomSurface == .dock && dockFrame != nil ? 1 : 0
        var frames: [Rect] = []
        var present: [Bool] = []
        frames.reserveCapacity(ids.count + dockOffset)
        present.reserveCapacity(ids.count + dockOffset)
        if dockOffset == 1, let dockFrame {
            frames.append(dockFrame)
            present.append(true)
        }
        for id in ids {
            frames.append(windows.frame(of: id) ?? Rect(x: 0, y: 0, width: 0, height: 0))
            present.append(windows.entries[id]?.isPresent ?? false)
        }
        let visible = Occlusion.visibleIntervals(frames: frames, present: present, band: maxDriftHeight)
        if dockOffset == 1, let dockCap, let dockFrame {
            dockCap.updateCentered(frame: dockFrame, spills: &spills)
            dockCap.visible = visible[0]
        }
        for (position, id) in ids.enumerated() {
            let index = position + dockOffset
            guard let cap = capsByID[id] else { continue }
            // Suppress fullscreen geometry before movement can shed a snow cap.
            // Also protect callers that have not yet supplied platform classification.
            let fullscreen = fullscreenWindowIDs.contains(id) ||
                screens.contains { FullscreenCoverage.covers(frames[index], screen: $0) }
            if fullscreen {
                cap.clear()
                cap.restore(frame: frames[index])
                cap.isPresent = false
                cap.visible = []
                continue
            }
            let displacement = SnowCap.rigidDisplacement(from: cap.frame, to: frames[index])
            let distance = (displacement * displacement).sum().squareRoot()
            if !cap.isPresent {
                cap.restore(frame: frames[index])
            } else if distance > Config.shedDeadZone {
                cap.lastMoveTime = time
                let windowVelocity = windows.entries[id]?.rawVelocity ?? .zero
                let velocity = SIMD2(Self.shedLaunchVelocity(windowVelocity.x),
                                     Self.shedLaunchVelocity(windowVelocity.y))
                // Release at the old edge so the snow does not ride with the moving window.
                cap.shedAll(velocity: velocity, spills: &spills)
            }
            if cap.isPresent { cap.update(frame: frames[index], spills: &spills) }
            cap.isPresent = present[index] && !fullscreenWindowIDs.contains(id)
            cap.visible = cap.isPresent ? visible[index] : []
        }
    }

    private func updatePlows(dt: Float) {
        guard bottomSurface == .screen && snowplowEnabled else { return }
        for index in screenCaps.indices {
            let cap = screenCaps[index]
            guard cap.isPresent else { continue }
            if let position = plows.firstIndex(where: { $0.screenIndex == index }) {
                plows[position].x -= Config.plowSpeed * dt
                let bladeX = plows[position].bladeX
                // Sweep the whole footprint after settling so fresh deposits and lateral
                // relaxation cannot leave snow beneath the vehicle.
                let collected = cap.clearSnow(from: plows[position].x + Config.plowSize.x,
                                              to: bladeX)
                let available = plows[position].bladeLoad + collected
                let retained = min(Config.plowLoadCapacity,
                                   available / (1 + dt / Config.plowLoadResidence))
                plows[position].bladeLoad = retained
                plows[position].dischargedSnow += available - retained
                if plows[position].x + Config.plowSize.x < screens[index].minX {
                    plows.remove(at: position)
                    plowLastRun[index] = time
                }
            } else if time - plowLastRun[index] >= Config.plowCooldown,
                      cap.mass / max(cap.frame.width, 1) >= maxDriftHeight * Config.plowTriggerFraction {
                plows.append(SnowPlow(screenIndex: index, x: screens[index].maxX + 8,
                                      y: screens[index].minY - Config.plowBottomOffset))
            }
        }
    }

    private static func shedLaunchVelocity(_ speed: Float) -> Float {
        guard speed != 0 else { return 0 }
        let magnitude = max(abs(speed) * Config.shedVelocityInherit, Config.shedMinLaunchSpeed)
        return min(magnitude, Config.shedMaxLaunchSpeed) * (speed > 0 ? 1 : -1)
    }

    /// Cursor brush: snow touched by the cursor's path since the last step breaks off.
    private func applyBrush(dt: Float) {
        defer { previousCursor = cursor }
        guard let from = previousCursor, let to = cursor, dt > 0 else { return }
        let delta = to - from
        guard (delta * delta).sum() >= Config.brushMinMove * Config.brushMinMove else { return }
        let horizontal = min(max(delta.x / dt * Config.brushVelocityInherit,
                                 -Config.brushMaxHorizontalSpeed), Config.brushMaxHorizontalSpeed)
        let vertical = min(max(Config.brushKick + delta.y / dt * Config.brushVerticalVelocityInherit,
                               Config.brushVerticalSpeedRange.lowerBound), Config.brushVerticalSpeedRange.upperBound)
        let velocity = SIMD2(horizontal, vertical)
        for cap in caps where cap.isPresent && !cap.visible.isEmpty {
            cap.brush(from: from, to: to, radius: Config.brushRadius, velocity: velocity,
                      fraction: Config.brushReleaseFraction, spills: &spills)
        }
    }

    /// Absorbs snow (a flake or a debris particle) that crossed a visible, resting cap surface
    /// between `previous` and `current`. Caps are checked front to back so the topmost wins.
    private func absorb(from previous: SIMD2<Float>, to current: SIMD2<Float>,
                        amount: Float, restDelay: Float, allowWindows: Bool) -> Bool {
        for cap in caps.reversed() where cap.isPresent && !cap.visible.isEmpty {
            if !allowWindows && cap.id != Self.dockCapID && !screenCaps.contains(where: { $0 === cap }) {
                continue
            }
            let frame = cap.frame
            guard current.x >= frame.minX, current.x <= frame.maxX,
                  previous.y >= frame.maxY - cap.cornerRadius,
                  current.y <= frame.maxY + cap.maxHeight,
                  time - cap.lastMoveTime >= restDelay,
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
