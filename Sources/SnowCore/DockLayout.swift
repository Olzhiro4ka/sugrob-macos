/// Dock preferences as read from the `com.apple.dock` domain.
public struct DockPreferences: Equatable, Sendable {
    public enum Tile: Equatable, Sendable {
        case app(bundleID: String)
        case spacer
        case smallSpacer
    }

    public var orientation = "bottom"
    public var autohide = false
    /// `tilesize` (pt). macOS default is 48 when the key is absent.
    public var tileSize: Float = 48
    public var persistentApps: [Tile] = []
    /// Folders and stacks to the right of the separator.
    public var persistentOthers = 0
    public var showRecents = true
    public var recentApps: [String] = []

    public init() {}
}

/// Estimates the Dock's frame from public information only: the screen's `frame` vs.
/// `visibleFrame` (where the Dock reserves space) plus the tile counts from its preferences.
public enum DockLayout {
    public static let finderBundleID = "com.apple.finder"

    /// Number of tile-sized slots and separators the Dock shows.
    public static func tileCounts(preferences: DockPreferences, runningRegularApps: [String]) -> (tiles: Float, separators: Int) {
        var tiles: Float = 1 // Finder is always first and never listed in persistent-apps.
        var pinned = Set<String>([finderBundleID])
        for tile in preferences.persistentApps {
            switch tile {
            case .app(let bundleID):
                tiles += 1
                pinned.insert(bundleID)
            case .spacer:
                tiles += 1
            case .smallSpacer:
                tiles += 0.5
            }
        }
        // Running apps that aren't pinned, plus recent apps when that section is enabled.
        var extras = Set(runningRegularApps.filter { !pinned.contains($0) })
        if preferences.showRecents {
            extras.formUnion(preferences.recentApps.filter { !pinned.contains($0) })
        }
        tiles += Float(extras.count)
        var separators = 1 // before folders and the Trash
        if preferences.showRecents && !extras.isEmpty { separators += 1 }
        tiles += Float(preferences.persistentOthers) + 1 // + Trash
        return (tiles, separators)
    }

    /// The Dock's frame (AppKit global points) on a screen, or nil when it doesn't sit at the
    /// bottom of that screen (other orientation, auto-hidden, or on another display).
    public static func frame(screen: Rect, visible: Rect, preferences: DockPreferences,
                             runningRegularApps: [String]) -> Rect? {
        guard preferences.orientation == "bottom", !preferences.autohide else { return nil }
        let inset = visible.minY - screen.minY
        guard inset > 8 else { return nil }
        let counts = tileCounts(preferences: preferences, runningRegularApps: runningRegularApps)
        let tile = preferences.tileSize
        let width = 2 * Config.dockEndPadding + counts.tiles * (tile + Config.dockTileExtra)
            + Float(counts.separators) * tile * Config.dockSeparatorFactor
        let height = min(tile + Config.dockHeightExtra, inset)
        let top = visible.minY - min(Config.dockTopGap, max(inset - height, 0))
        let clampedWidth = min(width, screen.width)
        return Rect(x: screen.minX + (screen.width - clampedWidth) / 2, y: top - height,
                    width: clampedWidth, height: height)
    }
}
