import AppKit
import MetalKit

/// Borderless, transparent, click-through window covering one screen.
@MainActor
final class OverlayWindow: NSWindow {
    let snowView: MTKView
    /// Global AppKit frame of the screen this overlay covers.
    let screenFrame: CGRect

    init(screen: NSScreen, device: MTLDevice) {
        screenFrame = screen.frame
        snowView = MTKView(frame: CGRect(origin: .zero, size: screen.frame.size), device: device)
        // Init without `screen:` (that variant interprets contentRect relative to the screen),
        // then place the frame in global coordinates explicitly.
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)

        // Above the Dock so snow can sit on it, below menus/pop-ups so they cover the flakes.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none

        snowView.colorPixelFormat = .bgra8Unorm
        snowView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        snowView.framebufferOnly = true
        snowView.layer?.isOpaque = false
        // Each full-screen Retina drawable is ~22 MB (2940×1912 px × 4 B); the default 3 alone
        // alone would add ~22 MB. Measured: two give even frame pacing at 30 and 60 fps (no drops);
        // at 60 fps `currentDrawable` waits ~0.7 ms for the compositor, which is acceptable.
        (snowView.layer as? CAMetalLayer)?.maximumDrawableCount = 2
        // We drive drawing ourselves from the shared display link.
        snowView.isPaused = true
        snowView.enableSetNeedsDisplay = false
        snowView.autoresizingMask = [.width, .height]
        contentView = snowView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Borderless windows must not be nudged below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
