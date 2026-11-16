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

    @Test func bladeDischargesOnlySnowItCrosses() {
        let cap = makeCap(radius: 0)
        cap.fill(fraction: 0.8)
        cap.deposit(at: 205, amount: 5)
        let before = cap.mass
        let ahead = cap.heights[49]
        let removed = cap.clearSnow(from: 210, to: 200)
        #expect(removed > 0)
        #expect(abs(cap.mass + removed - before) < 0.01)
        #expect(cap.heights[49] == ahead)
        #expect(cap.heights[52] == 0)
        #expect(cap.clearSnow(from: 210, to: 200) == 0)
    }

    @Test func bladeDischargeDoesNotDependOnStepSize() {
        let largeStep = makeCap(radius: 0)
        let smallSteps = makeCap(radius: 0)
        largeStep.fill(fraction: 0.8)
        smallSteps.fill(fraction: 0.8)
        let removed = largeStep.clearSnow(from: 210, to: 200)
        var incremental: Float = 0
        for step in 0..<40 {
            let old = 210 - Float(step) * 0.25
            incremental += smallSteps.clearSnow(from: old, to: old - 0.25)
        }
        #expect(abs(removed - incremental) < 0.01)
        for (large, small) in zip(largeStep.heights, smallSteps.heights) {
            #expect(abs(large - small) < 0.001)
        }
    }

    @Test func bladeDischargesSnowAtTheScreenEdge() {
        let cap = makeCap(radius: 0)
        cap.deposit(at: frame.minX + 3, amount: 20)
        let before = cap.mass
        let exported = cap.clearSnow(from: frame.minX + 8, to: frame.minX - 1)
        #expect(exported > 0)
        #expect(abs(cap.mass + exported - before) < 0.01)
    }

    @Test func ceilingLimitsHeight() {
        let cap = makeCap()
        var spills: [SnowSpill] = []
        for _ in 0..<10_000 {
            cap.deposit(at: 300, amount: 12)
            cap.relax(dt: 1.0 / 30, spills: &spills)
        }
        #expect(cap.heights.max()! <= Config.capMaxHeight + 1e-3)
        #expect(cap.heights.max()! > Config.capMaxHeight * 0.7)
    }

    @Test func relaxationConservesMassAwayFromEdges() {
        let cap = makeCap()
        for _ in 0..<40 { cap.deposit(at: 300, amount: 12) }
        let before = cap.mass
        var spills: [SnowSpill] = []
        for _ in 0..<500 { cap.relax(dt: 1.0 / 30, spills: &spills) }
        #expect(spills.isEmpty)
        #expect(abs(cap.mass - before) < 1e-2)
    }

    @Test func relaxationReachesAngleOfRepose() {
        let cap = makeCap()
        for _ in 0..<60 { cap.deposit(at: 300, amount: 12) }
        var spills: [SnowSpill] = []
        for _ in 0..<2000 { cap.relax(dt: 1.0 / 30, spills: &spills) }
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
        let melted = cap.meltedMass
        for _ in 0..<300 { cap.relax(dt: 1.0 / 30, spills: &spills) }
        let spilled = spills.reduce(0) { $0 + $1.mass }
        #expect(abs(cap.mass + spilled + (cap.meltedMass - melted) - before) < 1e-2)
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

    @Test func dockResizeKeepsSnowAtItsScreenPosition() {
        let dock = Rect(x: 200, y: 3, width: 1000, height: 84)
        let cap = SnowCap(id: World.dockCapID, frame: dock, cornerRadius: Config.dockCornerRadius)
        for x: Float in [250, 400, 1000, 1150] { cap.deposit(at: x, amount: 50) }
        var spills: [SnowSpill] = []
        let narrower = Rect(x: 300, y: 3, width: 800, height: 84)
        cap.updateCentered(frame: narrower, spills: &spills)

        #expect(cap.heights[Int((400 - narrower.minX) / cap.spacing)] > 0)
        #expect(cap.heights[Int((1000 - narrower.minX) / cap.spacing)] > 0)
        #expect(cap.heights[Int((500 - narrower.minX) / cap.spacing)] == 0)
        #expect(spills.contains { $0.position.x < narrower.minX })
        #expect(spills.contains { $0.position.x > narrower.maxX })
    }

    @Test func depositEasesIn() {
        let cap = makeCap()
        cap.deposit(at: 300, amount: 12)
        #expect(cap.heights.max()! == 0) // nothing pops in instantly
        var spills: [SnowSpill] = []
        cap.relax(dt: 1.0 / 30, spills: &spills)
        let first = cap.heights.max()!
        #expect(first > 0)
        for _ in 0..<60 { cap.relax(dt: 1.0 / 30, spills: &spills) }
        #expect(cap.heights.max()! > first)
        #expect(abs(cap.mass - 12) < 1e-2)
    }

    @Test func loweringMaxHeightTrimsSnow() {
        let cap = makeCap()
        cap.fill(fraction: 1)
        cap.setMaxHeight(6)
        #expect(cap.heights.max()! <= 6 + 1e-3)
        var spills: [SnowSpill] = []
        for _ in 0..<1000 {
            cap.deposit(at: 300, amount: 12)
            cap.relax(dt: 1.0 / 30, spills: &spills)
        }
        #expect(cap.heights.max()! <= 6 + 1e-3)
        cap.setMaxHeight(20)
        for _ in 0..<3000 {
            cap.deposit(at: 300, amount: 12)
            cap.relax(dt: 1.0 / 30, spills: &spills)
        }
        #expect(cap.heights.max()! > 12)
    }

    @Test func capsSettleAndWakeOnChange() {
        let cap = makeCap()
        cap.fill(fraction: 0.5)
        var spills: [SnowSpill] = []
        for _ in 0..<600 { cap.relax(dt: 1.0 / 30, spills: &spills) }
        #expect(cap.isSettled)
        let heights = cap.heights
        cap.relax(dt: 1.0 / 30, spills: &spills)
        #expect(cap.heights == heights)
        cap.deposit(at: 300, amount: 12)
        #expect(!cap.isSettled)
        cap.relax(dt: 1.0 / 30, spills: &spills)
        #expect(cap.heights != heights)
    }

    @Test func endsMeltWithoutDebris() {
        let cap = makeCap(radius: 14)
        cap.fill(fraction: 1)
        var spills: [SnowSpill] = []
        for _ in 0..<600 {
            cap.deposit(at: frame.minX + 4, amount: 12)
            cap.relax(dt: 1.0 / 30, spills: &spills)
        }
        #expect(spills.isEmpty)
        #expect(cap.meltedMass > 0)
    }

    @Test func partialShedKeepsTheRest() {
        let cap = makeCap()
        cap.fill(fraction: 1)
        let before = cap.mass
        var spills: [SnowSpill] = []
        cap.shed(fraction: 0.25, velocity: [100, 0], spills: &spills)
        let spilled = spills.reduce(0) { $0 + $1.mass }
        #expect(abs(spilled - before * 0.25) < before * 0.01)
        #expect(abs(cap.mass - before * 0.75) < before * 0.01)
        #expect(spills.allSatisfy { $0.velocity == [100, 0] })
    }

    @Test func brushRemovesOnlyTouchedColumns() {
        let cap = makeCap()
        cap.fill(fraction: 1)
        cap.visible = [Interval(frame.minX, frame.maxX)]
        var spills: [SnowSpill] = []
        // Horizontal swipe 4 pt above the edge from x=280 to x=320.
        let removed = cap.brush(from: [280, frame.maxY + 4], to: [320, frame.maxY + 4], radius: 10,
                                velocity: [50, 90], spills: &spills)
        #expect(removed > 0)
        for i in 0..<cap.columnCount {
            let x = cap.x(ofColumn: i)
            if x > 272 && x < 328 { #expect(cap.heights[i] == 0) }
            // Away from the brush and from the drained corners, snow stays.
            if (x > 130 && x < 260) || (x > 340 && x < 470) { #expect(cap.heights[i] > 0) }
        }
        #expect(abs(spills.reduce(0) { $0 + $1.mass } - removed) < 1e-3)
    }

    @Test func brushFarAboveDoesNothing() {
        let cap = makeCap()
        cap.fill(fraction: 1)
        cap.visible = [Interval(frame.minX, frame.maxX)]
        var spills: [SnowSpill] = []
        let removed = cap.brush(from: [200, frame.maxY + 40], to: [400, frame.maxY + 40], radius: 10,
                                velocity: .zero, spills: &spills)
        #expect(removed == 0)
    }

    @Test func brushIgnoresHiddenPart() {
        let cap = makeCap()
        cap.fill(fraction: 1)
        cap.visible = [Interval(frame.minX, 250)]
        var spills: [SnowSpill] = []
        cap.brush(from: [300, frame.maxY + 4], to: [320, frame.maxY + 4], radius: 10, velocity: .zero, spills: &spills)
        #expect(spills.isEmpty)
    }

    @Test func rigidDisplacementSeparatesMoveFromResize() {
        let a = Rect(x: 0, y: 0, width: 100, height: 100)
        #expect(SnowCap.rigidDisplacement(from: a, to: a.offsetBy([5, -3])) == [5, -3])
        #expect(SnowCap.rigidDisplacement(from: a, to: Rect(x: 0, y: 0, width: 80, height: 100)) == [0, 0])
        #expect(SnowCap.rigidDisplacement(from: a, to: Rect(x: 20, y: 0, width: 80, height: 100)) == [0, 0])
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
