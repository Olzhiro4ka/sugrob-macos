import AppKit
import SnowCore

/// Keeps one overlay (window + renderer) per `NSScreen`, rebuilt when the display layout changes.
@MainActor
final class ScreenManager {
    struct Overlay {
        let window: OverlayWindow
        let renderer: SnowRenderer
    }

    private let gpu: SnowGPU
    private let world: World
    private(set) var overlays: [Overlay] = []
    /// Called after overlays were rebuilt.
    var onRebuild: (() -> Void)?

    init(gpu: SnowGPU, world: World) {
        self.gpu = gpu
        self.world = world
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        rebuild()
    }

    var screenRects: [Rect] { overlays.map { CoordinateSpace.core($0.window.screenFrame) } }

    func setVisible(_ visible: Bool) {
        for overlay in overlays {
            if visible {
                overlay.renderer.invalidate()
                overlay.window.orderFrontRegardless()
            } else {
                overlay.window.orderOut(nil)
            }
        }
    }

    func render() {
        for overlay in overlays {
            overlay.window.snowView.draw()
        }
    }

    @objc private func screensChanged() {
        rebuild()
    }

    private func rebuild() {
        let wasVisible = overlays.first?.window.isVisible ?? true
        for overlay in overlays {
            overlay.window.snowView.delegate = nil
            overlay.window.orderOut(nil)
            overlay.window.close()
        }
        overlays = NSScreen.screens.compactMap { screen in
            let window = OverlayWindow(screen: screen, device: gpu.device)
            guard let renderer = SnowRenderer(gpu: gpu, world: world, screenFrame: screen.frame) else { return nil }
            window.snowView.delegate = renderer
            if wasVisible { window.orderFrontRegardless() }
            return Overlay(window: window, renderer: renderer)
        }
        world.setScreens(screenRects)
        onRebuild?()
    }
}
