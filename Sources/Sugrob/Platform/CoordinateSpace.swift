import AppKit
import SnowCore

/// The single place for coordinate conversions (see CLAUDE.md, "Coordinate spaces").
/// SnowCore works in AppKit global points, y up; the math lives in `SnowCore.CoordinateMath`.
enum CoordinateSpace {
    /// Height of the primary display: the screen with the menu bar, whose AppKit origin is (0, 0).
    /// Deliberately not `NSScreen.main` (that is the screen with the key window).
    @MainActor
    static var primaryHeight: Float {
        Float(NSScreen.screens.first?.frame.maxY ?? 0)
    }

    /// AppKit global rect → SnowCore rect (same space, different type).
    static func core(_ rect: CGRect) -> Rect {
        Rect(x: Float(rect.minX), y: Float(rect.minY), width: Float(rect.width), height: Float(rect.height))
    }

    /// CoreGraphics global rect (top-left origin, y down) → SnowCore rect (AppKit, y up).
    static func core(fromCG rect: CGRect, primaryHeight: Float) -> Rect {
        CoordinateMath.appKitRect(fromCG: core(rect), primaryHeight: primaryHeight)
    }
}
