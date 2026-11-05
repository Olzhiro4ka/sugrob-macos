import Testing
@testable import SnowCore

struct OcclusionTests {
    private let back = Rect(x: 0, y: 0, width: 1000, height: 500) // top edge at y = 500

    private func visible(front: Rect) -> [Interval] {
        Occlusion.visibleIntervals(frames: [front, back], present: [true, true])[1]
    }

    @Test func noOverlapKeepsWholeEdge() {
        let front = Rect(x: 1200, y: 0, width: 300, height: 600)
        #expect(visible(front: front) == [Interval(0, 1000)])
    }

    @Test func frontWindowSplitsEdge() {
        let front = Rect(x: 300, y: 200, width: 200, height: 400) // covers 300…500 across y=500
        #expect(visible(front: front) == [Interval(0, 300), Interval(500, 1000)])
    }

    @Test func frontWindowCoveringEverythingHidesCap() {
        let front = Rect(x: -50, y: 100, width: 1100, height: 600)
        #expect(visible(front: front).isEmpty)
    }

    @Test func frontWindowBelowEdgeDoesNotHide() {
        let front = Rect(x: 300, y: 100, width: 200, height: 300) // top at 400 < 500
        #expect(visible(front: front) == [Interval(0, 1000)])
    }

    @Test func frontWindowInSnowBandHides() {
        // Bottom 5 pt above the edge: it would cover the snow.
        let front = Rect(x: 300, y: 505, width: 200, height: 300)
        #expect(visible(front: front) == [Interval(0, 300), Interval(500, 1000)])
    }

    @Test func frontWindowWellAboveDoesNotHide() {
        let front = Rect(x: 300, y: 500 + Config.occlusionBand + 1, width: 200, height: 300)
        #expect(visible(front: front) == [Interval(0, 1000)])
    }

    @Test func backWindowNeverHidesFront() {
        let front = Rect(x: 300, y: 200, width: 200, height: 400)
        let result = Occlusion.visibleIntervals(frames: [front, back], present: [true, true])
        #expect(result[0] == [Interval(300, 500)])
    }

    @Test func missingWindowNeitherShowsNorOccludes() {
        let front = Rect(x: 300, y: 200, width: 200, height: 400)
        let result = Occlusion.visibleIntervals(frames: [front, back], present: [false, true])
        #expect(result[0].isEmpty)
        #expect(result[1] == [Interval(0, 1000)])
    }

    @Test func slivers() {
        // Two front windows leave a 1 pt gap: too small to show snow.
        let a = Rect(x: 0, y: 0, width: 500, height: 600)
        let b = Rect(x: 501, y: 0, width: 600, height: 600)
        let result = Occlusion.visibleIntervals(frames: [a, b, back], present: [true, true, true])
        #expect(result[2].isEmpty)
    }

    @Test func intervalSubtraction() {
        var list = [Interval(0, 10), Interval(20, 30)]
        Intervals.subtract(&list, 5, 25)
        #expect(list == [Interval(0, 5), Interval(25, 30)])
    }
}
