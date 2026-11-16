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

    // MARK: Windows

    /// Window corner radius on macOS 14/15 (pt). Caps droop along this arc at both ends.
    public static let windowCornerRadiusLegacy: Float = 10
    /// Window corner radius on macOS 26+ (pt). Tahoe varies it per window (toolbar windows are
    /// rounder); this is a compromise that only shapes the droop.
    public static let windowCornerRadiusModern: Float = 16
    /// Minimum window size to carry snow (pt).
    public static let minWindowSize: SIMD2<Float> = [80, 40]
    /// A window must be missing from this many consecutive polls before it counts as gone.
    /// Space switches and Mission Control hide windows for a few frames.
    public static let disappearPolls = 3
    /// Window-list polling interval while idle (s): 8 Hz.
    public static let pollIntervalIdle: Float = 1.0 / 8
    /// Window-list polling interval while the mouse is down or windows just changed (s): 30 Hz.
    public static let pollIntervalActive: Float = 1.0 / 30
    /// How long after the last window change polling stays fast (s).
    public static let pollActiveWindow: Float = 0.5
    /// Mission Control presence polling interval while its animation is showing (s).
    public static let missionControlWatchInterval = 0.25
    /// Polling interval while waiting for window frames to settle after Mission Control (s).
    public static let missionControlRecoveryPollInterval = 0.05
    /// Longest recovery pause when window frames keep changing (s).
    public static let missionControlRecoveryMaxWait = 0.6
    /// Maximum window-frame change considered settled after Mission Control (pt).
    public static let missionControlFrameTolerance: Float = 2
    /// Weight of the newest sample in the exponentially smoothed velocity (0…1).
    public static let velocitySmoothing: Float = 0.6
    /// Visible intervals shorter than this are dropped (pt).
    public static let minVisibleInterval: Float = 2
    /// Allowed uncovered edge when deciding if a window fills a display (pt).
    public static let fullscreenEdgeTolerance: Float = 2

    // MARK: Snow caps

    /// Horizontal distance between heightmap columns (pt).
    public static let capColumnSpacing: Float = 2
    /// Default maximum cap height (pt); user-adjustable within `capMaxHeightRange`. Each column
    /// gets a lumpy ceiling between `maxHeight * capCeilingLumpiness` and `maxHeight`.
    public static let capMaxHeight: Float = 12
    /// Allowed range of the user's "max drift height" setting (pt).
    public static let capMaxHeightRange: ClosedRange<Float> = 6...20
    /// Lower bound of the per-column ceiling as a fraction of `capMaxHeight`.
    public static let capCeilingLumpiness: Float = 0.75
    /// Wavelength of the ceiling lumps (pt).
    public static let capLumpWavelength: Float = 22
    /// Snow area one absorbed flake adds to a cap (pt²) at medium intensity.
    /// Flux ≈ 0.0038 flakes/(pt·s) ⇒ 12 pt² ≈ 0.046 pt/s ⇒ a full cap in ~4 minutes.
    public static let snowPerFlake: Float = 12
    /// Half-width of the triangular kernel a flake is spread over (columns).
    public static let depositRadiusColumns = 4
    /// Rate at which freshly deposited snow eases into the heightmap (1/s); avoids visible steps.
    public static let depositEaseRate: Float = 5
    /// Angle of repose as max rise per run (tan θ, θ ≈ 37°).
    public static let reposeSlope: Float = 0.75
    /// Relaxation passes per simulation step.
    public static let relaxPasses = 2
    /// Fraction of the excess slope moved per pass (0…1); < 1 keeps it stable and soft.
    public static let relaxRate: Float = 0.5
    /// Snow height an end column can hold (pt). The excess slides over the rounded corner and
    /// melts away silently: a constant drizzle of particles would look busy and keep the frame
    /// rate at 60 fps.
    public static let capEdgeHold: Float = 0.4
    /// Vertical band above a top edge that a front window must touch to hide that cap (pt).
    public static let occlusionBand: Float = capMaxHeight
    /// Allowed range of the user's wind multiplier (× `windBase`/`windGust`).
    public static let windScaleRange: ClosedRange<Float> = 0...2
    /// `--instant-snow` fills caps to this fraction of their ceiling.
    public static let instantSnowFill: Float = 0.9
    /// Hard bound on simultaneously tracked caps (count).
    public static let maxCaps = 256
    /// Time to retain an off-screen window's snow for a Space or app switch (s).
    public static let hiddenWindowSnowLifetime: Float = 120
    /// Mean screen-edge snow height that starts a plow pass (fraction of max drift height).
    public static let plowTriggerFraction: Float = 0.65
    /// Snowplow travel speed from right to left (pt/s).
    public static let plowSpeed: Float = 50
    /// Displayed sprite dimensions and blade contact offset (pt).
    public static let plowSize = SIMD2<Float>(77, 45)
    public static let plowBladeOffset: Float = 4
    public static let plowBottomOffset: Float = 5
    /// Minimum time between plow passes on one display (s).
    public static let plowCooldown: Float = 15
    /// Hard bound on spill events buffered per step (count).
    public static let maxSpillsPerStep = 4096

    // MARK: Dock (estimated without permissions; calibrated against AX on macOS 26)

    /// Extra width per Dock tile beyond `tilesize` (pt). AX: 68 pt slots at tilesize 64.
    public static let dockTileExtra: Float = 4
    /// Separator width as a fraction of `tilesize`. AX: 30.6 pt at tilesize 64.
    public static let dockSeparatorFactor: Float = 0.478
    /// Padding at each end of the Dock (pt). AX: 7.7 pt.
    public static let dockEndPadding: Float = 7.7
    /// Dock height beyond `tilesize` (pt). AX: 84 pt at tilesize 64.
    public static let dockHeightExtra: Float = 20
    /// Gap between the Dock's top and the bottom of `visibleFrame` (pt). The 90 pt inset at
    /// tilesize 64 leaves 6 pt around an 84 pt Dock; assumed split evenly.
    public static let dockTopGap: Float = 3
    /// Corner radius of the Dock's rounded ends (pt); snow droops off them like off windows.
    public static let dockCornerRadius: Float = 18
    /// How often the Dock estimate is refreshed besides app launch/quit notifications (s).
    public static let dockRefreshInterval: Double = 5

    // MARK: Debris (knocked-off snow)

    /// Hard upper bound of simultaneous debris particles (count).
    public static let debrisCapacity = 4096
    /// Snow carried by one debris particle (pt²). Spills are split into particles of this mass
    /// with stochastic rounding, so mass is conserved on average.
    public static let debrisParticleMass: Float = 4
    /// Gravity (pt/s²).
    public static let gravity: Float = 500
    /// Linear air drag (1/s).
    public static let debrisDrag: Float = 0.8
    /// Maximum life of a particle (s).
    public static let debrisMaxLife: Float = 6
    /// Random velocity added to every new particle (pt/s, ± per axis).
    public static let debrisJitter: SIMD2<Float> = [12, 10]
    /// Debris radius range (pt).
    public static let debrisRadius: ClosedRange<Float> = 0.9...2.0
    /// Debris opacity range.
    public static let debrisOpacity: ClosedRange<Float> = 0.75...1.0

    // MARK: Interactions

    /// Window displacement per step below which nothing is shed (pt); filters bounds rounding.
    public static let shedDeadZone: Float = 0.3
    /// Horizontal speed of snow spilling from a resized surface (pt/s).
    public static let resizeSpillHorizontalKick: Float = 25
    /// Initial upward speed of snow spilling from a resized surface (pt/s).
    public static let resizeSpillVerticalKick: Float = 15
    /// Fraction of window velocity passed to detached snow in both axes (0…1).
    public static let shedVelocityInherit: Float = 0.85
    /// Minimum launch speed in an axis where the window actually moved (pt/s).
    public static let shedMinLaunchSpeed: Float = 60
    /// Maximum speed per axis of snow detached by a moving window (pt/s).
    public static let shedMaxLaunchSpeed: Float = 700
    /// A window must rest this long before it collects snow again (s).
    public static let settleDelay: Float = 0.3
    /// Brief rest before loose snow can land on a window again (s).
    public static let debrisLandingDelay: Float = 0.06
    /// Cursor brush radius (pt).
    public static let brushRadius: Float = 10
    /// Minimum cursor movement per step for the brush to act (pt).
    public static let brushMinMove: Float = 0.5
    /// Fraction of each touched column detached by one brush pass (0…1).
    public static let brushReleaseFraction: Float = 0.55
    /// Fraction of horizontal cursor velocity passed on to brushed snow (0…1).
    public static let brushVelocityInherit: Float = 0.10
    /// Maximum horizontal speed of brushed snow (pt/s).
    public static let brushMaxHorizontalSpeed: Float = 110
    /// Fraction of vertical cursor speed passed to brushed snow (0…1).
    public static let brushVerticalVelocityInherit: Float = 0.30
    /// Allowed vertical launch speed after brushing (pt/s, negative is downward).
    public static let brushVerticalSpeedRange: ClosedRange<Float> = -180...460
    /// Base upward kick of brushed snow when the cursor moves horizontally (pt/s).
    public static let brushKick: Float = 70

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
