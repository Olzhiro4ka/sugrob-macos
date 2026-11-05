import Foundation
import IOKit.ps

/// Reports whether the Mac runs on battery, via IOKit power-source notifications.
@MainActor
final class PowerMonitor {
    var onChange: ((Bool) -> Void)?
    private(set) var isOnBattery = PowerMonitor.readOnBattery()
    private var source: CFRunLoopSource?

    init() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        // The run-loop source is added to the main run loop, so the C callback runs on the main thread.
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.update() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.source = source
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
    }

    private func update() {
        let onBattery = Self.readOnBattery()
        guard onBattery != isOnBattery else { return }
        isOnBattery = onBattery
        onChange?(onBattery)
    }

    private static func readOnBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue()
        else { return false }
        return (type as String) == kIOPSBatteryPowerValue
    }
}
