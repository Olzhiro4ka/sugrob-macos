/// Occlusion of window top edges. A surface is the top edge of a window; it can only hold and
/// show snow where no window in front of it covers the snow band above that edge.
public enum Occlusion {
    /// - Parameters:
    ///   - frames: window frames, **front to back**.
    ///   - present: whether each window is currently on screen (missing ones neither show snow
    ///     nor occlude).
    ///   - band: height above a top edge that a front window must overlap to hide it (pt).
    /// - Returns: visible x-intervals of each window's top edge, same order as `frames`.
    public static func visibleIntervals(frames: [Rect], present: [Bool], band: Float = Config.occlusionBand) -> [[Interval]] {
        var result: [[Interval]] = []
        result.reserveCapacity(frames.count)
        for (index, frame) in frames.enumerated() {
            guard present[index] else {
                result.append([])
                continue
            }
            let edge = frame.maxY
            var visible = [Interval(frame.minX, frame.maxX)]
            for front in 0..<index where present[front] {
                let other = frames[front]
                if other.maxY > edge && other.minY < edge + band {
                    Intervals.subtract(&visible, other.minX, other.maxX)
                    if visible.isEmpty { break }
                }
            }
            visible.removeAll { $0.length < Config.minVisibleInterval }
            result.append(visible)
        }
        return result
    }
}
