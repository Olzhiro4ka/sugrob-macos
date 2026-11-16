import AppKit

/// Reasons the snow is fully paused. Any active reason stops the tick and hides the overlays.
enum PauseReason: Hashable {
    case userDisabled
    case screenLocked
    case screensaver
    case systemAsleep
    case displaysAsleep
    case sessionInactive
    case poweringOff
    /// "Pause on battery power" is on and the Mac runs on battery.
    case onBattery
    /// Mission Control / App Exposé is showing (and a short grace period after it closes).
    case missionControl
}

/// Watches lock, sleep, screensaver, fast user switching and shutdown via public notifications.
@MainActor
final class SessionMonitor {
    var onChange: ((PauseReason, Bool) -> Void)?
    /// Called when the active Space changes (windows jump; worth an immediate window poll).
    var onSpaceChange: (() -> Void)?

    init() {
        let distributed = DistributedNotificationCenter.default()
        let distributedEvents: [(String, Selector)] = [
            ("com.apple.screenIsLocked", #selector(screenLocked)),
            ("com.apple.screenIsUnlocked", #selector(screenUnlocked)),
            ("com.apple.screensaver.didstart", #selector(screensaverStarted)),
            ("com.apple.screensaver.didstop", #selector(screensaverStopped)),
        ]
        for (name, selector) in distributedEvents {
            // Accessory apps are "inactive"; without .deliverImmediately these get coalesced.
            distributed.addObserver(self, selector: selector, name: Notification.Name(name),
                                    object: nil, suspensionBehavior: .deliverImmediately)
        }

        let workspace = NSWorkspace.shared.notificationCenter
        let workspaceEvents: [(Notification.Name, Selector)] = [
            (NSWorkspace.willSleepNotification, #selector(willSleep)),
            (NSWorkspace.didWakeNotification, #selector(didWake)),
            (NSWorkspace.screensDidSleepNotification, #selector(screensDidSleep)),
            (NSWorkspace.screensDidWakeNotification, #selector(screensDidWake)),
            (NSWorkspace.sessionDidResignActiveNotification, #selector(sessionResigned)),
            (NSWorkspace.sessionDidBecomeActiveNotification, #selector(sessionBecameActive)),
            (NSWorkspace.willPowerOffNotification, #selector(willPowerOff)),
            (NSWorkspace.activeSpaceDidChangeNotification, #selector(spaceChanged)),
        ]
        for (name, selector) in workspaceEvents {
            workspace.addObserver(self, selector: selector, name: name, object: nil)
        }
    }

    @objc private func screenLocked() { onChange?(.screenLocked, true) }
    @objc private func screenUnlocked() { onChange?(.screenLocked, false) }
    @objc private func screensaverStarted() { onChange?(.screensaver, true) }
    @objc private func screensaverStopped() { onChange?(.screensaver, false) }
    @objc private func willSleep() { onChange?(.systemAsleep, true) }
    @objc private func didWake() { onChange?(.systemAsleep, false) }
    @objc private func screensDidSleep() { onChange?(.displaysAsleep, true) }
    @objc private func screensDidWake() { onChange?(.displaysAsleep, false) }
    @objc private func sessionResigned() { onChange?(.sessionInactive, true) }
    @objc private func sessionBecameActive() { onChange?(.sessionInactive, false) }
    @objc private func willPowerOff() { onChange?(.poweringOff, true) }
    @objc private func spaceChanged() { onSpaceChange?() }
}
