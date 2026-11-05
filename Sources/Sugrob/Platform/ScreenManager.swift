import AppKit
import SnowCore

/// Keeps one overlay (window + renderer) per `NSScreen`, rebuilt when the display layout changes.
@MainActor
final class ScreenManager {
    struct Overlay {
        let window: OverlayWindow
        let renderer: SnowRenderer
        let rect: Rect
    }

    private let gpu: SnowGPU
    private let world: World
    private(set) var overlays: [Overlay] = []
    /// Called after overlays were rebuilt.
    var onRebuild: (() -> Void)?

    /// Global switch (pause); per-screen fullscreen hiding is applied on top.
    private var globallyVisible = true
    /// Indices of overlays hidden because a fullscreen window covers that screen.
    private(set) var fullscreenHidden: Set<Int> = []

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

    var allHiddenByFullscreen: Bool {
        !overlays.isEmpty && fullscreenHidden.count == overlays.count
    }

    func setVisible(_ visible: Bool) {
        globallyVisible = visible
        applyVisibility()
    }

    /// Hides overlays whose screen is covered by a fullscreen window; others keep snowing.
    func setFullscreen(_ indices: Set<Int>) {
        guard indices != fullscreenHidden else { return }
        fullscreenHidden = indices
        applyVisibility()
    }

    func render() {
        for (index, overlay) in overlays.enumerated() where !fullscreenHidden.contains(index) {
            overlay.window.snowView.draw()
        }
    }

    /// Sum of cap segments drawn last frame, for the HUD.
    var lastCapSegments: Int { overlays.reduce(0) { $0 + $1.renderer.lastCapSegments } }

    @objc private func screensChanged() {
        rebuild()
    }

    private func applyVisibility() {
        for (index, overlay) in overlays.enumerated() {
            if globallyVisible && !fullscreenHidden.contains(index) {
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
        for overlay in overlays {
            overlay.window.snowView.delegate = nil
            overlay.window.orderOut(nil)
            overlay.window.close()
        }
        fullscreenHidden = []
        overlays = NSScreen.screens.compactMap { screen in
            let window = OverlayWindow(screen: screen, device: gpu.device)
            guard let renderer = SnowRenderer(gpu: gpu, world: world, screen: screen) else { return nil }
            renderer.debugSurfaces = debugSurfaces
            window.snowView.delegate = renderer
            return Overlay(window: window, renderer: renderer, rect: CoordinateSpace.core(screen.frame))
        }
        applyVisibility()
        world.setScreens(screenRects)
        onRebuild?()
    }
}
