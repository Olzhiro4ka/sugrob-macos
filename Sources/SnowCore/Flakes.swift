import Foundation

/// Fixed-capacity pool of falling flakes, struct-of-arrays.
///
/// Active flakes are packed into `0..<count`; removal swaps the last active flake in, so the
/// pool never allocates after `init`. Each flake belongs to a *region* (one screen) and is
/// recycled to the top of a region when it falls out of the bottom of its own.
public struct FlakePool {
    public let capacity: Int
    public private(set) var count = 0

    /// Render data per flake: (x, y, radius, alpha). Kept in one array so the renderer can copy
    /// it straight into a GPU buffer.
    public private(set) var sprites: [SIMD4<Float>]
    private var fallSpeed: [Float]
    private var swayPhase: [Float]
    private var swayOmega: [Float]
    private var swayAmplitude: [Float]
    private var windFactor: [Float]
    private var region: [Int32]

    private var regions: [Rect] = []
    /// Cumulative region widths: respawn picks a region with probability ∝ width, which keeps
    /// the steady-state density equal on screens of different heights.
    private var cumulativeWidth: [Float] = []
    /// Cumulative region areas: used for the initial uniform fill.
    private var cumulativeArea: [Float] = []

    /// Desired number of active flakes; the pool converges to it as flakes recycle.
    public private(set) var targetCount = 0

    public init(capacity: Int = Config.flakeCapacity) {
        self.capacity = capacity
        sprites = Array(repeating: .zero, count: capacity)
        fallSpeed = Array(repeating: 0, count: capacity)
        swayPhase = Array(repeating: 0, count: capacity)
        swayOmega = Array(repeating: 0, count: capacity)
        swayAmplitude = Array(repeating: 0, count: capacity)
        windFactor = Array(repeating: 0, count: capacity)
        region = Array(repeating: 0, count: capacity)
    }

    public var activeRegions: [Rect] { regions }

    /// Replaces the spawn regions (screens) and redistributes all flakes uniformly over them.
    public mutating func setRegions(_ newRegions: [Rect], density: Float, rng: inout SplitMix64) {
        regions = newRegions.filter { $0.width > 0 && $0.height > 0 }
        cumulativeWidth = []
        cumulativeArea = []
        var width: Float = 0
        var area: Float = 0
        for rect in regions {
            width += rect.width
            area += rect.area
            cumulativeWidth.append(width)
            cumulativeArea.append(area)
        }
        count = 0
        setDensity(density)
        while count < targetCount {
            spawn(uniformlyIn: pickRegion(cumulative: cumulativeArea, rng: &rng), rng: &rng)
        }
    }

    /// Sets the density (flakes per Mpt²). New flakes appear at the top of screens; surplus
    /// flakes vanish as they reach the bottom, so changes fade in and out naturally.
    public mutating func setDensity(_ density: Float) {
        let totalArea = cumulativeArea.last ?? 0
        targetCount = min(capacity, Int((density * totalArea / 1_000_000).rounded()))
    }

    public mutating func step(dt: Float, wind: Float, rng: inout SplitMix64) {
        step(dt: dt, wind: wind, rng: &rng) { _, _, _ in false }
    }

