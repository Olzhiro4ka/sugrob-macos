/// One window as reported by a window-list poll (AppKit global points).
public struct WindowSample: Equatable, Sendable {
    public var id: UInt32
    public var frame: Rect

    public init(id: UInt32, frame: Rect) {
        self.id = id
        self.frame = frame
    }
}

/// Turns discrete window-list polls into smooth per-window state: velocity, extrapolated
/// positions between polls, z-order, and debounced disappearance.
public final class WindowRegistry {
    public struct Entry: Sendable {
        public let id: UInt32
        /// Latest polled frame.
        public internal(set) var frame: Rect
        /// Frame from the poll before the latest one.
        public internal(set) var previousFrame: Rect
        /// Simulation time of the latest poll in which the window was present (s).
        public internal(set) var sampleTime: Float
        /// Smoothed origin velocity (pt/s).
        public internal(set) var velocity: SIMD2<Float> = .zero
        /// Consecutive polls the window was missing from.
        public internal(set) var missingPolls = 0
        /// Position in the latest poll, 0 = frontmost. Missing windows keep their last value.
        public internal(set) var zIndex: Int

        public var isPresent: Bool { missingPolls == 0 }
    }

    public struct Changes: Sendable {
        public var appeared: [UInt32] = []
        /// Windows gone for `Config.disappearPolls` polls, with their last state.
        public var disappeared: [Entry] = []
        /// Whether any frame, z-order or presence changed in this poll.
        public var anyChange = false
    }

    public private(set) var entries: [UInt32: Entry] = [:]
    /// Present windows front to back, followed by missing (debouncing) ones.
    public private(set) var order: [UInt32] = []
    /// Simulation time of the last poll that changed anything (s).
    public private(set) var lastChangeTime: Float = -.infinity

    public init() {}

    @discardableResult
    public func ingest(_ samples: [WindowSample], time: Float) -> Changes {
        var changes = Changes()
        var seen = Set<UInt32>(minimumCapacity: samples.count)
        var newOrder: [UInt32] = []
        newOrder.reserveCapacity(samples.count)

        for (z, sample) in samples.enumerated() where !seen.contains(sample.id) {
            seen.insert(sample.id)
            newOrder.append(sample.id)
            if var entry = entries[sample.id] {
                let dt = time - entry.sampleTime
                let delta = sample.frame.origin - entry.frame.origin
                if delta == .zero {
                    entry.velocity = .zero
                } else if dt > 0 {
                    let raw = delta / dt
                    entry.velocity = entry.velocity == .zero
                        ? raw
                        : entry.velocity + (raw - entry.velocity) * Config.velocitySmoothing
                }
                if sample.frame != entry.frame || entry.zIndex != z || !entry.isPresent {
                    changes.anyChange = true
                }
                entry.previousFrame = entry.frame
                entry.frame = sample.frame
                entry.sampleTime = time
                entry.missingPolls = 0
                entry.zIndex = z
                entries[sample.id] = entry
            } else {
                entries[sample.id] = Entry(id: sample.id, frame: sample.frame, previousFrame: sample.frame,
                                           sampleTime: time, zIndex: z)
                changes.appeared.append(sample.id)
                changes.anyChange = true
            }
        }

        for id in order where !seen.contains(id) {
            guard var entry = entries[id] else { continue }
            if entry.isPresent { changes.anyChange = true }
            entry.missingPolls += 1
            entry.velocity = .zero
            if entry.missingPolls >= Config.disappearPolls {
                entries[id] = nil
                changes.disappeared.append(entry)
            } else {
                entries[id] = entry
                newOrder.append(id)
            }
        }

        order = newOrder
        if changes.anyChange { lastChangeTime = time }
        return changes
    }

    /// Frame of `id` at `time`, extrapolated along its velocity for at most
    /// `Config.maxExtrapolation` past the latest poll.
    public func frame(of id: UInt32, at time: Float) -> Rect? {
        guard let entry = entries[id] else { return nil }
        let ahead = min(max(time - entry.sampleTime, 0), Config.maxExtrapolation)
        return entry.frame.offsetBy(entry.velocity * ahead)
    }

    /// True while any present window has a non-zero velocity.
    public var anyMoving: Bool {
        entries.values.contains { $0.isPresent && $0.velocity != .zero }
    }
}
