import Cocoa
import ApplicationServices

// Private API to get dock orientation — declared at file scope
@_silgen_name("CoreDockGetOrientationAndPinning")
func CoreDockGetOrientationAndPinning(_ orientation: UnsafeMutablePointer<Int32>, _ pinning: UnsafeMutablePointer<Int32>)

enum DockPosition {
    case bottom, left, right, unknown

    var isHorizontal: Bool {
        switch self {
        case .bottom, .unknown: return true
        case .left, .right: return false
        }
    }

    static func current() -> DockPosition {
        var orientation: Int32 = 0
        var pinning: Int32 = 0
        CoreDockGetOrientationAndPinning(&orientation, &pinning)
        switch orientation {
        case 2: return .bottom
        case 3: return .left
        case 4: return .right
        default: return .bottom
        }
    }

    static func dockSize() -> CGFloat {
        guard let screen = NSScreen.main else { return 0 }
        let pos = current()
        switch pos {
        case .right:  return screen.frame.width - screen.visibleFrame.maxX
        case .left:   return screen.visibleFrame.origin.x - screen.frame.origin.x
        case .bottom: return screen.visibleFrame.origin.y - screen.frame.origin.y
        case .unknown: return 0
        }
    }
}

/// Hovered dock item info
struct DockItemInfo {
    let app: NSRunningApplication
    let dockItemElement: AXUIElement
    let bundleId: String
}

// Global C callback for AXObserver — must be a free function
private func dockSelectionChangedCallback(
    observer: AXObserver, element: AXUIElement, notification: CFString, refcon: UnsafeMutableRawPointer?
) {
    DockPeekService.shared.handleDockItemChanged()
}

/// Monitors Dock item hover via Accessibility notifications and shows window previews.
final class DockPeekService {
    static let shared = DockPeekService()

    private(set) var isEnabled = false
    private var axObserver: AXObserver?
    private var dockPID: pid_t?
    private var subscribedDockList: AXUIElement?
    private var healthCheckTimer: Timer?
    private var lastHoveredBundleId: String?
    private var lastShownItem: DockItemInfo?

    // Preview panel
    private var previewPanel: DockPeekPanel?
    private var hideWorkItem: DispatchWorkItem?

    // Track the last dock item frame (in NS coordinates) for dismiss logic
    private var lastDockItemFrameNS: CGRect = .zero

    // Grace period — don't dismiss within this window after showing
    private var showTime: CFTimeInterval = 0

    // Mouse tracking for dismiss
    private var mouseMonitor: Any?
    private var dismissPollTimer: Timer?

    private init() {}

    // MARK: - Public

    /// Immediately dismiss the preview panel (e.g. after activating a window).
    func dismissPreview() {
        hidePreviewNow()
    }

