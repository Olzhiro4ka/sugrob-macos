import AppKit
import SnowCore

/// Keeps one overlay (window + renderer) per `NSScreen`, rebuilt when the display layout changes.
@MainActor
final class ScreenManager {
    struct Overlay {
        let window: OverlayWindow
        let renderer: SnowRenderer
        let screen: NSScreen
        let rect: Rect
    }

    private let gpu: SnowGPU
    private let world: World
    private(set) var overlays: [Overlay] = []
    /// Overlays skipped while macOS considers them fully occluded during Space transitions.
    private var occludedOverlays: Set<Int> = []
    /// Called after overlays were rebuilt.
    var onRebuild: (() -> Void)?

    /// Global switch for user and session pauses.
    private var globallyVisible = true

    var debugSurfaces = false {
        didSet { for overlay in overlays { overlay.renderer.debugSurfaces = debugSurfaces } }
    }

    init(gpu: SnowGPU, world: World) {
        self.gpu = gpu
        self.world = world
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        rebuild()
    }

    var screenRects: [Rect] { overlays.map(\.rect) }

    func setVisible(_ visible: Bool) {
        globallyVisible = visible
        applyVisibility()
    }

    func render() {
        for (index, overlay) in overlays.enumerated() {
            guard overlay.window.occlusionState.contains(.visible) else {
                occludedOverlays.insert(index)
                continue
            }
            if occludedOverlays.remove(index) != nil {
                overlay.renderer.invalidate()
            }
            overlay.window.snowView.draw()
        }
    }

    var presentedFrames: Int { overlays.reduce(0) { $0 + $1.renderer.presentedFrames } }
    var droppedFrames: Int { overlays.reduce(0) { $0 + $1.renderer.droppedFrames } }

    /// Sum of cap segments drawn last frame, for the HUD.
    var lastCapSegments: Int { overlays.reduce(0) { $0 + $1.renderer.lastCapSegments } }

    private struct ScreenLayout: Equatable {
        let frame: CGRect
        let scale: CGFloat
    }

    /// Frames and scales of the screens the overlays were built for.
    private var layoutSignature: [ScreenLayout] = []

    private static func currentSignature() -> [ScreenLayout] {
        NSScreen.screens.map { ScreenLayout(frame: $0.frame, scale: $0.backingScaleFactor) }
    }

    @objc private func screensChanged() {
        // Also posted when only a `visibleFrame` changes (Dock resized, menu bar hidden);
        // rebuilding then would needlessly reshuffle every flake.
        guard Self.currentSignature() != layoutSignature else { return }
        rebuild()
    }

    private func applyVisibility() {
        for overlay in overlays {
            if globallyVisible {
                if !overlay.window.isVisible {
                    overlay.renderer.invalidate()
                    overlay.window.orderFrontRegardless()
                }
            } else if overlay.window.isVisible {
                overlay.window.orderOut(nil)
            }
        }
    }

    private func rebuild() {
        occludedOverlays.removeAll()
        for overlay in overlays {
            overlay.window.snowView.delegate = nil
            overlay.window.orderOut(nil)
            overlay.window.close()
        }
        layoutSignature = Self.currentSignature()
        overlays = NSScreen.screens.compactMap { screen in
            let window = OverlayWindow(screen: screen, device: gpu.device)
            guard let renderer = SnowRenderer(gpu: gpu, world: world, screen: screen) else { return nil }
            renderer.debugSurfaces = debugSurfaces
            window.snowView.delegate = renderer
            return Overlay(window: window, renderer: renderer, screen: screen,
                           rect: CoordinateSpace.core(screen.frame))
        }
        applyVisibility()
        world.setScreens(screenRects)
        onRebuild?()
    }
}
