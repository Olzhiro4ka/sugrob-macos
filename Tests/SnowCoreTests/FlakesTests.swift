import Testing
@testable import SnowCore

struct FlakesTests {
    private let laptop = Rect(x: 0, y: 0, width: 1512, height: 982)

    @Test func initialFillMatchesDensityAndStaysInside() {
        var rng = SplitMix64(seed: 1)
        var pool = FlakePool()
        pool.setRegions([laptop], density: 90, rng: &rng)
        #expect(pool.count == Int((90 * laptop.area / 1_000_000).rounded()))
        for i in 0..<pool.count {
            let s = pool.sprites[i]
            #expect(laptop.contains(SIMD2(s.x, s.y)))
            #expect(Config.flakeRadius.contains(s.z))
            #expect(Config.flakeOpacity.contains(s.w))
        }
    }

    @Test func countNeverExceedsCapacity() {
        var rng = SplitMix64(seed: 2)
        var pool = FlakePool(capacity: 50)
        pool.setRegions([laptop], density: 10_000, rng: &rng)
        #expect(pool.count == 50)
        for _ in 0..<600 { pool.step(dt: 1.0 / 30, wind: 3, rng: &rng) }
        #expect(pool.count == 50)
    }

    @Test func flakesFallAndRecycleWithinBounds() {
        var rng = SplitMix64(seed: 3)
        var pool = FlakePool()
        pool.setRegions([laptop], density: 90, rng: &rng)
        let start = pool.sprites[0].y
        pool.step(dt: 0.1, wind: 0, rng: &rng)
        #expect(pool.sprites[0].y < start)

        // Two minutes: every flake has crossed the screen at least once.
        for _ in 0..<(120 * 30) { pool.step(dt: 1.0 / 30, wind: 20, rng: &rng) }
        let margin = Config.flakeMargin
        for i in 0..<pool.count {
            let s = pool.sprites[i]
            #expect(s.x >= laptop.minX - margin && s.x <= laptop.maxX + margin)
            #expect(s.y >= laptop.minY - margin && s.y <= laptop.maxY + margin)
        }
        #expect(pool.count == pool.targetCount)
    }

    @Test func densityChangeConverges() {
        var rng = SplitMix64(seed: 4)
        var pool = FlakePool()
        pool.setRegions([laptop], density: 90, rng: &rng)
        pool.setDensity(30)
        for _ in 0..<(60 * 30) { pool.step(dt: 1.0 / 30, wind: 0, rng: &rng) }
        #expect(pool.count == pool.targetCount)
        pool.setDensity(300)
        pool.step(dt: 1.0 / 30, wind: 0, rng: &rng)
        #expect(pool.count == pool.targetCount)
    }

    @Test func multipleScreensGetProportionalShare() {
        var rng = SplitMix64(seed: 5)
        var pool = FlakePool()
        let external = Rect(x: 1512, y: -200, width: 2560, height: 1440)
        pool.setRegions([laptop, external], density: 400, rng: &rng)
        for _ in 0..<(120 * 30) { pool.step(dt: 1.0 / 30, wind: 0, rng: &rng) }
        var onExternal = 0
        for i in 0..<pool.count where pool.regionIndex(of: i) == 1 { onExternal += 1 }
        let expected = Float(pool.count) * external.area / (laptop.area + external.area)
        #expect(abs(Float(onExternal) - expected) < expected * 0.15)
    }

    @Test func noRegionsMeansNoFlakes() {
        var rng = SplitMix64(seed: 6)
        var pool = FlakePool()
        pool.setRegions([], density: 90, rng: &rng)
        pool.step(dt: 0.1, wind: 0, rng: &rng)
        #expect(pool.count == 0)
    }

    @Test func worldIsDeterministic() {
        func run() -> [SIMD4<Float>] {
            let world = World(seed: 99)
            world.setScreens([laptop])
            for _ in 0..<300 { world.step(dt: 1.0 / 30) }
            return Array(world.flakes.sprites[0..<world.flakes.count])
        }
        #expect(run() == run())
    }

    @Test func worldClampsLongSteps() {
        let world = World(seed: 1)
        world.setScreens([laptop])
        world.step(dt: 10)
        #expect(abs(world.time - Config.maxStep) < 1e-6)
    }

    @Test func windStaysGentle() {
        for t in stride(from: Float(0), to: 1000, by: 0.5) {
            #expect(abs(Wind.velocity(at: t)) <= Config.windBase + Config.windGust)
        }
    }
}
