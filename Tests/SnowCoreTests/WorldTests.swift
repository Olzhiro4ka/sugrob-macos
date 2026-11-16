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
            // Near the boundary, relaxation legitimately slides a little snow under the cover.
            if x > 630 { hiddenMass += back.heights[i] }
            if x < 590 { visibleMass += back.heights[i] }
        }
        #expect(visibleMass > 0)
        #expect(hiddenMass < visibleMass * 0.01)
        #expect(back.visible == [Interval(200, 600)])
    }

    @Test func briskWindowMovementShedsImmediately() {
        let world = makeWorld()
        world.instantSnow = true
        world.snowOnWindows = false
        world.ingestWindows([WindowSample(id: 1, frame: window)])
        world.step(dt: 1.0 / 30)
        let mass = world.caps[0].mass
        #expect(mass > 0)
        // A single drag poll at ~600 pt/s releases the cap immediately.
        for poll in 1...1 {
            world.ingestWindows([WindowSample(id: 1, frame: window.offsetBy([Float(poll) * 20, 0]))])
            world.step(dt: 1.0 / 30)
        }
        #expect(world.caps[0].mass < mass * 0.05)
        #expect(world.debris.count > 0)
        // Shed snow carries the window's direction of motion on average.
        var vx: Float = 0
        for i in 0..<world.debris.count { vx += world.debris.velocities[i].x }
        #expect(vx / Float(world.debris.count) > 350)
        #expect(vx / Float(world.debris.count) < 550)
    }

    @Test func firstSmallWindowMoveDetachesSnowWithoutCarryingIt() {
        let world = makeWorld()
        world.instantSnow = true
        world.snowOnWindows = false
        world.ingestWindows([WindowSample(id: 1, frame: window)])
        world.step(dt: 1.0 / 30)
        let originalMass = world.caps[0].mass

        world.ingestWindows([WindowSample(id: 1, frame: window.offsetBy([1, 0]))])
        world.step(dt: 1.0 / 30)

        #expect(world.caps[0].mass < originalMass * 0.05)
        #expect(world.debris.count > 0)
        let meanVX = (0..<world.debris.count).map { world.debris.velocities[$0].x }
            .reduce(0, +) / Float(world.debris.count)
        #expect(meanVX > 50)
        #expect(meanVX < 90)
    }

    @Test func windowMotionSetsDetachedSnowDirectionFromItsOldPosition() {
        let world = makeWorld()
        world.instantSnow = true
        world.snowOnWindows = false
        world.ingestWindows([WindowSample(id: 1, frame: window)])
        world.step(dt: 1.0 / 30)

        world.ingestWindows([WindowSample(id: 1, frame: window.offsetBy([20, -20]))])
        world.step(dt: 1.0 / 30)

        #expect(world.debris.count > 0)
        let positions = (0..<world.debris.count).map { world.debris.sprites[$0] }
        let velocities = (0..<world.debris.count).map { world.debris.velocities[$0] }
        let meanX = positions.map(\.x).reduce(0, +) / Float(positions.count)
        let meanVX = velocities.map(\.x).reduce(0, +) / Float(velocities.count)
        let meanVY = velocities.map(\.y).reduce(0, +) / Float(velocities.count)
        #expect(meanX < window.midX + 5)
        #expect(meanVX > 250)
        #expect(meanVY < -250)
    }

    @Test func reversingWindowDirectionImmediatelyReversesSnow() {
        let world = makeWorld()
        world.instantSnow = true
        world.snowOnWindows = false
        world.ingestWindows([WindowSample(id: 1, frame: window)])
        world.step(dt: 1.0 / 30)
        world.ingestWindows([WindowSample(id: 1, frame: window.offsetBy([20, 0]))])
        world.step(dt: 1.0 / 30)
        world.clearSnow()
        world.caps[0].fill(fraction: Config.instantSnowFill)

        world.ingestWindows([WindowSample(id: 1, frame: window.offsetBy([15, 0]))])
        world.step(dt: 1.0 / 30)

        #expect(world.debris.count > 0)
        let meanVX = (0..<world.debris.count).map { world.debris.velocities[$0].x }
            .reduce(0, +) / Float(world.debris.count)
        #expect(meanVX < -50)
    }

    @Test func gentleWindowMovementAlsoStartsShedding() {
        let world = makeWorld()
        world.instantSnow = true
        world.snowOnWindows = false
        world.ingestWindows([WindowSample(id: 1, frame: window)])
        world.step(dt: 1.0 / 30)
        let mass = world.caps[0].mass

        world.ingestWindows([WindowSample(id: 1, frame: window.offsetBy([2, 0]))])
        world.step(dt: 1.0 / 30)
        #expect(world.caps[0].mass < mass * 0.8)
        #expect(world.debris.count > 0)

        for poll in 2...30 {
            world.ingestWindows([WindowSample(id: 1, frame: window.offsetBy([Float(poll) * 2, 0]))])
            world.step(dt: 1.0 / 30)
        }
        #expect(world.caps[0].mass < mass * 0.05)
    }

    @Test func movedWindowCanCatchFallingSnowAfterItStops() {
        let world = makeWorld()
        world.instantSnow = true
        world.snowOnWindows = false
        world.ingestWindows([WindowSample(id: 1, frame: window)])
        run(world, seconds: 0.4)

        let moved = window.offsetBy([6, 0])
        world.ingestWindows([WindowSample(id: 1, frame: moved)])
        world.step(dt: 1.0 / 30)
        let cap = world.caps[0]
        let afterMove = cap.mass
        #expect(world.debris.count > 0)

        for _ in 0..<12 { world.step(dt: 1.0 / 30) }
        #expect(cap.mass > afterMove)
    }

    @Test func upwardWindowJerkCanThrowSnow() {
        let world = makeWorld()
        world.instantSnow = true
        world.snowOnWindows = false
        world.ingestWindows([WindowSample(id: 1, frame: window)])
        world.step(dt: 1.0 / 30)
        world.ingestWindows([WindowSample(id: 1, frame: window.offsetBy([0, 20]))])
        world.step(dt: 1.0 / 30)

        #expect(world.debris.count > 0)
        let verticalSpeeds = (0..<world.debris.count).map { world.debris.velocities[$0].y }
        #expect((verticalSpeeds.min() ?? 0) > 350)
        #expect((verticalSpeeds.max() ?? 0) < 550)
    }

    @Test func tinyJitterDoesNotShed() {
        let world = makeWorld()
        world.instantSnow = true
        world.snowOnWindows = false
        world.ingestWindows([WindowSample(id: 1, frame: window)])
        world.step(dt: 1.0 / 30)
        let mass = world.caps[0].mass
        world.ingestWindows([WindowSample(id: 1, frame: window.offsetBy([0.2, 0]))])
        world.step(dt: 1.0 / 30)
        #expect(abs(world.caps[0].mass - mass) < mass * 0.01)
    }

    @Test func movingWindowCollectsNoSnow() {
        let world = makeWorld()
        world.ingestWindows([WindowSample(id: 1, frame: window)])
        var x: Float = 0
        for _ in 0..<(20 * 30) {
            x += 3
            world.ingestWindows([WindowSample(id: 1, frame: window.offsetBy([x.truncatingRemainder(dividingBy: 300), 0]))])
            world.step(dt: 1.0 / 30)
        }
        #expect(world.caps[0].mass < 1)
    }

    @Test func narrowingDropsDebrisFromTheRemovedPart() {
        let world = makeWorld()
        world.instantSnow = true
        world.ingestWindows([WindowSample(id: 1, frame: window)])
        world.step(dt: 1.0 / 30)
        let narrower = Rect(x: window.minX, y: window.minY, width: 400, height: window.height)
        world.ingestWindows([WindowSample(id: 1, frame: narrower)])
        world.step(dt: 1.0 / 30)
        #expect(world.debris.count > 0)
        for i in 0..<world.debris.count {
            #expect(world.debris.sprites[i].x > narrower.maxX - 10)
        }
    }

    @Test func cursorBrushKnocksSnowOff() {
        let world = makeWorld()
        world.instantSnow = true
        world.ingestWindows([WindowSample(id: 1, frame: window)])
        world.step(dt: 1.0 / 30)
        let mass = world.caps[0].mass
        // Sweep the cursor along the cap, 5 pt above the edge, from x=400 to x=600.
        for i in 0...20 {
            world.setCursor([400 + Float(i) * 10, window.maxY + 5])
            world.step(dt: 1.0 / 60)
        }
        #expect(world.caps[0].mass < mass * 0.95)
        #expect(world.debris.count > 0)
    }

    @Test func brushedSnowHopsBrieflyThenFalls() {
        let world = makeWorld()
        world.instantSnow = true
        world.snowOnWindows = false
        world.ingestWindows([WindowSample(id: 1, frame: window)])
        world.step(dt: 1.0 / 30)
        world.setCursor([400, window.maxY + 5])
        world.step(dt: 1.0 / 60)
        world.setCursor([410, window.maxY + 5])
        world.step(dt: 1.0 / 60)

        #expect(world.debris.count > 0)
        let startY = world.debris.sprites[0].y
        for i in 0..<world.debris.count {
            #expect(abs(world.debris.velocities[i].x) < 100)
            #expect(world.debris.velocities[i].y > 40)
            #expect(world.debris.velocities[i].y < 100)
        }
        world.step(dt: 0.05)
        #expect(world.debris.sprites[0].y > startY)
        for _ in 0..<12 { world.step(dt: 1.0 / 30) }
        #expect(world.debris.sprites[0].y < startY)
    }

    @Test func upwardCursorFlickThrowsSnowAboveTheWindow() {
        let world = makeWorld()
        world.instantSnow = true
        world.snowOnWindows = false
        world.ingestWindows([WindowSample(id: 1, frame: window)])
        world.step(dt: 1.0 / 30)
        world.setCursor([500, window.maxY - 20])
        world.step(dt: 1.0 / 60)
        world.setCursor([500, window.maxY + 20])
        world.step(dt: 1.0 / 60)

        #expect(world.debris.count > 0)
        let startY = world.debris.sprites[0].y
        for i in 0..<world.debris.count {
            #expect(world.debris.velocities[i].y > 430)
            #expect(world.debris.velocities[i].y < 480)
        }
        for _ in 0..<6 { world.step(dt: 1.0 / 30) }
        #expect(world.debris.sprites[0].y > startY + 40)
    }

    @Test func quickSidewaysBrushThrowsSnowFurther() {
        let world = makeWorld()
        world.instantSnow = true
        world.snowOnWindows = false
        world.ingestWindows([WindowSample(id: 1, frame: window)])
        world.step(dt: 1.0 / 30)
        world.setCursor([500, window.maxY + 5])
        world.step(dt: 1.0 / 60)
        world.setCursor([520, window.maxY + 5])
        world.step(dt: 1.0 / 60)

        #expect(world.debris.count > 0)
        let meanVX = (0..<world.debris.count).map { world.debris.velocities[$0].x }
            .reduce(0, +) / Float(world.debris.count)
        #expect(meanVX > 90)
        #expect(meanVX < 130)
    }

    @Test func brushedSnowCanLandOnLowerWindow() {
        let world = makeWorld()
        world.instantSnow = true
        world.snowOnWindows = false
        let upper = Rect(x: 300, y: 600, width: 300, height: 200)
        let lower = Rect(x: 100, y: 100, width: 800, height: 300)
        world.ingestWindows([WindowSample(id: 1, frame: upper), WindowSample(id: 2, frame: lower)])
        world.step(dt: 1.0 / 30)
        let lowerCap = world.caps.first { $0.id == 2 }!
        lowerCap.clear()

        for i in 0...20 {
            world.setCursor([350 + Float(i) * 10, upper.maxY + 5])
            world.step(dt: 1.0 / 60)
        }
        for _ in 0..<90 { world.step(dt: 1.0 / 30) }
        #expect(lowerCap.mass > 0)
    }

    @Test func restingCursorDoesNotErode() {
        let world = makeWorld()
        world.instantSnow = true
        world.ingestWindows([WindowSample(id: 1, frame: window)])
        world.setCursor([500, window.maxY + 5])
        world.step(dt: 1.0 / 30)
        let mass = world.caps[0].mass
        for _ in 0..<60 { world.step(dt: 1.0 / 30) }
        #expect(world.caps[0].mass >= mass * 0.98)
    }

    @Test func hiddenWindowDoesNotDropSnowOntoWindowBelow() {
        let world = makeWorld()
        world.instantSnow = true
        world.snowOnWindows = false // only debris may add snow
        let upper = Rect(x: 300, y: 600, width: 300, height: 200)
        let lower = Rect(x: 100, y: 100, width: 800, height: 300)
        world.ingestWindows([WindowSample(id: 1, frame: upper), WindowSample(id: 2, frame: lower)])
        world.step(dt: 1.0 / 30)
        let lowerCap = world.caps.first { $0.id == 2 }!
        lowerCap.clear()
        // A hidden upper window must not shower the lower one during a Space switch.
        for _ in 0..<Config.disappearPolls {
            world.ingestWindows([WindowSample(id: 2, frame: lower)])
        }
        for _ in 0..<(3 * 30) { world.step(dt: 1.0 / 30) }
        #expect(world.debris.count == 0)
        #expect(lowerCap.mass == 0)
    }

    @Test func brushedDebrisCanSettleBackOnItsSource() {
        let world = makeWorld()
        world.instantSnow = true
        world.snowOnWindows = false
        world.ingestWindows([WindowSample(id: 1, frame: window)])
        run(world, seconds: 0.4)
        let cap = world.caps[0]
        // Brushed snow rises briefly, then can settle back on the resting window.
        for i in 0...10 {
            world.setCursor([500 + Float(i) * 5, window.maxY + 5])
            world.step(dt: 1.0 / 60)
        }
        let afterBrush = cap.mass
        for _ in 0..<(3 * 30) { world.step(dt: 1.0 / 30) }
        #expect(cap.mass > afterBrush)
    }

    @Test func dockCollectsSnowAndHidesCapsBehindIt() {
        let world = makeWorld()
        let dock = Rect(x: 200, y: 3, width: 1066, height: 84)
        world.setDock(dock)
        // A window whose top edge sits inside the Dock's band is hidden by the Dock.
        world.ingestWindows([WindowSample(id: 1, frame: Rect(x: 0, y: 0, width: 1512, height: 60))])
        run(world, seconds: 60)
        let dockCap = world.caps.first { $0.id == World.dockCapID }!
        #expect(dockCap.mass > 0)
        #expect(world.caps.last?.id == World.dockCapID) // rendered in front
        let window = world.caps.first { $0.id == 1 }!
        #expect(!Intervals.contains(window.visible, 700))
        #expect(Intervals.contains(window.visible, 100))
    }

    @Test func dockSnowCanBeBrushedOff() {
        let world = makeWorld()
        world.instantSnow = true
        world.setDock(Rect(x: 200, y: 3, width: 1066, height: 84))
        world.step(dt: 1.0 / 30)
        let cap = world.caps.first { $0.id == World.dockCapID }!
        let mass = cap.mass
        for i in 0...30 {
            world.setCursor([500 + Float(i) * 10, Float(87 + 4)])
            world.step(dt: 1.0 / 60)
        }
        #expect(cap.mass < mass * 0.8)
    }

    @Test func hidingTheDockClearsItsSnow() {
        let world = makeWorld()
        world.instantSnow = true
        world.setDock(Rect(x: 200, y: 3, width: 1066, height: 84))
        world.step(dt: 1.0 / 30)
        world.setDock(nil)
        #expect(!world.caps.contains { $0.id == World.dockCapID })
        world.step(dt: 1.0 / 30)
        #expect(world.debris.count == 0)
    }

    @Test func dockToggleOffClearsSnow() {
        let world = makeWorld()
        world.instantSnow = true
        world.setDock(Rect(x: 200, y: 3, width: 1066, height: 84))
        world.step(dt: 1.0 / 30)
        world.snowOnDock = false
        #expect(world.dockFrame == nil)
        #expect(!world.caps.contains { $0.id == World.dockCapID })
        world.setDock(Rect(x: 200, y: 3, width: 1066, height: 84))
        #expect(world.dockFrame == nil)
        world.step(dt: 1.0 / 30)
        #expect(world.debris.count == 0)
    }

    @Test func fullscreenWindowLosesItsSnow() {
        let world = makeWorld()
        world.instantSnow = true
        world.ingestWindows([WindowSample(id: 1, frame: window)])
        world.step(dt: 1.0 / 30)
        #expect(world.caps[0].mass > 0)

        world.setFullscreenWindows([1])
        #expect(world.caps[0].mass == 0)
        run(world, seconds: 2)
        #expect(world.caps[0].mass == 0)
        #expect(world.debris.count == 0)
    }

    @Test func fullscreenWindowKeepsFlakesButOccludesSnowBehindIt() {
        let world = makeWorld()
        world.instantSnow = true
        let fullscreen = WindowSample(id: 1, frame: screen)
        let behind = WindowSample(id: 2, frame: window)
        world.ingestWindows([fullscreen, behind])
        world.setFullscreenWindows([1])
        world.step(dt: 1.0 / 30)

        #expect(world.flakes.count > 0)
        #expect(world.caps.first { $0.id == 1 }?.visible.isEmpty == true)
        #expect(world.caps.first { $0.id == 2 }?.visible.isEmpty == true)
    }

    @Test func fullscreenCoverageAcceptsOversizedWindowButNotMaximizedWindow() {
        let oversized = Rect(x: -3, y: -4, width: 1518, height: 990)
        let maximized = Rect(x: 0, y: 90, width: 1512, height: 859)
        #expect(FullscreenCoverage.covers(oversized, screen: screen))
        #expect(!FullscreenCoverage.covers(maximized, screen: screen))
    }

    @Test func screenCoveringWindowBelowMenuBarIsFullscreen() {
        let display = Rect(x: 0, y: 0, width: 1470, height: 956)
        let visible = Rect(x: 0, y: 90, width: 1470, height: 833)
        // Captured from CGWindowList: y=33, height=923 in top-left coordinates.
        let window = Rect(x: 0, y: 0, width: 1470, height: 923)
        #expect(FullscreenCoverage.covers(window, screen: display, visible: visible))
    }

    @Test func settingsAreClampedAndApplied() {
        let world = makeWorld()
        world.instantSnow = true
        world.ingestWindows([WindowSample(id: 1, frame: window)])
        world.maxDriftHeight = 100
        #expect(world.maxDriftHeight == Config.capMaxHeightRange.upperBound)
        world.maxDriftHeight = 7
        #expect(world.caps[0].maxHeight == 7)
        world.windScale = -3
        #expect(world.windScale == 0)
        world.step(dt: 1.0 / 30)
        #expect(world.wind == 0)
    }

    @Test func clearSnowRemovesEverything() {
        let world = makeWorld()
        world.instantSnow = true
        world.ingestWindows([WindowSample(id: 1, frame: window)])
        world.setDock(Rect(x: 200, y: 3, width: 1066, height: 84))
        world.step(dt: 1.0 / 30)
        world.clearSnow()
        #expect(world.caps.allSatisfy { $0.mass == 0 })
        #expect(world.debris.count == 0)
    }

    @Test func debrisIsBoundedAndDies() {
        var rng = SplitMix64(seed: 1)
        var pool = DebrisPool(capacity: 100)
        pool.spawn(SnowSpill(position: [0, 500], mass: 10_000), rng: &rng)
        #expect(pool.count == 100)
        for _ in 0..<(10 * 30) { pool.step(dt: 1.0 / 30, floor: 0) { _, _, _, _ in false } }
        #expect(pool.count == 0)
    }

    @Test func debrisFallsUnderGravity() {
        var rng = SplitMix64(seed: 2)
        var pool = DebrisPool()
        pool.spawn(SnowSpill(position: [0, 500], mass: Config.debrisParticleMass), rng: &rng)
        #expect(pool.count == 1)
        let y0 = pool.sprites[0].y
        for _ in 0..<15 { pool.step(dt: 1.0 / 30, floor: -1000) { _, _, _, _ in false } }
        #expect(pool.sprites[0].y < y0 - 50)
        #expect(pool.sprites[0].y > y0 - 85)
        #expect(pool.velocities[0].y < -200)
    }

    @Test func spawnConservesMassOnAverage() {
        var rng = SplitMix64(seed: 3)
        var pool = DebrisPool()
        var total: Float = 0
        for _ in 0..<1000 {
            pool.spawn(SnowSpill(position: .zero, mass: 1.3), rng: &rng)
            total += 1.3
        }
        #expect(abs(pool.totalMass - total) < total * 0.1)
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

    @Test func goneWindowRetainsItsSnowWithoutSpilling() {
        let world = makeWorld()
        world.instantSnow = true
        world.ingestWindows([WindowSample(id: 1, frame: window)])
        world.step(dt: 1.0 / 30)
        for _ in 0..<Config.disappearPolls { world.ingestWindows([]) }
        #expect(world.caps.isEmpty)
        #expect(world.spills.isEmpty)
    }

    @Test func switchingAwayAndBackKeepsWindowSnowQuiet() {
        let world = makeWorld()
        world.instantSnow = true
        let sample = WindowSample(id: 1, frame: window)
        world.ingestWindows([sample])
        world.step(dt: 1.0 / 30)
        let mass = world.caps[0].mass
        for _ in 0..<Config.disappearPolls { world.ingestWindows([]) }
        world.step(dt: 1.0 / 30)
        #expect(world.debris.count == 0)
        world.ingestWindows([sample])
        world.step(dt: 1.0 / 30)
        #expect(world.caps[0].mass >= mass * 0.98)
    }

    @Test func screenEdgeCollectsSnowAndPlowClearsIt() {
        let world = makeWorld()
        world.intensity = .light
        world.bottomSurface = .screen
        world.snowOnWindows = false
        world.instantSnow = true
        world.setScreens([])
        world.setScreens([screen])
        let edge = world.caps.first { $0.id == World.screenCapID }
        #expect(edge != nil)
        #expect(edge?.mass ?? 0 > 0)
        world.step(dt: 1.0 / 30)
        #expect(world.plows.count == 1)
        let before = edge?.mass ?? 0
        let initialX = world.plows[0].x
        for _ in 0..<90 { world.step(dt: 1.0 / 30) }
        #expect(abs(world.plows[0].x - (initialX - Config.plowSpeed * 3)) < 1)
        #expect((edge?.heights.max() ?? 0) <= world.maxDriftHeight * 1.5)
        #expect((edge?.mass ?? 0) < before * 0.95)
        #expect(world.plows[0].dischargedSnow > 0)
        for _ in 0..<1080 { world.step(dt: 1.0 / 30) }
        #expect((edge?.mass ?? 0) < before * 0.5)
    }

    @Test func plowClearsSnowWithoutBuildingATallWall() {
        let world = World(seed: 42)
        world.bottomSurface = .screen
        world.instantSnow = true
        world.setScreens([screen])
        world.step(dt: 1 / 30)
        let cap = world.caps.first { $0.id == World.screenCapID }!
        let initialMass = cap.mass
        for _ in 0..<300 { world.step(dt: 1 / 30) }
        #expect((cap.heights.max() ?? 0) < world.maxDriftHeight * 1.5)
        #expect(cap.mass < initialMass * 0.85)
        #expect(world.plows[0].dischargedSnow > initialMass * 0.2)
    }

    @Test func disablingPlowStopsItWithoutErasingSnow() {
        let world = makeWorld()
        world.bottomSurface = .screen
        world.instantSnow = true
        world.setScreens([])
        world.setScreens([screen])
        world.step(dt: 1 / 30)
        #expect(world.plows.count == 1)
        let cap = world.caps.first { $0.id == World.screenCapID }!
        let before = cap.mass
        world.snowplowEnabled = false
        #expect(world.plows.isEmpty)
        #expect(cap.mass == before)
        for _ in 0..<30 { world.step(dt: 1 / 30) }
        #expect(world.plows.isEmpty)
        world.snowplowEnabled = true
        world.step(dt: 1 / 30)
        #expect(world.plows.count == 1)
    }

    @Test func screenEdgeCollectsFallingFlakesWithoutWindows() {
        let world = makeWorld()
        world.bottomSurface = .screen
        world.snowOnWindows = false
        run(world, seconds: 30)
        #expect(world.caps.first { $0.id == World.screenCapID }?.mass ?? 0 > 0)
    }

    @Test func bottomSurfaceSwitchesBetweenDockAndScreen() {
        let world = makeWorld()
        world.setDock(Rect(x: 200, y: 3, width: 1066, height: 84))
        #expect(world.caps.contains { $0.id == World.dockCapID })
        world.bottomSurface = .screen
        #expect(world.caps.contains { $0.id == World.screenCapID })
        #expect(!world.caps.contains { $0.id == World.dockCapID })
        world.bottomSurface = .dock
        #expect(world.caps.contains { $0.id == World.dockCapID })
    }

    @Test func returnedWindowWithNewFrameDoesNotDropSnow() {
        let world = makeWorld()
        world.instantSnow = true
        world.ingestWindows([WindowSample(id: 1, frame: window)])
        world.step(dt: 1.0 / 30)
        for _ in 0..<Config.disappearPolls { world.ingestWindows([]) }
        let relocated = Rect(x: 400, y: 300, width: 600, height: 500)
        world.ingestWindows([WindowSample(id: 1, frame: relocated)])
        world.step(dt: 1.0 / 30)
        #expect(world.debris.count == 0)
        #expect(world.caps[0].frame == relocated)
        #expect(world.caps[0].mass > 0)
    }

    @Test func fullscreenScreenHidesItsEdgeSnow() {
        let world = makeWorld()
        world.bottomSurface = .screen
        world.ingestWindows([WindowSample(id: 1, frame: screen)])
        world.setFullscreenWindows([1])
        world.step(dt: 1.0 / 30)
        #expect(world.caps.first { $0.id == World.screenCapID }?.isPresent == false)
        world.setFullscreenWindows([])
        #expect(world.caps.first { $0.id == World.screenCapID }?.isPresent == true)
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
