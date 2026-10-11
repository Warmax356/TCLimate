import SwiftUI
import AppKit

/// Keeps the menu bar window's top edge just under the menu bar of whichever screen it's on.
/// AppKit resizes windows around a fixed bottom-left origin, and MenuBarExtra doesn't re-anchor
/// when its content height changes, which otherwise opens a gap below the menu bar.
/// The top is derived from the screen each time (not remembered), so it stays right across
/// screens, sign-in/out and reopening. MenuBarExtra also keeps a taller frame after the content
/// shrinks (e.g. devices → sign-in), centering the content in it, so `height` resizes the window too.
struct WindowTopAnchor: NSViewRepresentable {
    var height: CGFloat?

    func makeNSView(context: Context) -> NSView { AnchorView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? AnchorView, view.height != height else { return }
        view.height = height
        DispatchQueue.main.async { view.anchor() }
    }

    fileprivate final class AnchorView: NSView {
        var height: CGFloat?
        private var gap: CGFloat?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            let center = NotificationCenter.default
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification] {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.anchor() }
                })
            }
            anchor()
        }

        func anchor() {
            guard let window, let screen = window.screen ?? NSScreen.main else { return }
            // Bottom of the menu bar; with an auto-hiding menu bar, visibleFrame reaches the top edge.
            let menuBarBottom = screen.visibleFrame.maxY < screen.frame.maxY
                ? screen.visibleFrame.maxY
                : screen.frame.maxY - NSStatusBar.system.thickness
            // Keep the system's own spacing from the first correct placement.
            if gap == nil {
                let measured = menuBarBottom - window.frame.maxY
                gap = (0...12).contains(measured) ? measured : 4
            }
            let top = menuBarBottom - (gap ?? 4)
            let height = (self.height ?? window.frame.height).rounded(.up)
            guard abs(window.frame.maxY - top) > 0.5 || abs(window.frame.height - height) > 0.5 else { return }
            window.setFrame(NSRect(x: window.frame.minX, y: top - height, width: window.frame.width, height: height), display: true)
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}
