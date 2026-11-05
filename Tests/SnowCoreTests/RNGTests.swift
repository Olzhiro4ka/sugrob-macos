import Testing
@testable import SnowCore

struct RNGTests {
    @Test func sameSeedSameSequence() {
        var a = SplitMix64(seed: 42)
        var b = SplitMix64(seed: 42)
        for _ in 0..<1000 {
            #expect(a.next() == b.next())
        }
    }

    @Test func differentSeedsDiverge() {
        var a = SplitMix64(seed: 1)
        var b = SplitMix64(seed: 2)
        #expect(a.next() != b.next())
    }

    @Test func unitIsInHalfOpenRange() {
        var rng = SplitMix64(seed: 7)
        for _ in 0..<10_000 {
            let value = rng.nextUnit()
            #expect(value >= 0 && value < 1)
        }
    }

    @Test func rangeIsRespected() {
        var rng = SplitMix64(seed: 9)
        for _ in 0..<10_000 {
            let value = rng.next(in: 25...60)
            #expect(value >= 25 && value <= 60)
        }
    }
}
