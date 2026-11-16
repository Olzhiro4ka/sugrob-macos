import AppKit
import SnowCore

/// Drives the single display-linked tick: poll inputs → `World.step` → render.
@MainActor
final class SnowEngine: NSObject {
    private let world: World
    private let screens: ScreenManager
    private let tracker = WindowTracker()
    private let systemProcesses = SystemProcesses()
    private let session = SessionMonitor()
    private let dock: DockLocator
    private let power = PowerMonitor()
    private var frameRateMode = FrameRateMode.balanced
    private var pauseOnBattery = false
    private let hud: HUD?
    /// `--fps N` override.
    private let fixedFPS: Int?

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var nextPoll: CFTimeInterval = 0
    private var pollInFlight = false
    private var wasMouseDown = false
    /// Duration of a poll that completed since the last HUD frame (s).
    private var completedPollSeconds: Double?
    private var currentFPS = Config.idleFPS
    private var pauseReasons: Set<PauseReason> = []
    /// Poll that runs while Mission Control stops the tick, to notice when it ends.
    private var watchTimer: Timer?
    private var watchInterval: TimeInterval = 0
    private var missionControlRecoverySamples: [WindowSample]?
    private var missionControlRecoveryStart: CFTimeInterval?
    /// Displays covered by a fullscreen window; their Dock cap is suppressed.
    private var fullscreenScreens: Set<Int> = []

    init?(options: LaunchOptions, settings: SettingsStore) {
        guard let gpu = SnowGPU() else { return nil }
        let seed = options.seed ?? (UInt64(Date().timeIntervalSince1970 * 1000) ^ Config.defaultSeed)
        world = World(seed: seed)
        world.instantSnow = options.instantSnow
        world.windowCornerRadius = ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
        ) ? Config.windowCornerRadiusModern : Config.windowCornerRadiusLegacy
        screens = ScreenManager(gpu: gpu, world: world)
        screens.debugSurfaces = options.debugSurfaces
        hud = options.hud ? HUD() : nil
        dock = DockLocator(verbose: options.hud || options.debugSurfaces)
        fixedFPS = options.fps
        if let fps = options.fps { currentFPS = fps }
        super.init()

