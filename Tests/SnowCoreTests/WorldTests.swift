import Testing
@testable import SnowCore

struct WorldTests {
    private let screen = Rect(x: 0, y: 0, width: 1512, height: 982)
    private let window = Rect(x: 200, y: 200, width: 800, height: 500)

    private func makeWorld() -> World {
        let world = World(seed: 42)
        world.intensity = .blizzard
        world.setScreens([screen])
        return world
    }

    private func run(_ world: World, seconds: Float) {
        for _ in 0..<Int(seconds * 30) { world.step(dt: 1.0 / 30) }
    }

    @Test func snowAccumulatesOnAWindow() {
        let world = makeWorld()
        world.ingestWindows([WindowSample(id: 1, frame: window)])
        run(world, seconds: 60)
        let cap = world.caps[0]
        #expect(cap.mass > 0)
        #expect(cap.heights.max()! <= Config.capMaxHeight + 1e-3)
    }

    @Test func coveredPartGetsNoSnow() {
        let world = makeWorld()
        // Front window covers the right half of the back window's top edge.
        let front = Rect(x: 600, y: 300, width: 600, height: 600)
        world.ingestWindows([WindowSample(id: 2, frame: front), WindowSample(id: 1, frame: window)])
        run(world, seconds: 60)
        let back = world.caps.first { $0.id == 1 }!
        var hiddenMass: Float = 0
        var visibleMass: Float = 0
        for i in 0..<back.columnCount {
            let x = back.x(ofColumn: i)
            // Ignore columns near the boundary that receive a flake's kernel spill-over.
            if x > 610 { hiddenMass += back.heights[i] }
            if x < 590 { visibleMass += back.heights[i] }
        }
        #expect(visibleMass > 0)
        #expect(hiddenMass == 0)
        #expect(back.visible == [Interval(200, 600)])
    }

    @Test func capFollowsWindow() {
        let world = makeWorld()
        world.instantSnow = true
        world.ingestWindows([WindowSample(id: 1, frame: window)])
        world.step(dt: 1.0 / 30)
        let mass = world.caps[0].mass
        world.ingestWindows([WindowSample(id: 1, frame: window.offsetBy([40, 30]))])
        world.step(dt: 1.0 / 30)
        #expect(world.caps[0].frame.minY > window.minY)
        #expect(abs(world.caps[0].mass - mass) < mass * 0.02)
    }

    @Test func briefDisappearanceKeepsSnow() {
        let world = makeWorld()
        world.instantSnow = true
        let sample = WindowSample(id: 1, frame: window)
        world.ingestWindows([sample])
        world.step(dt: 1.0 / 30)
        let mass = world.caps[0].mass
        // A Space switch hides it for two polls.
        world.ingestWindows([])
        world.step(dt: 1.0 / 30)
        #expect(world.caps[0].isPresent == false)
        world.ingestWindows([])
        world.step(dt: 1.0 / 30)
        world.ingestWindows([sample])
        world.step(dt: 1.0 / 30)
        #expect(world.caps.count == 1)
        #expect(abs(world.caps[0].mass - mass) < mass * 0.02)
    }

    @Test func goneWindowShedsItsSnow() {
        let world = makeWorld()
        world.instantSnow = true
        world.ingestWindows([WindowSample(id: 1, frame: window)])
        world.step(dt: 1.0 / 30)
        for _ in 0..<Config.disappearPolls { world.ingestWindows([]) }
        #expect(world.caps.isEmpty)
        #expect(world.spills.reduce(0) { $0 + $1.mass } > 0)
    }

    @Test func noSnowOnWindowsWhenDisabled() {
        let world = makeWorld()
        world.snowOnWindows = false
        world.ingestWindows([WindowSample(id: 1, frame: window)])
        run(world, seconds: 30)
        #expect(world.caps[0].mass == 0)
    }

    @Test func deterministicAccumulation() {
        func run() -> [Float] {
            let world = makeWorld()
            world.ingestWindows([WindowSample(id: 1, frame: window)])
            self.run(world, seconds: 20)
            return world.caps[0].heights
        }
        #expect(run() == run())
    }
}
