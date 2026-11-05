import AppKit

/// Owns the menu bar snowflake and its menu.
@MainActor
final class StatusItemController: NSObject {
    private let settings: SettingsStore
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let toggleItem = NSMenuItem(title: "Snow", action: #selector(toggleSnow), keyEquivalent: "")
    /// Called with the new enabled state after the user toggles snow.
    var onToggle: ((Bool) -> Void)?

    init(settings: SettingsStore) {
        self.settings = settings
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "snowflake", accessibilityDescription: "Sugrob")
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Sugrob", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        statusItem.menu = menu

        refresh()
    }

    @objc private func toggleSnow() {
        settings.isSnowEnabled.toggle()
        refresh()
        onToggle?(settings.isSnowEnabled)
    }

    private func refresh() {
        toggleItem.state = settings.isSnowEnabled ? .on : .off
        // A dimmed snowflake signals "off" without needing a second symbol.
        statusItem.button?.appearsDisabled = !settings.isSnowEnabled
    }
}