    /// Advances all flakes. `land(previous, current, radius)` is asked about every flake that
    /// moved; returning true absorbs it (it is recycled like a flake that left the screen).
    public mutating func step(
        dt: Float, wind: Float, rng: inout SplitMix64,
        land: (SIMD2<Float>, SIMD2<Float>, Float) -> Bool
    ) {
        guard !regions.isEmpty else {
            count = 0
            return
        }
        let margin = Config.flakeMargin
        var i = 0
        while i < count {
            var sprite = sprites[i]
            let previous = SIMD2(sprite.x, sprite.y)
            swayPhase[i] += swayOmega[i] * dt
            let sway = swayAmplitude[i] * swayOmega[i] * cos(swayPhase[i])
            sprite.x += (wind * windFactor[i] + sway) * dt
            sprite.y -= fallSpeed[i] * dt

            let bounds = regions[Int(region[i])]
            if sprite.x < bounds.minX - margin {
                sprite.x += bounds.width + 2 * margin
            } else if sprite.x > bounds.maxX + margin {
                sprite.x -= bounds.width + 2 * margin
            }

            let landed = land(previous, SIMD2(sprite.x, sprite.y), sprite.z)
            if landed || sprite.y < bounds.minY - margin {
                if count > targetCount {
                    remove(at: i)
                    continue // the swapped-in flake at `i` still needs its step
                }
                respawnAtTop(i, rng: &rng)
            } else {
                sprites[i] = sprite
            }
            i += 1
        }
        // Grow towards the target from the top of the screens.
        while count < targetCount {
            count += 1
            respawnAtTop(count - 1, rng: &rng)
        }
    }

    /// Region index of the flake at `index` (test hook).
    func regionIndex(of index: Int) -> Int { Int(region[index]) }

    // MARK: Private

    private mutating func spawn(uniformlyIn regionIndex: Int, rng: inout SplitMix64) {
        let bounds = regions[regionIndex]
        let index = count
        count += 1
        initialize(index, regionIndex: regionIndex, rng: &rng)
        sprites[index].x = bounds.minX + rng.nextUnit() * bounds.width
        sprites[index].y = bounds.minY + rng.nextUnit() * bounds.height
    }

    private mutating func respawnAtTop(_ index: Int, rng: inout SplitMix64) {
        let regionIndex = pickRegion(cumulative: cumulativeWidth, rng: &rng)
        let bounds = regions[regionIndex]
        initialize(index, regionIndex: regionIndex, rng: &rng)
        sprites[index].x = bounds.minX + rng.nextUnit() * bounds.width
        sprites[index].y = bounds.maxY + rng.nextUnit() * Config.flakeMargin
    }

    private mutating func initialize(_ index: Int, regionIndex: Int, rng: inout SplitMix64) {
        // `size` in 0…1 drives radius, fall speed and wind response together.
        let size = rng.nextUnit()
        let radius = Config.flakeRadius.lowerBound
            + (Config.flakeRadius.upperBound - Config.flakeRadius.lowerBound) * size
        let alpha = rng.next(in: Config.flakeOpacity)
        let speed = Config.flakeFallSpeed.lowerBound
            + (Config.flakeFallSpeed.upperBound - Config.flakeFallSpeed.lowerBound) * size
        let jitter = 1 + Config.flakeFallJitter * (2 * rng.nextUnit() - 1)
        let clampedSpeed = min(max(speed * jitter, Config.flakeFallSpeed.lowerBound), Config.flakeFallSpeed.upperBound)

        sprites[index] = SIMD4(0, 0, radius, alpha)
        fallSpeed[index] = clampedSpeed
        swayPhase[index] = rng.nextUnit() * 2 * Float.pi
        swayOmega[index] = 2 * Float.pi * rng.next(in: Config.flakeSwayFrequency)
        swayAmplitude[index] = rng.next(in: Config.flakeSwayAmplitude)
        windFactor[index] = 1 - (1 - Config.windLargeFlakeFactor) * size
        region[index] = Int32(regionIndex)
    }

    private mutating func remove(at index: Int) {
        let last = count - 1
        if index != last {
            sprites[index] = sprites[last]
            fallSpeed[index] = fallSpeed[last]
            swayPhase[index] = swayPhase[last]
            swayOmega[index] = swayOmega[last]
            swayAmplitude[index] = swayAmplitude[last]
            windFactor[index] = windFactor[last]
            region[index] = region[last]
        }
        count = last
    }

    private func pickRegion(cumulative: [Float], rng: inout SplitMix64) -> Int {
        guard let total = cumulative.last, total > 0 else { return 0 }
        let target = rng.nextUnit() * total
        return cumulative.firstIndex { target < $0 } ?? cumulative.count - 1
    }
}
