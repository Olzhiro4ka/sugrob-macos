import AppKit
import SnowCore

/// Owns the menu bar snowflake and its menu. The menu is rebuilt each time it opens, so it
/// always reflects the current settings.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let settings: SettingsStore
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    var onClearSnow: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    init(settings: SettingsStore) {
        self.settings = settings
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "snowflake", accessibilityDescription: "Sugrob")
            image?.isTemplate = true
            button.image = image
        }
        menu.delegate = self
        statusItem.menu = menu
        refreshIcon()
    }

    func refreshIcon() {
        // A dimmed snowflake signals "off" without needing a second symbol.
        statusItem.button?.appearsDisabled = !settings.isSnowEnabled
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(item("Snow", #selector(toggleSnow), on: settings.isSnowEnabled))
        menu.addItem(item("Snow Accumulation", #selector(toggleAccumulation), on: settings.settlingEnabled))

        let intensity = NSMenuItem(title: "Intensity", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for level in Intensity.allCases {
            let entry = item(level.title, #selector(chooseIntensity(_:)), on: settings.intensity == level)
            entry.representedObject = level.rawValue
            submenu.addItem(entry)
        }
        intensity.submenu = submenu
        menu.addItem(intensity)

        let windows = item("Snow on Windows", #selector(toggleWindows), on: settings.snowOnWindows)
        windows.isEnabled = settings.settlingEnabled
        menu.addItem(windows)
        let bottom = NSMenuItem(title: "Bottom Snow", action: nil, keyEquivalent: "")
        let bottomMenu = NSMenu()
        bottomMenu.addItem(item("Dock", #selector(chooseDock), on: settings.bottomSurface == .dock))
        bottomMenu.addItem(item("Screen Edge", #selector(chooseScreen), on: settings.bottomSurface == .screen))
        bottom.submenu = bottomMenu
        bottom.isEnabled = settings.settlingEnabled
        menu.addItem(bottom)
        let plow = item("Snowplow", #selector(toggleSnowplow), on: settings.snowplowEnabled)
        plow.isEnabled = settings.settlingEnabled && settings.bottomSurface == .screen
        menu.addItem(plow)
        menu.addItem(.separator())
        menu.addItem(item("Clear All Snow", #selector(clearSnow)))
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Sugrob", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: Selector, on: Bool? = nil, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        if let on { entry.state = on ? .on : .off }
        return entry
    }

    @objc private func toggleSnow() {
        settings.isSnowEnabled.toggle()
        refreshIcon()
    }

    @objc private func chooseIntensity(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let level = Intensity(rawValue: raw) {
            settings.intensity = level
        }
    }

    @objc private func toggleSnowplow() { settings.snowplowEnabled.toggle() }
    @objc private func toggleAccumulation() { settings.settlingEnabled.toggle() }
    @objc private func toggleWindows() { settings.snowOnWindows.toggle() }
    @objc private func chooseDock() { settings.bottomSurface = .dock }
    @objc private func chooseScreen() { settings.bottomSurface = .screen }
    @objc private func clearSnow() { onClearSnow?() }
    @objc private func openSettings() { onOpenSettings?() }
}
