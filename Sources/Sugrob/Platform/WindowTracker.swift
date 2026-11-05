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

    /// Polls off the main thread. `completion` receives normal windows front to back in AppKit
    /// global points, plus the poll duration (s), on the main actor.
    func poll(primaryHeight: Float, completion: @escaping @MainActor @Sendable ([WindowSample], Double) -> Void) {
        let ownPID = ownPID
        queue.async {
            let start = CACurrentMediaTime()
            let samples = Self.read(primaryHeight: primaryHeight, ownPID: ownPID)
            let duration = CACurrentMediaTime() - start
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(samples, duration) }
            }
        }
    }

    private static func read(primaryHeight: Float, ownPID: pid_t) -> [WindowSample] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]
        else { return [] }

        let minSize = Config.minWindowSize
        var samples: [WindowSample] = []
        samples.reserveCapacity(list.count)
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
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
        return samples
    }
}
