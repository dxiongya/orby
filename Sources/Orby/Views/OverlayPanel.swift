import Cocoa

final class OverlayPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        hasShadow = false
        backgroundColor = .clear
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func showOverlay() {
        makeKeyAndOrderFront(nil)
    }

    func hideOverlay() {
        orderOut(nil)
    }
}
