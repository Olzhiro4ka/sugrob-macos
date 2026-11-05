/// Pure conversions between CoreGraphics global display space and AppKit global space.
///
/// - CoreGraphics (`CGWindowListCopyWindowInfo`): origin at the primary display's top-left,
///   y grows down.
/// - AppKit (`NSScreen`, SnowCore): origin at the primary display's bottom-left, y grows up.
///
/// Both share the x axis. `primaryHeight` is the height of the primary display
/// (`NSScreen.screens[0].frame.maxY`), never `NSScreen.main`.
public enum CoordinateMath {
    public static func appKitRect(fromCG rect: Rect, primaryHeight: Float) -> Rect {
        Rect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func cgRect(fromAppKit rect: Rect, primaryHeight: Float) -> Rect {
        // The flip is its own inverse.
        appKitRect(fromCG: rect, primaryHeight: primaryHeight)
    }
}
