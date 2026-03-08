import Cocoa
import SwiftUI

/// Notification posted when a window thumbnail is captured for DockPeek
extension Notification.Name {
    static let dockPeekThumbnailReady = Notification.Name("dockPeekThumbnailReady")
}

/// Floating borderless panel that shows window previews when hovering dock icons.
final class DockPeekPanel: NSPanel {

    private var hostingView: NSHostingView<DockPeekView>?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar + 1
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
    }

    // MARK: - Show / Hide

    func showPreview(
        windows: [WindowItem],
        appIcon: NSImage,
        appName: String,
        bundleId: String,
        dockItemFrame: CGRect,
        dockPosition: DockPosition
    ) {
        let view = DockPeekView(
            windows: windows,
            appIcon: appIcon,
            appName: appName,
            bundleId: bundleId
        )

        let hosting = NSHostingView(rootView: view)
        contentView = hosting
        hostingView = hosting

        // Capture thumbnails asynchronously
        for window in windows where !window.isMinimized && window.cgWindowID > 0 {
            let winId = window.id
            AppDiscoveryService.shared.captureWindowPreviewAsync(
                cgWindowID: window.cgWindowID, maxSize: 280
            ) { img in
                guard let img = img else { return }
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .dockPeekThumbnailReady,
                        object: nil,
                        userInfo: ["windowId": winId, "image": img]
                    )
                }
            }
        }

        // Let SwiftUI compute the natural content size
        let fitting = hosting.fittingSize
        let panelW = min(max(fitting.width, 160), 820)
        let panelH = max(fitting.height, 40)

        // Position panel relative to dock item
        let panelFrame = calculatePanelFrame(
            panelSize: NSSize(width: panelW, height: panelH),
            dockItemFrame: dockItemFrame,
            dockPosition: dockPosition
        )

        setFrame(panelFrame, display: true)

        // Animate in
        alphaValue = 0
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    func hidePreview() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
        })
    }

    // MARK: - Panel Positioning

    private func calculatePanelFrame(
        panelSize: NSSize,
        dockItemFrame: CGRect,
        dockPosition: DockPosition
    ) -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(origin: .zero, size: panelSize)
        }

        let screenH = screen.frame.height
        var origin = CGPoint.zero

        switch dockPosition {
        case .bottom, .unknown:
            let dockItemTopNS = screenH - dockItemFrame.minY
            let dockItemCenterX = dockItemFrame.midX
            origin.x = dockItemCenterX - panelSize.width / 2
            origin.y = dockItemTopNS + 2

        case .left:
            let dockItemRight = dockItemFrame.maxX
            let dockItemCenterY = screenH - dockItemFrame.midY
            origin.x = dockItemRight + 2
            origin.y = dockItemCenterY - panelSize.height / 2

        case .right:
            let dockItemLeft = dockItemFrame.minX
            let dockItemCenterY = screenH - dockItemFrame.midY
            origin.x = dockItemLeft - panelSize.width - 2
            origin.y = dockItemCenterY - panelSize.height / 2
        }

        // Clamp to screen bounds
        let screenFrame = screen.visibleFrame
        origin.x = max(screenFrame.minX + 2, min(origin.x, screenFrame.maxX - panelSize.width - 2))
        origin.y = max(screenFrame.minY + 2, min(origin.y, screenFrame.maxY - panelSize.height - 2))

        return NSRect(origin: origin, size: panelSize)
    }
}
