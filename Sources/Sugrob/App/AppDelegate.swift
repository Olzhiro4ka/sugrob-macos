import AppKit
import SnowCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options = LaunchOptions(arguments: CommandLine.arguments)
    private let settings = SettingsStore()
    private var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindowController?
    private var engine: SnowEngine?

    func applicationDidFinishLaunching(_ notification: Notification) {
        engine = SnowEngine(options: options, settings: settings)
        if engine == nil {
            NSLog("Sugrob: Metal is unavailable; running without snow.")
        }

        let statusItem = StatusItemController(settings: settings)
        let settingsWindow = SettingsWindowController(settings: settings)
        statusItem.onClearSnow = { [weak self] in self?.engine?.clearSnow() }
        statusItem.onOpenSettings = { settingsWindow.show() }
        settings.onChange = { [weak self] in
            self?.engine?.apply(self?.settings)
            self?.statusItem?.refreshIcon()
        }
        self.statusItem = statusItem
        self.settingsWindow = settingsWindow
        if options.openSettings { settingsWindow.show() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine?.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