        screens.onRebuild = { [weak self] in self?.overlaysRebuilt() }
        session.onChange = { [weak self] reason, active in self?.setPaused(reason, active) }
        session.onSpaceChange = { [weak self] in
            guard let self else { return }
            self.missionControlRecoverySamples = nil
            self.missionControlRecoveryStart = nil
            self.updateWatch()
            self.nextPoll = 0
            self.requestPoll()
        }
        dock.onChange = { [weak self] _ in self?.updateDockSurface() }
        power.onChange = { [weak self] _ in self?.updateBatteryPause() }
        apply(settings, preciseDockOverride: options.preciseDock)
        dock.refresh()
        overlaysRebuilt()
    }

    var isPaused: Bool { !pauseReasons.isEmpty }

    /// Applies user settings live.
    func apply(_ settings: SettingsStore?, preciseDockOverride: Bool = false) {
        guard let settings else { return }
        world.intensity = settings.intensity
        world.snowOnWindows = settings.snowOnWindows
        if !settings.snowOnWindows {
            world.clearWindowSnow()
        }
        world.snowOnDock = settings.bottomSurface == .dock
        world.bottomSurface = settings.bottomSurface
        world.snowplowEnabled = settings.snowplowEnabled
        updateDockSurface()
        world.maxDriftHeight = Float(settings.maxDriftHeight)
        world.windScale = Float(settings.windStrength)
        frameRateMode = settings.frameRate
        pauseOnBattery = settings.pauseOnBattery
        dock.preciseMode = settings.preciseDock || preciseDockOverride
        updateBatteryPause()
        setPaused(.userDisabled, !settings.isSnowEnabled)
    }

    func clearSnow() {
        world.clearSnow()
    }

    private func updateBatteryPause() {
        setPaused(.onBattery, pauseOnBattery && power.isOnBattery)
    }

    private func updateDockSurface() {
        guard let frame = dock.frame else {
            world.setDock(nil)
            return
        }
        let dockCenter = SIMD2(frame.midX, frame.maxY)
        let covered = screens.overlays.enumerated().contains { index, overlay in
            fullscreenScreens.contains(index) && overlay.rect.contains(dockCenter)
        }
        world.setDock(covered ? nil : frame)
    }

    func setPaused(_ reason: PauseReason, _ active: Bool) {
        let wasPaused = isPaused
        if active {
            pauseReasons.insert(reason)
        } else {
            pauseReasons.remove(reason)
        }
        updateWatch()
        guard wasPaused != isPaused else { return }
        applyPauseState()
    }

    func shutdown() {
        displayLink?.invalidate()
        displayLink = nil
        watchTimer?.invalidate()
        dock.stop()
        power.stop()
    }

    // MARK: Tick

    @objc private func tick(_ link: CADisplayLink) {
        let start = CACurrentMediaTime()
        // Step by the interval between the frames' *presentation* times, so motion matches what
        // the display actually shows even if a callback runs a little late.
        let dt = lastTimestamp.map { link.targetTimestamp - $0 } ?? 0
        lastTimestamp = link.targetTimestamp
        let mouseDown = NSEvent.pressedMouseButtons != 0
        let mouse = NSEvent.mouseLocation
        world.setCursor(SIMD2(Float(mouse.x), Float(mouse.y)))
        if mouseDown && !wasMouseDown { nextPoll = 0 }
        wasMouseDown = mouseDown

        if start >= nextPoll && !pollInFlight {
            requestPoll()
            let fast = mouseDown || world.timeSinceWindowChange < Config.pollActiveWindow
            nextPoll = start + Double(fast ? Config.pollIntervalActive : Config.pollIntervalIdle)
        }

        world.step(dt: Float(dt))
        updateFrameRate(active: mouseDown || world.isBusy)

        let simulated = CACurrentMediaTime()
        screens.render()
        let rendered = CACurrentMediaTime()

        hud?.record(HUD.Frame(
            interval: dt, drops: screens.droppedFrames,
            tick: simulated - start, render: rendered - simulated, poll: completedPollSeconds,
            flakes: world.flakes.count, debris: world.debris.count, snow: world.settledMass, windows: world.windows.order.count,
            caps: world.caps.count, segments: screens.lastCapSegments, fps: currentFPS
        ))
        completedPollSeconds = nil
    }

    // MARK: Private

    /// Starts a background window poll; results are applied on the main actor, between ticks.
    private func requestPoll() {
        guard !pollInFlight else { return }
        pollInFlight = true
        tracker.poll(primaryHeight: CoordinateSpace.primaryHeight, system: systemProcesses.snapshot) { [weak self] result in
            guard let self else { return }
            pollInFlight = false
            completedPollSeconds = result.duration
            handleMissionControl(result)
            // Ignore window geometry while paused: during Mission Control frames are scaled
            // down and would look like every window jumped.
            guard !isPaused else { return }
            world.ingestWindows(result.samples)
            detectFullscreen(result.samples)
        }
    }

    private func handleMissionControl(_ result: WindowTracker.Result) {
        if result.missionControl {
            let wasRecovering = missionControlRecoveryStart != nil
            missionControlRecoverySamples = nil
            missionControlRecoveryStart = nil
            if wasRecovering { updateWatch() }
            if !pauseReasons.contains(.missionControl) { setPaused(.missionControl, true) }
        } else if pauseReasons.contains(.missionControl) {
            let now = CACurrentMediaTime()
            if let previous = missionControlRecoverySamples {
                let framesSettled = previous.count == result.samples.count &&
                    zip(previous, result.samples).allSatisfy { old, current in
                        old.id == current.id && old.frame.isClose(
                            to: current.frame, tolerance: Config.missionControlFrameTolerance
                        )
                    }
                if framesSettled || now - (missionControlRecoveryStart ?? now) >= Config.missionControlRecoveryMaxWait {
                    missionControlRecoverySamples = nil
                    missionControlRecoveryStart = nil
                    nextPoll = 0
                    setPaused(.missionControl, false)
                } else {
                    missionControlRecoverySamples = result.samples
                }
            } else {
                missionControlRecoverySamples = result.samples
                missionControlRecoveryStart = now
                updateWatch()
            }
        }
    }

    /// A layer-0 window covering a screen means a fullscreen app there.
    private func detectFullscreen(_ samples: [WindowSample]) {
        var covered: Set<Int> = []
        var fullscreenIDs: Set<UInt32> = []
        for (index, overlay) in screens.overlays.enumerated() {
            let visible = CoordinateSpace.core(overlay.screen.visibleFrame)
            for sample in samples where FullscreenCoverage.covers(sample.frame, screen: overlay.rect,
                                                                 visible: visible) {
                covered.insert(index)
                fullscreenIDs.insert(sample.id)
            }
        }
        world.setFullscreenWindows(fullscreenIDs)
        fullscreenScreens = covered
        updateDockSurface()
    }

    private func updateWatch() {
        let needsWatch = pauseReasons == [.missionControl]
        let interval = missionControlRecoveryStart == nil
            ? Config.missionControlWatchInterval : Config.missionControlRecoveryPollInterval
        if needsWatch, watchTimer == nil || watchInterval != interval {
            watchTimer?.invalidate()
            let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.requestPoll() }
            }
            timer.tolerance = interval * 0.3
            RunLoop.main.add(timer, forMode: .common)
            watchTimer = timer
            watchInterval = interval
        } else if !needsWatch {
            watchTimer?.invalidate()
            watchTimer = nil
        }
    }

    private func overlaysRebuilt() {
        // The display link is tied to a view; recreate it on the new primary overlay.
        displayLink?.invalidate()
        displayLink = nil
        guard let primary = screens.overlays.first else { return }
        let link = primary.window.snowView.displayLink(target: self, selector: #selector(tick(_:)))
        // .common keeps snow falling while the status menu is open (event-tracking run loop mode).
        link.add(to: .main, forMode: .common)
        displayLink = link
        setFrameRate(currentFPS)
        hud?.attach(to: primary.window.snowView)
        nextPoll = 0
        fullscreenScreens = []
        updateDockSurface()
        applyPauseState()
    }

    /// Presented-frame count when the current pause began; nil while running.
    private var framesAtPause: Int?

    private func applyPauseState() {
        displayLink?.isPaused = isPaused
        lastTimestamp = nil
        screens.setVisible(!isPaused)
        guard hud != nil else { return }
        // Proof for the "no GPU work while paused" budget line.
        if isPaused {
            if framesAtPause == nil { framesAtPause = screens.presentedFrames }
            log("[pause] \(pauseReasons.map { "\($0)" }.sorted().joined(separator: ","))")
        } else if let start = framesAtPause {
            framesAtPause = nil
            log("[resume] frames presented while paused: \(screens.presentedFrames - start)")
        }
    }

    private func log(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }

    private func updateFrameRate(active: Bool) {
        let fps = fixedFPS ?? frameRateMode.fps(active: active)
        if fps != currentFPS { setFrameRate(fps) }
    }

    private func setFrameRate(_ fps: Int) {
        currentFPS = fps
        let rate = Float(fps)
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: min(15, rate), maximum: rate, preferred: rate)
    }
}
