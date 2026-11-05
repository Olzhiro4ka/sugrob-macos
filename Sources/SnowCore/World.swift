/// Owns the whole simulation. The app feeds it inputs and reads render data back.
public final class World {
    public private(set) var flakes = FlakePool()
    /// Simulation time (s) since creation, excluding paused time.
    public private(set) var time: Float = 0
    public private(set) var wind: Float = 0

    public var intensity: Intensity = .medium {
        didSet { flakes.setDensity(density) }
    }

    private var rng: SplitMix64
    private var screens: [Rect] = []

    public init(seed: UInt64 = Config.defaultSeed) {
        rng = SplitMix64(seed: seed)
    }

    private var density: Float { Config.flakeDensity * intensity.densityMultiplier }

    /// Updates the screen layout. No-op when nothing changed.
    public func setScreens(_ rects: [Rect]) {
        guard rects != screens else { return }
        screens = rects
        flakes.setRegions(rects, density: density, rng: &rng)
    }

    /// Advances the simulation by `dt` seconds (clamped to `Config.maxStep`).
    public func step(dt: Float) {
        let dt = min(max(dt, 0), Config.maxStep)
        time += dt
        wind = Wind.velocity(at: time)
        flakes.step(dt: dt, wind: wind, rng: &rng)
    }
}
