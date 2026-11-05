import AppKit
import SnowCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options = LaunchOptions(arguments: CommandLine.arguments)
    private let settings = SettingsStore()
    private var statusItem: StatusItemController?
    private var engine: SnowEngine?

    func applicationDidFinishLaunching(_ notification: Notification) {
        engine = SnowEngine(options: options)
        if engine == nil {
            NSLog("Sugrob: Metal is unavailable; running without snow.")
        }
        engine?.setPaused(.userDisabled, !settings.isSnowEnabled)

        statusItem = StatusItemController(settings: settings)
        statusItem?.onToggle = { [weak self] enabled in
            self?.engine?.setPaused(.userDisabled, !enabled)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine?.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
