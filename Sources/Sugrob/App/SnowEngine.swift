import AppKit
import SnowCore

/// Drives the single display-linked tick: poll inputs → `World.step` → render.
@MainActor
final class SnowEngine: NSObject {
    private let world: World
    private let screens: ScreenManager
    private let tracker = WindowTracker()
    private let session = SessionMonitor()
    private let hud: HUD?
    /// `--fps N` override.
    private let fixedFPS: Int?

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var nextPoll: CFTimeInterval = 0
    private var pollInFlight = false
    /// Duration of a poll that completed since the last HUD frame (s).
    private var completedPollSeconds: Double?
    private var currentFPS = Config.idleFPS
    private var pauseReasons: Set<PauseReason> = []
    /// Low-rate poll that runs only while every screen is fullscreen (tick stopped), to notice
    /// when the user leaves fullscreen.
    private var fullscreenWatch: Timer?

    init?(options: LaunchOptions) {
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
        fixedFPS = options.fps
        if let fps = options.fps { currentFPS = fps }
        super.init()

        screens.onRebuild = { [weak self] in self?.overlaysRebuilt() }
        session.onChange = { [weak self] reason, active in self?.setPaused(reason, active) }
        session.onSpaceChange = { [weak self] in self?.nextPoll = 0 }
        overlaysRebuilt()
    }

    var isPaused: Bool { !pauseReasons.isEmpty }

    func setPaused(_ reason: PauseReason, _ active: Bool) {
        let wasPaused = isPaused
        if active {
            pauseReasons.insert(reason)
        } else {
            pauseReasons.remove(reason)
        }
        updateFullscreenWatch()
        guard wasPaused != isPaused else { return }
        applyPauseState()
    }

    func shutdown() {
        displayLink?.invalidate()
        displayLink = nil
        fullscreenWatch?.invalidate()
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
            flakes: world.flakes.count, debris: world.debris.count, windows: world.windows.order.count,
            caps: world.caps.count, segments: screens.lastCapSegments, fps: currentFPS
        ))
        completedPollSeconds = nil
    }

    // MARK: Private

    /// Starts a background window poll; results are applied on the main actor, between ticks.
    private func requestPoll() {
        guard !pollInFlight else { return }
        pollInFlight = true
        tracker.poll(primaryHeight: CoordinateSpace.primaryHeight) { [weak self] samples, duration in
            guard let self else { return }
            pollInFlight = false
            completedPollSeconds = duration
            guard !isPaused || pauseReasons == [.allFullscreen] else { return }
            world.ingestWindows(samples)
            detectFullscreen(samples)
        }
    }

    /// A layer-0 window whose bounds equal its screen's frame means a fullscreen app there.
    private func detectFullscreen(_ samples: [WindowSample]) {
        var covered: Set<Int> = []
        for (index, overlay) in screens.overlays.enumerated()
        where samples.contains(where: { $0.frame.isClose(to: overlay.rect, tolerance: 1) }) {
            covered.insert(index)
        }
        screens.setFullscreen(covered)
        let all = screens.allHiddenByFullscreen
        if all != pauseReasons.contains(.allFullscreen) {
            setPaused(.allFullscreen, all)
        }
    }

    private func updateFullscreenWatch() {
        let watch = pauseReasons == [.allFullscreen]
        if watch, fullscreenWatch == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.requestPoll() }
            }
            timer.tolerance = 0.3
            RunLoop.main.add(timer, forMode: .common)
            fullscreenWatch = timer
        } else if !watch {
            fullscreenWatch?.invalidate()
            fullscreenWatch = nil
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
        applyPauseState()
    }

    private func applyPauseState() {
        displayLink?.isPaused = isPaused
        lastTimestamp = nil
        screens.setVisible(!isPaused)
    }

    private func updateFrameRate(active: Bool) {
        let fps = fixedFPS ?? (active ? Config.activeFPS : Config.idleFPS)
        if fps != currentFPS { setFrameRate(fps) }
    }

    private func setFrameRate(_ fps: Int) {
        currentFPS = fps
        let rate = Float(fps)
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: min(15, rate), maximum: rate, preferred: rate)
    }
}
