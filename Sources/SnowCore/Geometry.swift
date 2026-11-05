/// Axis-aligned rectangle in AppKit global points (origin bottom-left, y up).
public struct Rect: Equatable, Sendable {
    public var minX: Float
    public var minY: Float
    public var width: Float
    public var height: Float

    public init(x: Float, y: Float, width: Float, height: Float) {
        minX = x
        minY = y
        self.width = width
        self.height = height
    }

    public var maxX: Float { minX + width }
    public var maxY: Float { minY + height }
    public var area: Float { width * height }
    public var midX: Float { minX + width / 2 }
    public var origin: SIMD2<Float> { SIMD2(minX, minY) }

    public func contains(_ point: SIMD2<Float>) -> Bool {
        point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    }

    /// True when a circle of `radius` around `point` touches this rect.
    public func intersects(circleAt point: SIMD2<Float>, radius: Float) -> Bool {
        point.x + radius >= minX && point.x - radius <= maxX
            && point.y + radius >= minY && point.y - radius <= maxY
    }

    public func offsetBy(_ delta: SIMD2<Float>) -> Rect {
        Rect(x: minX + delta.x, y: minY + delta.y, width: width, height: height)
    }

    /// Equal within `tolerance` on every edge.
    public func isClose(to other: Rect, tolerance: Float) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(maxX - other.maxX) <= tolerance && abs(maxY - other.maxY) <= tolerance
    }
}

/// Closed horizontal interval `[lower, upper]` (pt).
public struct Interval: Equatable, Sendable {
    public var lower: Float
    public var upper: Float

    public init(_ lower: Float, _ upper: Float) {
        self.lower = lower
        self.upper = upper
    }

    public var length: Float { upper - lower }

    public func contains(_ x: Float) -> Bool { x >= lower && x <= upper }
}

public enum Intervals {
    /// Removes `[cutLower, cutUpper]` from a sorted, disjoint list of intervals, in place.
    public static func subtract(_ intervals: inout [Interval], _ cutLower: Float, _ cutUpper: Float) {
        guard cutUpper > cutLower else { return }
        var result: [Interval] = []
        result.reserveCapacity(intervals.count + 1)
        for interval in intervals {
            if cutUpper <= interval.lower || cutLower >= interval.upper {
                result.append(interval)
                continue
            }
            if cutLower > interval.lower { result.append(Interval(interval.lower, cutLower)) }
            if cutUpper < interval.upper { result.append(Interval(cutUpper, interval.upper)) }
        }
        intervals = result
    }

    public static func contains(_ intervals: [Interval], _ x: Float) -> Bool {
        intervals.contains { $0.contains(x) }
    }
}
