/// Geometry check for a window covering the display below the menu bar, including the Dock.
/// Allows small overscan from window animations while keeping windows that stop above the Dock out.
public enum FullscreenCoverage {
    public static func covers(_ window: Rect, screen: Rect, visible: Rect? = nil) -> Bool {
        let tolerance = Config.fullscreenEdgeTolerance
        let top = visible?.maxY ?? screen.maxY
        return window.minX <= screen.minX + tolerance
            && window.minY <= screen.minY + tolerance
            && window.maxX >= screen.maxX - tolerance
            && window.maxY >= top - tolerance
    }
}
