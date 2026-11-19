import AppKit
import MacampCore

/// A window with no system chrome that can still take keyboard focus.
final class ChromelessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Owns the player window and rebuilds or resizes it to suit the active skin.
final class PlayerWindowController: NSObject, NSWindowDelegate {
    private(set) var window: NSWindow
    let view: SkinView
    private var skin: Skin
    private var replacingWindow = false

    /// The user closed the window.
    var onClose: (() -> Void)?
    /// The window moved or changed height, so its saved position is stale.
    var onFrameChange: (() -> Void)?

    init(controller: PlayerController, skin: Skin, origin: [Double]?, height: Double?) {
        self.skin = skin
        let h = Self.height(for: skin, saved: height)
        view = SkinView(controller: controller, skin: skin, height: h)
        window = Self.makeWindow(for: skin, height: h)
        super.init()
        install(view, in: window)
        if let origin, origin.count == 2 {
            setTopLeft(CGPoint(x: origin[0], y: origin[1]))
        } else {
            window.center()
        }
        keepOnScreen()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
    }

    /// The window's top-left corner in screen coordinates, which stays put when the height changes.
    var topLeft: CGPoint { CGPoint(x: window.frame.minX, y: window.frame.maxY) }
    var contentHeight: CGFloat { view.bounds.height }

    func apply(skin newSkin: Skin) {
        let old = skin
        skin = newSkin
        let corner = topLeft
        let h = Self.height(for: newSkin, saved: newSkin.window.resize == .vertical && old.window.resize == .vertical
                            ? Double(contentHeight) : nil)
        if old.window.titleBar != newSkin.window.titleBar {
            // The two title bar modes need different kinds of window, so swap windows.
            let replacement = Self.makeWindow(for: newSkin, height: h)
            let previous = window
            replacingWindow = true
            previous.delegate = nil
            view.removeFromSuperview()
            window = replacement
            view.apply(skin: newSkin)
            install(view, in: replacement)
            setTopLeft(corner)
            show()
            previous.close()
            replacingWindow = false
        } else {
            configure(window, for: newSkin)
            view.apply(skin: newSkin)
            window.setContentSize(CGSize(width: newSkin.window.size.width, height: h))
            setTopLeft(corner)
            window.invalidateShadow()
        }
        keepOnScreen()
    }

    // MARK: Building

    private static func height(for skin: Skin, saved: Double?) -> CGFloat {
        guard skin.window.resize == .vertical, let saved else { return skin.window.size.height }
        return CGFloat(min(skin.window.maxHeight, max(skin.window.minHeight, saved)))
    }

    private static func makeWindow(for skin: Skin, height: CGFloat) -> NSWindow {
        let rect = CGRect(x: 0, y: 0, width: skin.window.size.width, height: height)
        let window: NSWindow
        switch skin.window.titleBar {
        case .system:
            window = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.standardWindowButton(.zoomButton)?.isEnabled = false
        case .none:
            window = ChromelessWindow(contentRect: rect, styleMask: [.closable, .miniaturizable, .resizable],
                                      backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
        }
        window.title = "macamp"
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.fullScreenNone]
        configure(window, for: skin)
        return window
    }

    /// Size limits follow the skin: width is fixed, height moves only if the skin allows it.
    private static func configure(_ window: NSWindow, for skin: Skin) {
        let width = skin.window.size.width
        if skin.window.resize == .vertical {
            window.contentMinSize = CGSize(width: width, height: skin.window.minHeight)
            window.contentMaxSize = CGSize(width: width, height: skin.window.maxHeight)
        } else {
            window.contentMinSize = skin.window.size
            window.contentMaxSize = skin.window.size
        }
    }

    private func configure(_ window: NSWindow, for skin: Skin) { Self.configure(window, for: skin) }

    private func install(_ view: SkinView, in window: NSWindow) {
        view.frame = CGRect(origin: .zero, size: window.contentLayoutRect.size == .zero
                            ? window.frame.size : window.contentRect(forFrameRect: window.frame).size)
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        window.delegate = self
        window.initialFirstResponder = view
    }

    private func setTopLeft(_ point: CGPoint) {
        window.setFrameTopLeftPoint(point)
    }

    /// Pulls the window back if a saved position would leave it off every screen.
    private func keepOnScreen() {
        let frame = window.frame
        let visible = NSScreen.screens.contains { $0.visibleFrame.intersection(frame).width > 60
            && $0.visibleFrame.intersection(frame).height > 40 }
        if !visible { window.center() }
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard !replacingWindow, (notification.object as? NSWindow) === window else { return }
        onClose?()
    }

    func windowDidMove(_ notification: Notification) { onFrameChange?() }

    func windowDidResize(_ notification: Notification) {
        window.invalidateShadow()
        onFrameChange?()
    }

    func windowDidChangeOcclusionState(_ notification: Notification) { view.updateTicking() }
    func windowDidMiniaturize(_ notification: Notification) { view.updateTicking() }
    func windowDidDeminiaturize(_ notification: Notification) { view.updateTicking() }
}
