import Foundation

/// User preferences backed by `UserDefaults`. Grows into the full settings model in a later phase.
@MainActor
final class SettingsStore {
    private enum Key {
        static let snowEnabled = "snowEnabled"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.snowEnabled: true])
    }

    var isSnowEnabled: Bool {
        get { defaults.bool(forKey: Key.snowEnabled) }
        set { defaults.set(newValue, forKey: Key.snowEnabled) }
    }
}
