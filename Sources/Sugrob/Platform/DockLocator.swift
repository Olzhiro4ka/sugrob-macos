import AppKit
import ApplicationServices
import SnowCore

/// Finds the Dock's frame.
///
/// Default mode needs no permission: the Dock's band comes from `frame` vs. `visibleFrame`, and
/// its width from `com.apple.dock` preferences plus running apps (`SnowCore.DockLayout`).
/// The opt-in precise mode additionally asks Accessibility for the Dock list's horizontal
/// extent. It only ever prompts when the user explicitly turns it on. (On macOS 26 the AX
/// y-coordinate of the Dock is reported off-screen, so the vertical position always comes from
/// `visibleFrame`.)
@MainActor
final class DockLocator {
    private static let domain = "com.apple.dock" as CFString

    var onChange: ((Rect?) -> Void)?
    private(set) var frame: Rect?
    /// Last AX-measured horizontal extent, for comparing against the estimate in debug output.
    private(set) var preciseExtent: (minX: Float, width: Float)?
    private let verbose: Bool
    private var timer: Timer?

    var preciseMode = false {
        didSet {
            guard preciseMode != oldValue else { return }
            if preciseMode { Self.requestAccessibility() }
            refresh()
        }
    }

    init(verbose: Bool) {
        self.verbose = verbose
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appsChanged),
                           name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appsChanged),
                           name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appsChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // Catches preference changes (tile size, orientation, auto-hide) that post no notification.
        let timer = Timer(timeInterval: Config.dockRefreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func appsChanged() {
        // The Dock animates new tiles in; measure after it settles.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        let preferences = Self.readPreferences()
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.bundleIdentifier)
        var estimate: Rect?
        for screen in NSScreen.screens {
            if let found = DockLayout.frame(screen: CoordinateSpace.core(screen.frame),
                                            visible: CoordinateSpace.core(screen.visibleFrame),
                                            preferences: preferences, runningRegularApps: running) {
                estimate = found
                break
            }
        }

        preciseExtent = preciseMode ? Self.measureHorizontalExtent() : nil
        var result = estimate
        if var adjusted = estimate, let extent = preciseExtent {
            adjusted.minX = extent.minX
            adjusted.width = extent.width
            result = adjusted
        }

        guard result != frame else { return }
        frame = result
        if verbose { log(estimate: estimate, preferences: preferences) }
        onChange?(result)
    }

    // MARK: Preferences

    private static func value(_ key: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, domain)
    }

    static func readPreferences() -> DockPreferences {
        CFPreferencesAppSynchronize(domain)
        var preferences = DockPreferences()
        if let orientation = value("orientation") as? String { preferences.orientation = orientation }
        if let autohide = value("autohide") as? Bool { preferences.autohide = autohide }
        if let tileSize = value("tilesize") as? NSNumber { preferences.tileSize = tileSize.floatValue }
        if let showRecents = value("show-recents") as? Bool { preferences.showRecents = showRecents }
        if let apps = value("persistent-apps") as? [[String: Any]] {
            preferences.persistentApps = apps.compactMap { tile in
                switch tile["tile-type"] as? String {
                case "spacer-tile": return .spacer
                case "small-spacer-tile": return .smallSpacer
                default:
                    let data = tile["tile-data"] as? [String: Any]
                    return .app(bundleID: data?["bundle-identifier"] as? String ?? "")
                }
            }
        }
        if let others = value("persistent-others") as? [Any] { preferences.persistentOthers = others.count }
        if let recents = value("recent-apps") as? [[String: Any]] {
            preferences.recentApps = recents.compactMap {
                ($0["tile-data"] as? [String: Any])?["bundle-identifier"] as? String
            }
        }
        return preferences
    }

    // MARK: Accessibility (opt-in only)

    private static func requestAccessibility() {
        // String literal instead of `kAXTrustedCheckOptionPrompt` (a mutable global in Swift 6).
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Horizontal extent of the Dock's list element, or nil without permission.
    private static func measureHorizontalExtent() -> (minX: Float, width: Float)? {
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return nil }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &children) == .success,
              let list = (children as? [AXUIElement])?.first
        else { return nil }
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(list, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(list, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size,
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        // Type IDs were checked above, so these casts cannot fail.
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &extent),
              extent.width > 0
        else { return nil }
        return (Float(point.x), Float(extent.width))
    }

    private func log(estimate: Rect?, preferences: DockPreferences) {
        var line = "[dock] tilesize \(preferences.tileSize) orientation \(preferences.orientation) autohide \(preferences.autohide)"
        if let estimate {
            line += String(format: " · estimate x %.1f y %.1f w %.1f h %.1f", estimate.minX, estimate.minY, estimate.width, estimate.height)
        } else {
            line += " · no Dock surface"
        }
        if let extent = preciseExtent {
            line += String(format: " · AX x %.1f w %.1f", extent.minX, extent.width)
        }
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
