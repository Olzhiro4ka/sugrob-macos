import Testing
@testable import SnowCore

struct SnowCapTests {
    private let frame = Rect(x: 100, y: 0, width: 400, height: 300)

    private func makeCap(radius: Float = 10) -> SnowCap {
        SnowCap(id: 1, frame: frame, cornerRadius: radius)
    }

    @Test func columnsCoverWidth() {
        let cap = makeCap()
        #expect(cap.columnCount == 201)
        #expect(abs(cap.x(ofColumn: cap.columnCount - 1) - frame.maxX) < 1e-3)
    }

    @Test func cornersDroop() {
        let cap = makeCap(radius: 12)
        #expect(cap.base[0] == -12)
        #expect(cap.base[cap.columnCount / 2] == 0)
        #expect(cap.base[1] < 0 && cap.base[1] > -12)
        #expect(SnowCap.cornerDrop(fromEdge: 12, radius: 12) == 0)
    }

    @Test func depositAddsMass() {
        let cap = makeCap()
        let added = cap.deposit(at: 300, amount: 12)
        #expect(abs(added - 12) < 1e-3)
        #expect(abs(cap.mass - 12) < 1e-3)
    }

    @Test func ceilingLimitsHeight() {
        let cap = makeCap()
        for _ in 0..<10_000 { cap.deposit(at: 300, amount: 12) }
        #expect(cap.heights.max()! <= Config.capMaxHeight + 1e-3)
    }

    @Test func relaxationConservesMassAwayFromEdges() {
        let cap = makeCap()
        for _ in 0..<40 { cap.deposit(at: 300, amount: 12) }
        let before = cap.mass
        var spills: [SnowSpill] = []
        for _ in 0..<500 { cap.relax(spills: &spills) }
        #expect(spills.isEmpty)
        #expect(abs(cap.mass - before) < 1e-2)
    }

    @Test func relaxationReachesAngleOfRepose() {
        let cap = makeCap()
        for _ in 0..<60 { cap.deposit(at: 300, amount: 12) }
        var spills: [SnowSpill] = []
        for _ in 0..<2000 { cap.relax(spills: &spills) }
        let maxRise = Config.reposeSlope * cap.spacing
        for i in 0..<(cap.columnCount - 1) {
            let rise = abs(cap.surfaceY(ofColumn: i) - cap.surfaceY(ofColumn: i + 1))
            // Allow slack where the column is empty (the bare corner arc is steeper than repose).
            if cap.heights[i] > 0.01 && cap.heights[i + 1] > 0.01 {
                #expect(rise <= maxRise * 1.05)
            }
        }
    }

    @Test func massIsConservedIncludingSpills() {
        let cap = makeCap()
        cap.fill(fraction: 1)
        let before = cap.mass
        var spills: [SnowSpill] = []
        for _ in 0..<300 { cap.relax(spills: &spills) }
        let spilled = spills.reduce(0) { $0 + $1.mass }
        #expect(abs(cap.mass + spilled - before) < 1e-2)
    }

    @Test func endsDrainOverTheCorner() {
        let cap = makeCap(radius: 14)
        cap.fill(fraction: 1)
        #expect(cap.heights[0] <= Config.capEdgeHold + 0.5)
        #expect(cap.heights[cap.columnCount / 2] > Config.capMaxHeight * 0.6)
    }

    @Test func moveKeepsSnow() {
        let cap = makeCap()
        cap.fill(fraction: 1)
        let heights = cap.heights
        var spills: [SnowSpill] = []
        cap.update(frame: frame.offsetBy([350, -120]), spills: &spills)
        #expect(cap.heights == heights)
        #expect(spills.isEmpty)
        #expect(cap.edgeY == frame.maxY - 120)
    }

    @Test func narrowingFromRightSpillsTheRemovedPart() {
        let cap = makeCap()
        cap.fill(fraction: 1)
        let before = cap.mass
        let middle = cap.heights[50]
        var spills: [SnowSpill] = []
        let narrower = Rect(x: frame.minX, y: frame.minY, width: 200, height: frame.height)
        cap.update(frame: narrower, spills: &spills)
        let spilled = spills.reduce(0) { $0 + $1.mass }
        #expect(spilled > 0)
        #expect(spills.allSatisfy { $0.position.x > narrower.maxX && $0.velocity.x > 0 })
        // Remaining snow is roughly the left half; nothing is invented.
        #expect(cap.mass + spilled <= before + 1)
        #expect(abs(cap.heights[50] - middle) < 1e-3) // left-anchored columns are untouched
    }

    @Test func narrowingFromLeftAnchorsRight() {
        let cap = makeCap()
        cap.fill(fraction: 1)
        let rightHeights = Array(cap.heights.suffix(60))
        var spills: [SnowSpill] = []
        let narrower = Rect(x: frame.minX + 200, y: frame.minY, width: 200, height: frame.height)
        cap.update(frame: narrower, spills: &spills)
        #expect(spills.allSatisfy { $0.position.x < narrower.minX && $0.velocity.x < 0 })
        let after = Array(cap.heights.suffix(60))
        for (a, b) in zip(after, rightHeights) { #expect(abs(a - b) < 0.05) }
    }

    @Test func shedAllEmptiesCap() {
        let cap = makeCap()
        cap.fill(fraction: 1)
        let before = cap.mass
        var spills: [SnowSpill] = []
        cap.shedAll(velocity: [300, 0], spills: &spills)
        #expect(cap.mass == 0)
        #expect(abs(spills.reduce(0) { $0 + $1.mass } - before) < 1e-2)
    }
}
