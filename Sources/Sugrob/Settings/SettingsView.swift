import ServiceManagement
import SnowCore
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Snow") {
                Picker("Intensity", selection: $settings.intensity) {
                    ForEach(Intensity.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                LabeledContent("Max drift height") {
                    HStack {
                        Slider(value: $settings.maxDriftHeight,
                               in: Double(Config.capMaxHeightRange.lowerBound)...Double(Config.capMaxHeightRange.upperBound),
                               step: 1)
                        Text("\(Int(settings.maxDriftHeight)) pt")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }

                LabeledContent("Wind") {
                    HStack {
                        Slider(value: $settings.windStrength,
                               in: Double(Config.windScaleRange.lowerBound)...Double(Config.windScaleRange.upperBound))
                        Text(settings.windStrength < 0.05 ? "Calm" : String(format: "%.1f×", settings.windStrength))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }

                Toggle("Snow on windows", isOn: $settings.snowOnWindows)
                Picker("Bottom snow", selection: $settings.bottomSurface) {
                    Text("Dock").tag(BottomSurface.dock)
                    Text("Screen edge").tag(BottomSurface.screen)
                }
                Toggle("Snowplow", isOn: $settings.snowplowEnabled)
                    .disabled(settings.bottomSurface != .screen)
            }

            Section("Performance") {
                Picker("Frame rate", selection: $settings.frameRate) {
                    ForEach(FrameRateMode.allCases) { Text($0.title).tag($0) }
                }
                Text(settings.frameRate.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Pause on battery power", isOn: $settings.pauseOnBattery)
            }

            Section("System") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Toggle("Precise Dock detection", isOn: $settings.preciseDock)
                    .onChange(of: settings.preciseDock) { _, enabled in
                        if enabled { DockLocator.requestAccessibility() }
                    }
                Text("Measures the Dock with Accessibility. Off by default; macOS asks for permission when you turn it on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("Sugrob never uses the network and needs no permissions in its default configuration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Version \(Self.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// Hosts `SettingsView` in a regular window. The window is torn down on close so SwiftUI's
/// memory is returned while it's not shown.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let settings: SettingsStore
    private var window: NSWindow?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(settings: settings))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Sugrob Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil
        window = nil
    }
}
