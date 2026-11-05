import Testing
@testable import SnowCore

struct WindowRegistryTests {
    private let frame = Rect(x: 100, y: 100, width: 600, height: 400)

    @Test func appearsImmediately() {
        let registry = WindowRegistry()
        let changes = registry.ingest([WindowSample(id: 7, frame: frame)], time: 0)
        #expect(changes.appeared == [7])
        #expect(registry.entries[7]?.isPresent == true)
    }

    @Test func disappearanceIsDebounced() {
        let registry = WindowRegistry()
        registry.ingest([WindowSample(id: 7, frame: frame)], time: 0)
        for poll in 1..<Config.disappearPolls {
            let changes = registry.ingest([], time: Float(poll))
            #expect(changes.disappeared.isEmpty)
            #expect(registry.entries[7]?.isPresent == false)
        }
        let changes = registry.ingest([], time: 10)
        #expect(changes.disappeared.map(\.id) == [7])
        #expect(registry.entries[7] == nil)
    }

    @Test func reappearingWithinDebounceIsTheSameWindow() {
        let registry = WindowRegistry()
        registry.ingest([WindowSample(id: 7, frame: frame)], time: 0)
        registry.ingest([], time: 0.1)
        let changes = registry.ingest([WindowSample(id: 7, frame: frame)], time: 0.2)
        #expect(changes.appeared.isEmpty)
        #expect(changes.disappeared.isEmpty)
        #expect(registry.entries[7]?.isPresent == true)
    }

    @Test func velocityTracksMovement() {
        let registry = WindowRegistry()
        registry.ingest([WindowSample(id: 1, frame: frame)], time: 0)
        registry.ingest([WindowSample(id: 1, frame: frame.offsetBy([10, 0]))], time: 0.1)
        let velocity = registry.entries[1]!.velocity
        #expect(abs(velocity.x - 100) < 1e-3)
        #expect(registry.anyMoving)
        // No extrapolation: the frame is the latest poll.
        #expect(registry.frame(of: 1) == frame.offsetBy([10, 0]))

        registry.ingest([WindowSample(id: 1, frame: frame.offsetBy([10, 0]))], time: 0.2)
        #expect(registry.entries[1]!.velocity == .zero)
        #expect(!registry.anyMoving)
    }

    @Test func zOrderFollowsPoll() {
        let registry = WindowRegistry()
        let a = WindowSample(id: 1, frame: frame)
        let b = WindowSample(id: 2, frame: frame.offsetBy([50, 50]))
        registry.ingest([a, b], time: 0)
        #expect(registry.order == [1, 2])
        let changes = registry.ingest([b, a], time: 0.1)
        #expect(registry.order == [2, 1])
        #expect(changes.anyChange)
    }
}
