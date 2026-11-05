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
        /// Mission Control (or App Exposé) is showing: the Dock puts full-screen windows on
        /// layers 18/20 on screen, and other windows report their *scaled-down* frames.
        var missionControl: Bool
        /// Poll duration (s).
        var duration: Double
    }

    /// System processes whose layer-0 windows are not real windows (Stage Manager thumbnails,
    /// Dock overlays).
    private static let systemBundleIDs = ["com.apple.dock", "com.apple.WindowManager"]

    /// Polls off the main thread; `completion` runs on the main actor.
    func poll(primaryHeight: Float, completion: @escaping @MainActor @Sendable (Result) -> Void) {
        let ownPID = ownPID
        let dockPIDs = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
            .map(\.processIdentifier))
        let systemPIDs = Set(Self.systemBundleIDs.flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0).map(\.processIdentifier)
        })
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
            if dockPIDs.contains(pid) && (layer == 18 || layer == 20) {
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
