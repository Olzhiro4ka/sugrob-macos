import Testing
@testable import SnowCore

struct DockLayoutTests {
    private let screen = Rect(x: 0, y: 0, width: 1470, height: 956)
    private let visible = Rect(x: 0, y: 90, width: 1470, height: 833)

    /// The configuration measured with AX on macOS 26: 12 pinned apps, 1 folder, recents on,
    /// nothing extra running. AX reported x = 202, width = 1066, height = 84.
    private var measured: DockPreferences {
        var preferences = DockPreferences()
        preferences.tileSize = 64
        preferences.persistentApps = (0..<12).map { .app(bundleID: "app.\($0)") }
        preferences.persistentOthers = 1
        preferences.showRecents = true
        return preferences
    }

    @Test func matchesMeasuredDock() {
        let frame = DockLayout.frame(screen: screen, visible: visible, preferences: measured,
                                     runningRegularApps: ["app.1", "app.2", DockLayout.finderBundleID])!
        #expect(abs(frame.width - 1066) < 1)
        #expect(abs(frame.minX - 202) < 1)
        #expect(frame.height == 84)
        #expect(frame.maxY == 87)
    }

    @Test func runningUnpinnedAppsWidenTheDock() {
        let base = DockLayout.tileCounts(preferences: measured, runningRegularApps: [])
        let more = DockLayout.tileCounts(preferences: measured, runningRegularApps: ["x.y", "app.3"])
        #expect(more.tiles == base.tiles + 1)
        #expect(more.separators == base.separators + 1) // recents section appears
    }

    @Test func recentsOffMeansNoExtraSeparator() {
        var preferences = measured
        preferences.showRecents = false
        preferences.recentApps = ["r.1", "r.2"]
        let counts = DockLayout.tileCounts(preferences: preferences, runningRegularApps: ["x.y"])
        #expect(counts.separators == 1)
        #expect(counts.tiles == 1 + 12 + 1 + 1 + 1) // Finder, pinned, running x.y, folder, Trash
    }

    @Test func spacersCount() {
        var preferences = DockPreferences()
        preferences.persistentApps = [.spacer, .smallSpacer]
        #expect(DockLayout.tileCounts(preferences: preferences, runningRegularApps: []).tiles == 1 + 1.5 + 1)
    }

    @Test func hiddenOrSideDockHasNoSurface() {
        var preferences = measured
        preferences.autohide = true
        #expect(DockLayout.frame(screen: screen, visible: visible, preferences: preferences, runningRegularApps: []) == nil)
        preferences.autohide = false
        preferences.orientation = "left"
        #expect(DockLayout.frame(screen: screen, visible: visible, preferences: preferences, runningRegularApps: []) == nil)
    }

    @Test func screenWithoutBottomInsetHasNoDock() {
        let full = Rect(x: 0, y: 0, width: 1470, height: 923)
        #expect(DockLayout.frame(screen: screen, visible: full, preferences: measured, runningRegularApps: []) == nil)
    }

    @Test func secondaryScreenDockIsCenteredThere() {
        let external = Rect(x: 1470, y: -200, width: 2560, height: 1440)
        let externalVisible = Rect(x: 1470, y: -110, width: 2560, height: 1317)
        let frame = DockLayout.frame(screen: external, visible: externalVisible, preferences: measured,
                                     runningRegularApps: [])!
        #expect(abs(frame.midX - external.midX) < 0.01)
        #expect(frame.maxY == -113)
    }
}
