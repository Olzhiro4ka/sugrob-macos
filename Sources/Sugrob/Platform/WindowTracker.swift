import AppKit
import SnowCore

/// Reads on-screen window geometry with `CGWindowListCopyWindowInfo`, no permissions needed.
///
/// Only these keys are ever read: number, bounds, layer, owner PID, alpha. **Never**
/// `kCGWindowName`: reading titles is what requires Screen Recording.
///
/// The call is an IPC round trip to the WindowServer (~0.2 ms warm, 1–4 ms cold at 8 Hz), so it
/// runs on a background serial queue and never blocks the main thread or the render path.
final class WindowTracker: Sendable {
    private let queue = DispatchQueue(label: "io.github.sugrob.window-tracker", qos: .userInitiated)
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    struct Result: Sendable {
        /// Normal windows, front to back, AppKit global points.
        var samples: [WindowSample]
        /// Mission Control (or App Exposé) is showing: the Dock puts a layer-18 window on
        /// screen, and other windows report their *scaled-down* frames. Layer 20 also appears
        /// on ordinary desktops and must not pause snowfall.
        var missionControl: Bool
        /// Poll duration (s).
        var duration: Double
    }

    /// Polls off the main thread; `completion` runs on the main actor.
    func poll(primaryHeight: Float, system: SystemProcesses.Snapshot,
              completion: @escaping @MainActor @Sendable (Result) -> Void) {
        let ownPID = ownPID
        let dockPIDs = system.dock
        let systemPIDs = system.all
        queue.async {
            let start = CACurrentMediaTime()
            var result = Self.read(primaryHeight: primaryHeight, ownPID: ownPID,
                                   dockPIDs: dockPIDs, systemPIDs: systemPIDs)
            result.duration = CACurrentMediaTime() - start
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(result) }
            }
        }
    }

    private static func read(primaryHeight: Float, ownPID: pid_t,
                             dockPIDs: Set<pid_t>, systemPIDs: Set<pid_t>) -> Result {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]
        else { return Result(samples: [], missionControl: false, duration: 0) }

        let minSize = Config.minWindowSize
        var samples: [WindowSample] = []
        var missionControl = false
        samples.reserveCapacity(list.count)
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t
            else { continue }
            if dockPIDs.contains(pid) && layer == 18 {
                missionControl = true
                continue
            }
            guard layer == 0, pid != ownPID, !systemPIDs.contains(pid),
                  let number = info[kCGWindowNumber as String] as? UInt32,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
            else { continue }
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            guard alpha > 0.01,
                  Float(bounds.width) >= minSize.x, Float(bounds.height) >= minSize.y
            else { continue }
            samples.append(WindowSample(id: number, frame: CoordinateSpace.core(fromCG: bounds, primaryHeight: primaryHeight)))
        }
        return Result(samples: samples, missionControl: missionControl, duration: 0)
    }
}

/// PIDs of system processes whose layer-0 windows are not real windows (Stage Manager
/// thumbnails, Dock overlays). Looking them up is a synchronous LaunchServices XPC call, so
/// they are cached and refreshed only when apps launch or quit (the Dock relaunches rarely).
@MainActor
final class SystemProcesses {
    struct Snapshot: Sendable {
        var dock: Set<pid_t> = []
        var all: Set<pid_t> = []
    }

    private static let dockBundleID = "com.apple.dock"
    private static let bundleIDs = [dockBundleID, "com.apple.WindowManager"]

    private(set) var snapshot = Snapshot()

    init() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(refresh),
                           name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(refresh),
                           name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        refresh()
    }

    @objc private func refresh() {
        var snapshot = Snapshot()
        for bundleID in Self.bundleIDs {
            let pids = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).map(\.processIdentifier)
            snapshot.all.formUnion(pids)
            if bundleID == Self.dockBundleID { snapshot.dock.formUnion(pids) }
        }
        self.snapshot = snapshot
    }
}
