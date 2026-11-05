import AppKit
import SnowCore

/// Drives the single display-linked tick: poll inputs → `World.step` → render.
@MainActor
final class SnowEngine: NSObject {
    private let world: World
    private let screens: ScreenManager
    private let session = SessionMonitor()
    private let hud: HUD?

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var currentFPS = Config.idleFPS
    private var pauseReasons: Set<PauseReason> = []

    init?(options: LaunchOptions) {
        guard let gpu = SnowGPU() else { return nil }
        let seed = options.seed ?? (UInt64(Date().timeIntervalSince1970 * 1000) ^ Config.defaultSeed)
        world = World(seed: seed)
        screens = ScreenManager(gpu: gpu, world: world)
        hud = options.hud ? HUD() : nil
        super.init()

        screens.onRebuild = { [weak self] in self?.overlaysRebuilt() }
        session.onChange = { [weak self] reason, active in self?.setPaused(reason, active) }
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
        guard wasPaused != isPaused else { return }
        applyPauseState()
    }

    func shutdown() {
        displayLink?.invalidate()
        displayLink = nil
    }

    // MARK: Tick

    @objc private func tick(_ link: CADisplayLink) {
        let start = CACurrentMediaTime()
        let dt = lastTimestamp.map { link.timestamp - $0 } ?? 0
        lastTimestamp = link.timestamp

        updateFrameRate(active: NSEvent.pressedMouseButtons != 0)
        world.step(dt: Float(dt))

        let simulated = CACurrentMediaTime()
        screens.render()
        let rendered = CACurrentMediaTime()

        hud?.record(tick: simulated - start, render: rendered - simulated,
                    flakes: world.flakes.count, fps: currentFPS)
    }

    // MARK: Private

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
        if let hud { hud.attach(to: primary.window.snowView) }
        applyPauseState()
    }

    private func applyPauseState() {
        displayLink?.isPaused = isPaused
        lastTimestamp = nil
        screens.setVisible(!isPaused)
    }

    private func updateFrameRate(active: Bool) {
        let fps = active ? Config.activeFPS : Config.idleFPS
        if fps != currentFPS { setFrameRate(fps) }
    }

    private func setFrameRate(_ fps: Int) {
        currentFPS = fps
        let rate = Float(fps)
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: min(15, rate), maximum: rate, preferred: rate)
    }
}
