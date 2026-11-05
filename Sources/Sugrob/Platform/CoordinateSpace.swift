import AppKit
import SnowCore

/// The single place for coordinate conversions (see CLAUDE.md, "Coordinate spaces").
/// SnowCore works in AppKit global points, y up.
enum CoordinateSpace {
    /// AppKit global rect → SnowCore rect (same space, different type).
    static func core(_ rect: CGRect) -> Rect {
        Rect(x: Float(rect.minX), y: Float(rect.minY), width: Float(rect.width), height: Float(rect.height))
    }
}
