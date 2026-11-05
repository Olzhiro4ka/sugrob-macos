/// All simulation tunables live here. Every value documents its unit.
/// Coordinates are AppKit global points, y up.
public enum Config {
    /// Default RNG seed when `--seed` is not given; the app mixes in the launch time.
    public static let defaultSeed: UInt64 = 0x5_06D0_0B

    // MARK: Falling flakes

    /// Hard upper bound of simultaneously simulated flakes (pool size, count).
    public static let flakeCapacity = 4096
    /// Flakes per 1,000,000 pt² of screen area at `Intensity.medium` (count / Mpt²).
    /// One 1512×982 display ≈ 1.48 Mpt² → ~130 flakes: sparse, unobtrusive.
    public static let flakeDensity: Float = 90
    /// Flake radius (pt).
    public static let flakeRadius: ClosedRange<Float> = 1...3
    /// Flake opacity (0…1).
    public static let flakeOpacity: ClosedRange<Float> = 0.4...0.9
    /// Fall speed (pt/s). Larger flakes fall faster, which reads as depth.
    public static let flakeFallSpeed: ClosedRange<Float> = 25...60
    /// Random spread of the fall speed around the size-derived value (fraction, ±).
    public static let flakeFallJitter: Float = 0.15
    /// Horizontal sway amplitude (pt).
    public static let flakeSwayAmplitude: ClosedRange<Float> = 3...12
    /// Sway frequency (Hz, cycles per second).
    public static let flakeSwayFrequency: ClosedRange<Float> = 0.12...0.4
    /// How far outside a screen a flake may travel before it is recycled or wrapped (pt).
    public static let flakeMargin: Float = 12

    // MARK: Wind

    /// Constant drift to the right (pt/s). Negative blows left.
    public static let windBase: Float = 3
    /// Amplitude of slow gusts added on top of `windBase` (pt/s).
    public static let windGust: Float = 7
    /// Periods of the two sine waves that make up a gust (s); incommensurate on purpose.
    public static let windPeriods: (Float, Float) = (83, 31)
    /// Fraction of the wind felt by the largest flake; the smallest feels all of it (0…1).
    public static let windLargeFlakeFactor: Float = 0.55

    // MARK: Tick

    /// Longest simulated step (s); longer gaps (e.g. after a hitch) are clamped to this.
    public static let maxStep: Float = 1.0 / 15.0
    /// Render rate while nothing moves fast (fps).
    public static let idleFPS = 30
    /// Render rate while something moves fast: debris, mouse button down, moving window (fps).
    public static let activeFPS = 60
}

/// User-selectable snowfall intensity.
public enum Intensity: String, CaseIterable, Sendable {
    case light, medium, blizzard

    /// Multiplier applied to `Config.flakeDensity`.
    public var densityMultiplier: Float {
        switch self {
        case .light: 0.45
        case .medium: 1
        case .blizzard: 3.2
        }
    }
}
