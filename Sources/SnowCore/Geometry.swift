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

    public func contains(_ point: SIMD2<Float>) -> Bool {
        point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    }

    /// True when a circle of `radius` around `point` touches this rect.
    public func intersects(circleAt point: SIMD2<Float>, radius: Float) -> Bool {
        point.x + radius >= minX && point.x - radius <= maxX
            && point.y + radius >= minY && point.y - radius <= maxY
    }
}