    /// Refresh the current preview after a window action (close/minimize/fullscreen).
    /// Re-fetches windows for the same app; dismisses if no windows remain.
    func refreshPreview() {
        guard let item = lastShownItem else { return }
        // Short delay to let the window action take effect
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self = self, self.lastHoveredBundleId == item.bundleId else { return }
            let windows = AppDiscoveryService.shared.getWindowsForApp(pid: item.app.processIdentifier)
            if windows.isEmpty {
                self.hidePreviewNow()
            } else {
                // Force re-show by clearing bundleId so it doesn't short-circuit
                self.lastHoveredBundleId = nil
                self.showPreview(for: item)
            }
        }
    }

    func start() {
        guard !isEnabled else { return }
        isEnabled = true
        setupDockObserver()
        startHealthCheck()
        startMouseMonitor()
    }

    func stop() {
        isEnabled = false
        teardown()
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        dismissPollTimer?.invalidate()
        dismissPollTimer = nil
        stopMouseMonitor()
        hidePreviewNow()
    }

    // MARK: - AX Observer Setup

    private func setupDockObserver() {
        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return }
        guard AXIsProcessTrusted() else { return }

        let pid = dockApp.processIdentifier
        dockPID = pid

        let dockElement = AXUIElementCreateApplication(pid)

        // Find the dock list element
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return }

        var dockList: AXUIElement?
        for child in children {
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef)
            if let role = roleRef as? String, role == kAXListRole as String {
                dockList = child
                break
            }
        }

        guard let list = dockList else { return }

        var observer: AXObserver?
        guard AXObserverCreate(pid, dockSelectionChangedCallback, &observer) == .success,
              let obs = observer else { return }

        let result = AXObserverAddNotification(obs, list, kAXSelectedChildrenChangedNotification as CFString, nil)
        guard result == .success else { return }

        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .commonModes)
        axObserver = obs
        subscribedDockList = list
    }

    private func teardown() {
        if let obs = axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .commonModes)
        }
        axObserver = nil
        dockPID = nil
        subscribedDockList = nil
    }

    private func startHealthCheck() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.performHealthCheck()
        }
    }

    private func performHealthCheck() {
        guard let pid = dockPID else {
            setupDockObserver()
            return
        }

        let currentDock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        if currentDock?.processIdentifier != pid {
            teardown()
            setupDockObserver()
            return
        }

        if let element = subscribedDockList {
            var roleRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
            if result == .invalidUIElement || result == .cannotComplete {
                teardown()
                setupDockObserver()
            }
        }
    }

    // MARK: - Mouse Monitor (for dismiss when cursor leaves dock area)

    private func startMouseMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged]) { [weak self] _ in
            self?.checkMousePosition()
        }
    }

    private func stopMouseMonitor() {
        if let m = mouseMonitor {
            NSEvent.removeMonitor(m)
            mouseMonitor = nil
        }
    }

    private func startDismissPoll() {
        dismissPollTimer?.invalidate()
        dismissPollTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.checkMousePosition()
        }
    }

    private func stopDismissPoll() {
        dismissPollTimer?.invalidate()
        dismissPollTimer = nil
    }

    private func checkMousePosition() {
        guard let panel = previewPanel, panel.isVisible else {
            stopDismissPoll()
            return
        }

        // Grace period: don't dismiss within 0.4s of showing
        if CACurrentMediaTime() - showTime < 0.4 { return }

        let mouse = NSEvent.mouseLocation

        // Check if mouse is inside the panel (with small tolerance)
        let panelFrame = panel.frame.insetBy(dx: -6, dy: -6)
        if panelFrame.contains(mouse) {
            cancelHide()
            return
        }

        // Check if mouse is still in the dock area (broad check)
        let dockPos = DockPosition.current()
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main {
            if isMouseInDockArea(mouse: mouse, screen: screen, dockPosition: dockPos) {
                // In dock area — don't dismiss (AX will tell us if a different item is hovered)
                return
            }
        }

        // Check if mouse is in the bridge zone between panel and dock icon
        let iconFrame = lastDockItemFrameNS.insetBy(dx: -4, dy: -4)
        let bridgeRect = panelFrame.union(iconFrame)
        if bridgeRect.contains(mouse) {
            cancelHide()
            return
        }

        // Mouse is outside everything — dismiss
        hidePreviewNow()
    }

    private func isMouseInDockArea(mouse: NSPoint, screen: NSScreen, dockPosition: DockPosition) -> Bool {
        let dockSize = DockPosition.dockSize()
        guard dockSize > 0 else { return false }
        let margin: CGFloat = 8

        switch dockPosition {
        case .bottom, .unknown:
            return mouse.y <= screen.frame.minY + dockSize + margin
        case .left:
            return mouse.x <= screen.frame.minX + dockSize + margin
        case .right:
            return mouse.x >= screen.frame.maxX - dockSize - margin
        }
    }

    // MARK: - Dock Item Changed Callback

    func handleDockItemChanged() {
        guard isEnabled else { return }

        guard let itemInfo = getHoveredDockApp() else {
            // No app hovered — use short delay to absorb transient AX "deselect" events
            // during icon-to-icon transitions
            scheduleHide(delay: 0.12)
            return
        }

        // Same app still hovered — just keep it alive
        if lastHoveredBundleId == itemInfo.bundleId,
           previewPanel != nil, previewPanel?.isVisible == true {
            cancelHide()
            return
        }

        // Verify mouse is still in the dock area before showing
        let mouse = NSEvent.mouseLocation
        let dockPos = DockPosition.current()
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main {
            if !isMouseInDockArea(mouse: mouse, screen: screen, dockPosition: dockPos) {
                // AX notification arrived late — mouse already left dock
                return
            }
        }

        lastHoveredBundleId = itemInfo.bundleId
        cancelHide()
        showPreview(for: itemInfo)
    }

    // MARK: - Get Hovered Dock Item

    private func getHoveredDockApp() -> DockItemInfo? {
        guard let pid = dockPID else { return nil }

        let dockElement = AXUIElementCreateApplication(pid)

        var dockItemsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockElement, kAXChildrenAttribute as CFString, &dockItemsRef) == .success,
              let dockItems = dockItemsRef as? [AXUIElement],
              let firstList = dockItems.first else { return nil }

        var selectedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(firstList, kAXSelectedChildrenAttribute as CFString, &selectedRef) == .success,
              let selected = selectedRef as? [AXUIElement],
              let hoveredItem = selected.first else { return nil }

        var subroleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(hoveredItem, kAXSubroleAttribute as CFString, &subroleRef)
        guard let subrole = subroleRef as? String, subrole == "AXApplicationDockItem" else { return nil }

        var urlRef: CFTypeRef?
        AXUIElementCopyAttributeValue(hoveredItem, kAXURLAttribute as CFString, &urlRef)
        guard let url = (urlRef as? URL) ?? (urlRef as? NSURL)?.absoluteURL,
              let bundle = Bundle(url: url),
              let bundleId = bundle.bundleIdentifier else { return nil }

        guard let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else { return nil }

        return DockItemInfo(app: runningApp, dockItemElement: hoveredItem, bundleId: bundleId)
    }

    // MARK: - Show/Hide Preview

    private func showPreview(for item: DockItemInfo) {
        lastShownItem = item
        let dockItemFrameAX = getDockItemFrame(item.dockItemElement)
        let dockPos = DockPosition.current()

        // Convert AX frame (top-left origin) to NS frame (bottom-left origin) for dismiss checks
        if let screen = NSScreen.main {
            let screenH = screen.frame.height
            lastDockItemFrameNS = CGRect(
                x: dockItemFrameAX.origin.x,
                y: screenH - dockItemFrameAX.maxY,
                width: dockItemFrameAX.width,
                height: dockItemFrameAX.height
            )
        }

        let windows = AppDiscoveryService.shared.getWindowsForApp(pid: item.app.processIdentifier)

        let appIcon = item.app.icon ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) ?? NSImage()
        appIcon.size = NSSize(width: 32, height: 32)
        let appName = item.app.localizedName ?? "Unknown"

        // Record show time for grace period
        showTime = CACurrentMediaTime()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let panel = self.previewPanel ?? DockPeekPanel()
            self.previewPanel = panel

            panel.showPreview(
                windows: windows,
                appIcon: appIcon,
                appName: appName,
                bundleId: item.bundleId,
                dockItemFrame: dockItemFrameAX,
                dockPosition: dockPos
            )

            // Start dismiss poll AFTER panel is configured
            self.startDismissPoll()
        }
    }

    private func getDockItemFrame(_ element: AXUIElement) -> CGRect {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?

        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)

        var pos = CGPoint.zero
        var size = CGSize.zero

        if let pv = posRef, CFGetTypeID(pv) == AXValueGetTypeID() {
            AXValueGetValue(pv as! AXValue, .cgPoint, &pos)
        }
        if let sv = sizeRef, CFGetTypeID(sv) == AXValueGetTypeID() {
            AXValueGetValue(sv as! AXValue, .cgSize, &size)
        }

        return CGRect(origin: pos, size: size)
    }

    // MARK: - Hide Timer

    private func scheduleHide(delay: TimeInterval = 0.15) {
        guard hideWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.hidePreviewNow()
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelHide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    private func hidePreviewNow() {
        lastHoveredBundleId = nil
        lastShownItem = nil
        lastDockItemFrameNS = .zero
        hideWorkItem?.cancel()
        hideWorkItem = nil
        stopDismissPoll()
        previewPanel?.hidePreview()
    }
}
