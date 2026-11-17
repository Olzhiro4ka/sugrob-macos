import Foundation
import Observation
import SnowCore

/// How the render rate adapts.
enum FrameRateMode: String, CaseIterable, Identifiable {
    /// 30 fps idle, 60 fps while something moves fast.
    case balanced
    /// 60 fps all the time: smoothest, roughly twice the CPU.
    case smooth
    /// Never above 30 fps.
    case efficient

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced: "Balanced"
        case .smooth: "Smooth"
        case .efficient: "Efficient"
        }
    }

    var detail: String {
        switch self {
        case .balanced: "30 fps at rest, 60 fps while snow is flying."
        case .smooth: "Always 60 fps. Smoothest, about twice the CPU."
        case .efficient: "Never above 30 fps. Lowest CPU."
        }
    }

    func fps(active: Bool) -> Int {
        switch self {
        case .balanced: active ? Config.activeFPS : Config.idleFPS
        case .smooth: Config.activeFPS
        case .efficient: Config.idleFPS
        }
    }
}

extension Intensity {
    var title: String {
        switch self {
        case .light: "Light"
        case .medium: "Medium"
        case .blizzard: "Blizzard"
        }
    }
}

/// User preferences backed by `UserDefaults`, observable by SwiftUI and applied live through
/// `onChange`. Launch at login is not stored here: `SMAppService` is the source of truth.
@MainActor
@Observable
final class SettingsStore {
    private enum Key {
        static let snowEnabled = "snowEnabled"
        static let settlingEnabled = "settlingEnabled"
        static let intensity = "intensity"
        static let snowOnWindows = "snowOnWindows"
        static let snowOnDock = "snowOnDock"
        static let bottomSurface = "bottomSurface"
        static let snowplowEnabled = "snowplowEnabled"
        static let maxDriftHeight = "maxDriftHeight"
        static let windStrength = "windStrength"
        static let frameRate = "frameRate"
        static let pauseOnBattery = "pauseOnBattery"
        static let preciseDock = "preciseDock"
    }

    @ObservationIgnored private let defaults: UserDefaults
    /// Called after any setting changes.
    @ObservationIgnored var onChange: (() -> Void)?

    var isSnowEnabled: Bool { didSet { save(isSnowEnabled, Key.snowEnabled) } }
    var settlingEnabled: Bool { didSet { save(settlingEnabled, Key.settlingEnabled) } }
    var intensity: Intensity { didSet { save(intensity.rawValue, Key.intensity) } }
    var snowOnWindows: Bool { didSet { save(snowOnWindows, Key.snowOnWindows) } }
    var snowOnDock: Bool { didSet { save(snowOnDock, Key.snowOnDock) } }
    var bottomSurface: BottomSurface { didSet { save(bottomSurface.rawValue, Key.bottomSurface) } }
    var snowplowEnabled: Bool { didSet { save(snowplowEnabled, Key.snowplowEnabled) } }
    /// Points, within `Config.capMaxHeightRange`.
    var maxDriftHeight: Double { didSet { save(maxDriftHeight, Key.maxDriftHeight) } }
    /// Multiplier, within `Config.windScaleRange`.
    var windStrength: Double { didSet { save(windStrength, Key.windStrength) } }
    var frameRate: FrameRateMode { didSet { save(frameRate.rawValue, Key.frameRate) } }
    var pauseOnBattery: Bool { didSet { save(pauseOnBattery, Key.pauseOnBattery) } }
    /// Opt-in Accessibility measurement of the Dock.
    var preciseDock: Bool { didSet { save(preciseDock, Key.preciseDock) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.snowEnabled: true,
            Key.settlingEnabled: true,
            Key.intensity: Intensity.medium.rawValue,
            Key.snowOnWindows: true,
            Key.snowOnDock: true,
            Key.bottomSurface: BottomSurface.dock.rawValue,
            Key.snowplowEnabled: true,
            Key.maxDriftHeight: Double(Config.capMaxHeight),
            Key.windStrength: 1.0,
            Key.frameRate: FrameRateMode.balanced.rawValue,
            Key.pauseOnBattery: false,
            Key.preciseDock: false,
        ])
        isSnowEnabled = defaults.bool(forKey: Key.snowEnabled)
        settlingEnabled = defaults.bool(forKey: Key.settlingEnabled)
        intensity = Intensity(rawValue: defaults.string(forKey: Key.intensity) ?? "") ?? .medium
        snowOnWindows = defaults.bool(forKey: Key.snowOnWindows)
        snowOnDock = defaults.bool(forKey: Key.snowOnDock)
        bottomSurface = BottomSurface(rawValue: defaults.string(forKey: Key.bottomSurface) ?? "") ?? .dock
        snowplowEnabled = defaults.bool(forKey: Key.snowplowEnabled)
        maxDriftHeight = defaults.double(forKey: Key.maxDriftHeight)
        windStrength = defaults.double(forKey: Key.windStrength)
        frameRate = FrameRateMode(rawValue: defaults.string(forKey: Key.frameRate) ?? "") ?? .balanced
        pauseOnBattery = defaults.bool(forKey: Key.pauseOnBattery)
        preciseDock = defaults.bool(forKey: Key.preciseDock)
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        onChange?()
    }
}
