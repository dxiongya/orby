import SwiftUI

// Speed-independent animations (kept as module-level constants)
private let softSpring = Animation.spring(response: 0.2, dampingFraction: 0.75)
private let quickSpring = Animation.spring(response: 0.18, dampingFraction: 0.7)
private let collapseAnim = Animation.easeOut(duration: 0.12)

/// Non-reactive state for drag reorder — mutations do NOT trigger OrbyView body re-eval.
/// Only the actual reorder swap (which mutates `apps`) triggers a re-render.
private final class DragReorderState {
    var lastReorderTime: CFTimeInterval = 0
    var lastReorderPosition: CGPoint = .zero

    func reset() {
        lastReorderTime = 0
        lastReorderPosition = .zero
    }
}

enum CloseMode: Equatable {
    case none
    case mainApps
    case subApps
}

/// Monitors Option key press/release via local event monitor
private class OptionKeyState: ObservableObject {
    @Published var isHeld = false
    private var monitor: Any?

    deinit {
        if let m = monitor { NSEvent.removeMonitor(m) }
    }

    func startMonitoring() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let option = event.modifierFlags.contains(.option)
            if self?.isHeld != option {
                withAnimation(.easeOut(duration: 0.12)) {
                    self?.isHeld = option
                }
            }
            return event
        }
    }

    func stopMonitoring() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        isHeld = false
    }
}

/// Manages trackpad pinch-to-zoom state via NSEvent monitor (class-based for reference semantics)
private class PreviewZoomState: ObservableObject {
    @Published var zoom: CGFloat = 1.0
    @Published var anchor: UnitPoint = .center

    private var monitor: Any?
    private var accumulated: CGFloat = 0

    func startMonitoring() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
            self?.handleMagnify(event)
            return event
        }
    }

    deinit {
        if let m = monitor { NSEvent.removeMonitor(m) }
    }

    func stopMonitoring() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }

    private func handleMagnify(_ event: NSEvent) {
        if event.phase == .began {
            accumulated = 0
        }
        accumulated += event.magnification

        // Toggle zoom as soon as accumulated pinch crosses threshold
        if accumulated > 0.1 && zoom < 1.5 {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                zoom = 2.5
            }
        } else if accumulated < -0.1 && zoom > 1.5 {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                zoom = 1.0
            }
        }
    }

    func reset() {
        zoom = 1.0
        anchor = .center
        accumulated = 0
    }
}

/// NSMenuItem subclass that stores an action closure for menu item callbacks
private class ClosureMenuItem: NSMenuItem {
    var handler: (() -> Void)?

    convenience init(title: String, closure: @escaping () -> Void) {
        self.init(title: title, action: #selector(performClosure), keyEquivalent: "")
        self.target = self
        self.handler = closure
    }

    @objc func performClosure() { handler?() }
}

struct OrbyView: View {
    @Binding var isVisible: Bool

    @ObservedObject private var tagManager = TagManager.shared
    @ObservedObject private var quickLaunch = QuickLaunchManager.shared

    @State private var center: CGPoint = CGPoint(x: -1, y: -1)
    @State private var apps: [AppItem] = []
    @State private var mousePos: CGPoint = .zero
    @State private var hoveredAppIndex: Int?
    @State private var expandedAppIndex: Int?
    @State private var hoveredSubAppIndex: Int?
    @State private var pushOffsets: [CGPoint] = []
    @State private var appeared = false
    @State private var staggerFlags: [Bool] = []
    @State private var previewImage: NSImage?
    @State private var previewPosition: CGPoint = .zero
    @State private var hoverTimer: DispatchWorkItem?
    @State private var previewForWindowId: Int = -1
    @State private var previewFrame: CGRect = .zero
    @State private var subAppStaggerFlags: [Bool] = []
    @State private var isHoveringPreview = false
    @State private var previewTitle: String = ""
    @State private var previewDismissWorkItem: DispatchWorkItem?
    @StateObject private var zoomState = PreviewZoomState()
    @State private var switchWorkItem: DispatchWorkItem?
    @State private var safeBounds: CGRect = .zero
    @State private var rightClickMonitor: Any?

    // Inline tag input state
    @State private var inlineTagKey: String?
    @State private var inlineTagPosition: CGPoint = .zero
    @State private var inlineTagText: String = ""
    @FocusState private var inlineTagFocused: Bool

    // Close mode state
    @State private var closeMode: CloseMode = .none
    @State private var longPressWorkItem: DispatchWorkItem?
    @State private var longPressStartPos: CGPoint?
    @State private var longPressTriggered = false
    @State private var isDragging = false

    // Option key state for showing all sub-app labels
    @StateObject private var optionKey = OptionKeyState()

    // Keyboard mode state
    @ObservedObject private var settings = SettingsManager.shared

    // Speed-scaled entrance animations
    private var jellySpring: Animation {
        .spring(response: 0.32 / settings.mainAppSpeed, dampingFraction: 0.68)
    }
    private var subAppSpring: Animation {
        .spring(response: 0.35 / settings.subAppSpeed, dampingFraction: 0.5)
    }

    @State private var kbFocusedApp: Int = 0
    @State private var kbFocusedSub: Int = 0
    @State private var kbInSubMode: Bool = false
    private var isKBMode: Bool { settings.keyboardMode }

    // Sub-app drag reorder state
    @State private var subAppDragIndex: Int? = nil
    @State private var subAppReorderActive: Bool = false
    @State private var subAppDragPosition: CGPoint = .zero   // ghost cursor position
    @State private var subAppDragOriginalIndex: Int? = nil   // original index before reorder
    @State private var closeModeWorkItem: DispatchWorkItem?
    @State private var lastReorderFromIdx: Int? = nil        // anti-oscillation: don't reverse
    @State private var reorderState = DragReorderState()     // non-reactive throttle state


    var body: some View {
        GeometryReader { geo in
            ZStack {
                backgroundLayer

                if center.x >= 0 && appeared {
                    connectionLines()
                    subAppConnectionLines()
                    dragConnectionLine()
                    mainAppBubbles()
                    subAppBubbles()
                    dragGhostBubble()
                    subAppLabels()
                    windowPreview()
                    closeModeHint()
                    closeButton()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear {
                computeCenter(geoSize: geo.size)
            }
        }
        .ignoresSafeArea()
        .onContinuousHover { phase in
            if case .active(let loc) = phase { handleMouseMove(loc) }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if inlineTagKey != nil && isClickOnInlineTag(value.location) { return }
                    if !isDragging {
                        // First press — use startLocation (where finger first touched),
                        // NOT value.location which may have already moved if user is fast
                        isDragging = true
                        longPressStartPos = value.startLocation
                        if closeMode == .none && !isMouseOverPreview(value.startLocation) {
                            startLongPressDetection(at: value.startLocation)
                        }
                    } else if let start = longPressStartPos {
                        handleMouseMove(value.location)
                        let dx = value.location.x - start.x
                        let dy = value.location.y - start.y
                        let moved = sqrt(dx * dx + dy * dy)

                        if moved > 2 {
                            // Check if we should enter reorder mode
                            if subAppDragIndex != nil && !subAppReorderActive {
                                subAppReorderActive = true
                                lastReorderFromIdx = nil
                                subAppDragOriginalIndex = subAppDragIndex
                                subAppDragPosition = value.location
                                closeModeWorkItem?.cancel()
                                closeModeWorkItem = nil
                                longPressTriggered = true // prevent tap on release
                                clearPreviewNow()
                            } else if subAppDragIndex == nil {
                                cancelLongPress()
                            }
                        }
                    }

                    // Handle active drag reorder — free position tracking + slot detection
                    if subAppReorderActive, let dragIdx = subAppDragIndex,
                       let expIdx = expandedAppIndex, expIdx < apps.count {
                        subAppDragPosition = value.location  // ghost tracks at native frame rate
                        // Reorder detection at ~20Hz — non-reactive state, no body re-eval
                        let now = CACurrentMediaTime()
                        if now - reorderState.lastReorderTime >= 0.05 {
                            reorderState.lastReorderTime = now
                            handleSubAppDrag(at: value.location, dragIdx: dragIdx, appIdx: expIdx)
                        }
                    }
                }
                .onEnded { value in
                    isDragging = false

                    // Finish drag reorder — accept current order as-is
                    if subAppReorderActive, let expIdx = expandedAppIndex, expIdx < apps.count {
                        SubAppOrderManager.shared.saveOrder(
                            bundleId: apps[expIdx].id,
                            windows: apps[expIdx].windows
                        )
                    }
                    subAppDragIndex = nil
                    subAppReorderActive = false
                    subAppDragOriginalIndex = nil
                    lastReorderFromIdx = nil
                    reorderState.reset()
                    cancelLongPress()

                    if longPressTriggered {
                        longPressTriggered = false
                        return
                    }

                    // If clicking on the inline tag input, don't process as a regular click
                    if inlineTagKey != nil && isClickOnInlineTag(value.location) { return }

                    if closeMode != .none {
                        handleCloseModeTap(at: value.location)
                    } else {
                        handleClick(at: value.location)
                    }
                }
        )
        .overlay {
            if center.x >= 0 && appeared {
                inlineTagInput()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .escapePressed)) { _ in
            if inlineTagKey != nil {
                dismissInlineTag()
            } else if closeMode != .none {
                withAnimation(quickSpring) { closeMode = .none }
            } else if isKBMode && kbInSubMode {
                // Keyboard mode: Esc in sub-window mode → back to main apps
                withAnimation(quickSpring) {
                    kbInSubMode = false
                    collapseSubApps()
                }
            } else {
                dismiss()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .orbyKeyDown)) { notification in
            guard let event = notification.object as? NSEvent else { return }
            handleKeyboardNavigation(event)
        }
    }

    // MARK: - Keyboard Navigation

    private func handleKeyboardNavigation(_ event: NSEvent) {
        guard isKBMode, appeared, !apps.isEmpty else { return }

        let keyCode = event.keyCode
        let hasShift = event.modifierFlags.contains(.shift)

        switch keyCode {
        case 123: // Left arrow
            if hasShift && kbInSubMode {
                kbReorderSub(direction: -1)
            } else {
                kbMoveLeft()
            }
        case 124: // Right arrow
            if hasShift && kbInSubMode {
                kbReorderSub(direction: 1)
            } else {
                kbMoveRight()
            }
        case 49: // Space
            kbActivate()
        case 18...23, 25, 26, 28, 29: // Number keys 1-6 (keyCodes: 18=1, 19=2, 20=3, 21=4, 23=5, 22=6)
            let numMap: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6]
            if let num = numMap[keyCode] {
                kbActivateShortcut(num)
            }
        default:
            break
        }
    }

    private func kbMoveLeft() {
        withAnimation(quickSpring) {
            if kbInSubMode {
                guard let idx = expandedAppIndex, idx < apps.count else { return }
                let count = apps[idx].windows.count
                guard count > 0 else { return }
                kbFocusedSub = (kbFocusedSub - 1 + count) % count
                hoveredSubAppIndex = kbFocusedSub
            } else {
                guard !apps.isEmpty else { return }
                kbFocusedApp = (kbFocusedApp - 1 + apps.count) % apps.count
                hoveredAppIndex = kbFocusedApp
                recalcPushOffsets()
            }
        }
    }

    private func kbMoveRight() {
        withAnimation(quickSpring) {
            if kbInSubMode {
                guard let idx = expandedAppIndex, idx < apps.count else { return }
                let count = apps[idx].windows.count
                guard count > 0 else { return }
                kbFocusedSub = (kbFocusedSub + 1) % count
                hoveredSubAppIndex = kbFocusedSub
            } else {
                guard !apps.isEmpty else { return }
                kbFocusedApp = (kbFocusedApp + 1) % apps.count
                hoveredAppIndex = kbFocusedApp
                recalcPushOffsets()
            }
        }
    }

    private func kbActivate() {
        if kbInSubMode {
            // Activate focused sub-window
            guard let idx = expandedAppIndex, idx < apps.count,
                  kbFocusedSub < apps[idx].windows.count else { return }
            AppDiscoveryService.shared.activateWindow(apps[idx].windows[kbFocusedSub])
            dismiss()
        } else {
            guard kbFocusedApp < apps.count else { return }
            let app = apps[kbFocusedApp]
            if app.windows.count <= 1 {
                // Single window — activate directly
                if app.windows.count == 1 {
                    AppDiscoveryService.shared.activateWindow(app.windows[0])
                } else {
                    AppDiscoveryService.shared.activateApp(app)
                }
                dismiss()
            } else {
                // Multi-window — expand sub-windows
                withAnimation(quickSpring) {
                    switchExpandedApp(to: kbFocusedApp)
                    kbInSubMode = true
                    kbFocusedSub = 0
                    hoveredSubAppIndex = 0
                }
            }
        }
    }

    private func kbActivateShortcut(_ num: Int) {
        if kbInSubMode {
            // In sub-window mode: numbers map to sub-windows relative to focused
            guard let idx = expandedAppIndex, idx < apps.count else { return }
            let count = apps[idx].windows.count
            guard count > 0 else { return }
            let targetIdx = kbNeighborSub(num: num, focused: kbFocusedSub, count: count)
            guard let target = targetIdx, target < count else { return }
            AppDiscoveryService.shared.activateWindow(apps[idx].windows[target])
            dismiss()
        } else {
            // In main app mode: numbers map to apps around focused
            let targetIdx = kbNeighborApp(num: num, focused: kbFocusedApp, count: apps.count)
            guard let target = targetIdx, target < apps.count else { return }
            let app = apps[target]
            if app.windows.count <= 1 {
                if app.windows.count == 1 {
                    AppDiscoveryService.shared.activateWindow(app.windows[0])
                } else {
                    AppDiscoveryService.shared.activateApp(app)
                }
                dismiss()
            } else {
                withAnimation(quickSpring) {
                    kbFocusedApp = target
                    hoveredAppIndex = target
                    switchExpandedApp(to: target)
                    kbInSubMode = true
                    kbFocusedSub = 0
                    hoveredSubAppIndex = 0
                }
            }
        }
    }

    /// Map number 1-6 to neighbor index around the focused app.
    /// 1,2,3 = left neighbors (closest to farthest), 4,5,6 = right neighbors
    private func kbNeighborApp(num: Int, focused: Int, count: Int) -> Int? {
        guard count > 1 else { return nil }
        let offset: Int
        if num <= 3 {
            offset = -num // 1→-1, 2→-2, 3→-3
        } else {
            offset = num - 3 // 4→+1, 5→+2, 6→+3
        }
        let target = (focused + offset + count) % count
        return target == focused ? nil : target
    }

    /// Map number 1-6 to neighbor sub-window around focused sub-window.
    private func kbNeighborSub(num: Int, focused: Int, count: Int) -> Int? {
        guard count > 1 else { return nil }
        let offset: Int
        if num <= 3 {
            offset = -num
        } else {
            offset = num - 3
        }
        let target = (focused + offset + count) % count
        return target == focused ? nil : target
    }

    /// Return the keyboard shortcut label for a main app at index `i`, or nil.
    private func kbShortcutForApp(at i: Int) -> String? {
        guard isKBMode, !kbInSubMode, !apps.isEmpty else { return nil }
        if i == kbFocusedApp { return "␣" } // Space key label for focused
        let count = apps.count
        // Check left neighbors: 1,2,3
        for n in 1...min(3, count - 1) {
            if (kbFocusedApp - n + count) % count == i { return "\(n)" }
        }
        // Check right neighbors: 4,5,6
        for n in 1...min(3, count - 1) {
            if (kbFocusedApp + n) % count == i { return "\(n + 3)" }
        }
        return nil
    }

    /// Return the keyboard shortcut label for a sub-window at index `wIdx`, or nil.
    private func kbShortcutForSub(at wIdx: Int) -> String? {
        guard isKBMode, kbInSubMode,
              let idx = expandedAppIndex, idx < apps.count else { return nil }
        let count = apps[idx].windows.count
        if wIdx == kbFocusedSub { return "␣" }
        for n in 1...min(3, count - 1) {
            if (kbFocusedSub - n + count) % count == wIdx { return "\(n)" }
        }
        for n in 1...min(3, count - 1) {
            if (kbFocusedSub + n) % count == wIdx { return "\(n + 3)" }
        }
        return nil
    }

    // MARK: - Long Press Detection

    private func startLongPressDetection(at location: CGPoint) {
        longPressWorkItem?.cancel()
        closeModeWorkItem?.cancel()

        // Immediately detect if press is on a sub-app (for drag reorder on move)
        if let idx = expandedAppIndex, idx < apps.count,
           let subIdx = CircularLayoutEngine.findClosestSubApp(
               to: location, in: apps[idx].windows,
               threshold: CircularLayoutEngine.subBubbleRadius + 18
           ) {
            subAppDragIndex = subIdx
            // Schedule close mode at 0.8s (cancelled if drag starts)
            let closeWork = DispatchWorkItem { [self] in
                guard appeared, !subAppReorderActive else { return }
                subAppDragIndex = nil
                enterCloseMode(.subApps)
            }
            closeModeWorkItem = closeWork
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: closeWork)
            return
        }

        // Main apps — close mode at 0.8s
        let work = DispatchWorkItem { [self] in
            guard appeared else { return }
            let effectiveR = CircularLayoutEngine.effectiveBubbleRadius(for: apps.count)
            if let _ = CircularLayoutEngine.findClosestApp(
                to: location, in: apps, offsets: pushOffsets, threshold: effectiveR + 20
            ) {
                enterCloseMode(.mainApps)
            }
        }
        longPressWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func cancelLongPress() {
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
        closeModeWorkItem?.cancel()
        closeModeWorkItem = nil
        longPressStartPos = nil
    }

    private func enterCloseMode(_ mode: CloseMode) {
        longPressTriggered = true
        withAnimation(quickSpring) {
            closeMode = mode
            if mode == .mainApps {
                // Collapse sub-apps — close mode is for main apps only
                expandedAppIndex = nil
                hoveredSubAppIndex = nil
                recalcPushOffsets()
                subAppStaggerFlags = []
                clearPreviewNow()
            }
        }
    }

    // MARK: - Close Mode Tap

    private func handleCloseModeTap(at loc: CGPoint) {
        if closeMode == .mainApps {
            let effectiveR = CircularLayoutEngine.effectiveBubbleRadius(for: apps.count)
            if let idx = CircularLayoutEngine.findClosestApp(
                to: loc, in: apps, offsets: pushOffsets, threshold: effectiveR + 12
            ), apps[idx].isRunning {
                AppDiscoveryService.shared.terminateApp(apps[idx])

                if settings.appSourceMode == .manualEdit {
                    // Manual Edit: keep the bubble but mark as inactive
                    withAnimation(softSpring) {
                        apps[idx].isRunning = false
                        apps[idx].windows.removeAll()
                        hoveredAppIndex = nil
                    }
                } else {
                    // Running Apps: remove from circle entirely
                    withAnimation(softSpring) {
                        apps.remove(at: idx)
                        if idx < staggerFlags.count { staggerFlags.remove(at: idx) }
                        pushOffsets = Array(repeating: .zero, count: apps.count)
                        hoveredAppIndex = nil
                        CircularLayoutEngine.layoutApps(&apps, center: center, safeBounds: safeBounds)
                    }
                    if apps.isEmpty {
                        closeMode = .none
                        dismiss()
                    }
                }
            }
        } else if closeMode == .subApps {
            if let idx = expandedAppIndex, idx < apps.count,
               let sub = CircularLayoutEngine.findClosestSubApp(
                   to: loc, in: apps[idx].windows,
                   threshold: CircularLayoutEngine.subBubbleRadius + 12
               ) {
                let window = apps[idx].windows[sub]
                AppDiscoveryService.shared.closeWindow(window)
                withAnimation(softSpring) {
                    apps[idx].windows.remove(at: sub)
                    hoveredSubAppIndex = nil
                    if apps[idx].windows.isEmpty {
                        closeMode = .none
                        expandedAppIndex = nil
                        recalcPushOffsets()
                        subAppStaggerFlags = []
                    } else {
                        layoutSubApps(for: idx)
                        subAppStaggerFlags = []
                        animateSubAppEntrance(count: apps[idx].windows.count)
                    }
                }
            }
        }
    }

    // MARK: - Inline Tag Input

    private func inlineTagInput() -> some View {
        Group {
            if inlineTagKey != nil {
                VStack(spacing: 4) {
                    TextField("Tag name...", text: $inlineTagText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .focused($inlineTagFocused)
                        .frame(width: 100)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.65))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                                )
                        )
                        .onSubmit { commitInlineTag() }
                }
                .position(x: inlineTagPosition.x, y: inlineTagPosition.y)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
    }

    private func showInlineTagInput(for key: String) {
        // Find the bubble position for this key
        var pos = center
        // Check if it's a window key (contains "::")
        if key.contains("::") {
            // Sub-app — find position from expanded windows
            if let expIdx = expandedAppIndex, expIdx < apps.count {
                let app = apps[expIdx]
                let bundleId = app.id
                for win in app.windows {
                    if TagManager.key(for: bundleId, windowName: win.name) == key {
                        pos = win.position
                        break
                    }
                }
            }
        } else {
            // Main app — find by bundleId
            for app in apps {
                if app.id == key {
                    pos = app.position
                    break
                }
            }
        }

        inlineTagText = ""
        inlineTagKey = key
        let bubbleR = CircularLayoutEngine.mainBubbleRadius
        inlineTagPosition = CGPoint(x: pos.x, y: pos.y + bubbleR + 28)

        // Delay focus so the overlay view appears first, then grab focus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            inlineTagFocused = true
        }
    }

    private func commitInlineTag() {
        let rawName = inlineTagText.trimmingCharacters(in: .whitespaces)
        let name = String(rawName.prefix(30))
        guard !name.isEmpty, let key = inlineTagKey else {
            dismissInlineTag()
            return
        }
        // Pick color by cycling through available colors
        let colorIdx = tagManager.presetTags.count % AppTag.availableColors.count
        let colorName = AppTag.availableColors[colorIdx]
        let newTag = AppTag(name: name, colorName: colorName)
        tagManager.addPresetTag(newTag)
        tagManager.toggleTag(newTag, for: key)
        dismissInlineTag()
    }

    private func dismissInlineTag() {
        withAnimation(quickSpring) {
            inlineTagKey = nil
            inlineTagText = ""
            inlineTagFocused = false
        }
    }

    // MARK: - Close Mode Hint

    private func closeModeHint() -> some View {
        Group {
            if closeMode != .none {
                Text(closeMode == .mainApps ? "Tap to quit app · ESC to exit" : "Tap to close window · ESC to exit")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.red.opacity(0.55))
                            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                    )
                    .position(x: center.x, y: center.y + 32)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
    }

    // MARK: - Compute Center from mouse

    private func computeCenter(geoSize: CGSize) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        let sf = screen.frame

        let rawX = mouse.x - sf.origin.x
        let rawY = sf.height - (mouse.y - sf.origin.y)

        let vf = screen.visibleFrame
        let w = geoSize.width > 0 ? geoSize.width : sf.width
        let h = geoSize.height > 0 ? geoSize.height : sf.height
        let topInset = sf.maxY - vf.maxY
        let bottomInset = vf.minY - sf.minY
        let leftInset = vf.minX - sf.minX
        let rightInset = sf.maxX - vf.maxX
        safeBounds = CGRect(
            x: leftInset,
            y: topInset,
            width: w - leftInset - rightInset,
            height: h - topInset - bottomInset
        )

        // Keyboard mode: always center on screen
        let cursorPos = isKBMode
            ? CGPoint(x: w / 2, y: h / 2)
            : CGPoint(x: rawX, y: rawY)
        mousePos = cursorPos
        loadApps(around: cursorPos)
        optionKey.startMonitoring()
        if !isKBMode { startRightClickMonitor() }
        withAnimation(jellySpring) { appeared = true }
        animateStaggeredEntrance()

        // Initialize keyboard focus
        if isKBMode {
            kbFocusedApp = 0
            kbInSubMode = false
            recalcPushOffsets()
        }
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        Color.black
            .opacity(appeared ? 0.35 : 0)
            .background(.ultraThinMaterial.opacity(appeared ? 0.4 : 0))
            .ignoresSafeArea()
            .animation(.easeOut(duration: 0.35), value: appeared)
            .onTapGesture { dismiss() }
    }

    // MARK: - Close Button

    private func closeButton() -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.92))
                .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)
                .shadow(color: .white.opacity(0.5), radius: 2, x: 0, y: -1)
                .frame(width: 38, height: 38)
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.black.opacity(0.5))
        }
        .position(x: center.x, y: center.y)
        .scaleEffect(appeared ? 1.0 : 0.01)
        .opacity(appeared ? 1.0 : 0)
        .animation(.spring(response: 0.18, dampingFraction: 0.6), value: appeared)
        .onTapGesture { dismiss() }
    }

    // MARK: - Connection Lines

    private func connectionLines() -> some View {
        Group {
            if closeMode == .none, let i = hoveredAppIndex, i < apps.count {
                let off = offset(for: i)
                ConnectionLineView(
                    from: center,
                    to: CGPoint(x: apps[i].position.x + off.x, y: apps[i].position.y + off.y),
                    lineWidth: 2.0, opacity: 0.35, glowColor: .white
                )
            }
        }
    }

    private func subAppConnectionLines() -> some View {
        Group {
            if closeMode == .none,
               let idx = expandedAppIndex, idx < apps.count,
               let wIdx = hoveredSubAppIndex, wIdx < apps[idx].windows.count {
                let off = offset(for: idx)
                let pp = CGPoint(x: apps[idx].position.x + off.x, y: apps[idx].position.y + off.y)
                ConnectionLineView(
                    from: pp, to: apps[idx].windows[wIdx].position,
                    lineWidth: 1.2, opacity: 0.3, glowColor: Color(white: 0.85)
                )
            }
        }
    }

    // MARK: - Main App Bubbles

    private func mainAppBubbles() -> some View {
        ForEach(apps.indices, id: \.self) { i in
            let vis = staggerFlags.indices.contains(i) ? staggerFlags[i] : false
            // Entrance: fly outward from center
            let flyX = vis ? 0.0 : center.x - apps[i].position.x
            let flyY = vis ? 0.0 : center.y - apps[i].position.y
            AppBubbleView(
                app: apps[i],
                isHovered: hoveredAppIndex == i,
                isExpanded: expandedAppIndex == i,
                dimLevel: dimLevel(for: i),
                offset: offset(for: i),
                isInCloseMode: closeMode == .mainApps,
                tags: tagManager.tags(for: apps[i].id),
                quickSlot: quickLaunch.slot(for: apps[i].id),
                kbFocused: isKBMode && !kbInSubMode && kbFocusedApp == i,
                kbShortcut: kbShortcutForApp(at: i),
                isRunning: apps[i].isRunning
            )
            .zIndex(hoveredAppIndex == i ? 100 : 0)
            .offset(x: flyX, y: flyY)
            .scaleEffect(vis ? 1.0 : 0.35)
            .opacity(vis ? 1.0 : 0)
            .animation(jellySpring.delay(Double(i) * 0.015 / settings.mainAppSpeed), value: vis)
            .onTapGesture {
                if closeMode == .mainApps {
                    handleCloseModeTap(at: apps[i].position)
                } else {
                    tapApp(i)
                }
            }
        }
    }

    // MARK: - Sub App Bubbles

    private func subAppBubbles() -> some View {
        Group {
            if let idx = expandedAppIndex, idx < apps.count {
                // Use enumerated array with window.id as identity — avoids O(n²) firstIndex lookup
                ForEach(Array(apps[idx].windows.enumerated()), id: \.element.id) { wIdx, window in
                    let _ = window // silence unused warning; identity tracked via id
                    let vis = subAppStaggerFlags.indices.contains(wIdx) ? subAppStaggerFlags[wIdx] : false
                    let isDrag = subAppDragIndex == wIdx && subAppReorderActive
                    let isGrab = subAppDragIndex == wIdx && !subAppReorderActive
                    SubAppBubbleView(
                        window: apps[idx].windows[wIdx],
                        parentIcon: apps[idx].icon,
                        isHovered: hoveredSubAppIndex == wIdx,
                        showLabel: false,
                        isInCloseMode: closeMode == .subApps,
                        tags: tagManager.tags(for: TagManager.key(for: apps[idx].id, windowName: apps[idx].windows[wIdx].name)),
                        quickSlot: {
                            let wid = apps[idx].windows[wIdx].cgWindowID
                            return quickLaunch.slot(for: apps[idx].id, cgWindowID: wid > 0 ? wid : nil)
                                ?? quickLaunch.slot(for: apps[idx].id)
                        }(),
                        kbFocused: isKBMode && kbInSubMode && kbFocusedSub == wIdx,
                        kbShortcut: kbShortcutForSub(at: wIdx),
                        isDragging: isDrag,
                        isReorderMode: subAppReorderActive,
                        slotIndex: wIdx,
                        isGrabbed: isGrab
                    )
                    .zIndex(isDrag ? 200 : (hoveredSubAppIndex == wIdx ? 100 : 0))
                    .scaleEffect(vis ? 1.0 : 0.01)
                    .opacity(vis ? 1.0 : 0)
                    .animation(subAppSpring.delay(Double(wIdx) * 0.04 / settings.subAppSpeed), value: vis)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                    .onTapGesture {
                        if closeMode == .subApps {
                            handleCloseModeTap(at: apps[idx].windows[wIdx].position)
                        } else if closeMode == .none && !subAppReorderActive {
                            AppDiscoveryService.shared.activateWindow(apps[idx].windows[wIdx])
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sub-App Labels (rendered above all bubbles)

    /// Separate label layer so tooltip text floats above all sub-app icons.
    private func subAppLabels() -> some View {
        Group {
            if let idx = expandedAppIndex, idx < apps.count,
               hoveredSubAppIndex != nil || optionKey.isHeld {
                ForEach(Array(apps[idx].windows.enumerated()), id: \.element.id) { wIdx, window in
                    let show = hoveredSubAppIndex == wIdx || (optionKey.isHeld && closeMode == .none)
                    let vis = subAppStaggerFlags.indices.contains(wIdx) ? subAppStaggerFlags[wIdx] : false
                    if show && vis {
                        let win = apps[idx].windows[wIdx]
                        let label = SubAppBubbleView.displayName(for: win.name)
                        Text(label)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.95))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.7))
                                    .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
                            )
                            .position(
                                x: win.position.x,
                                y: win.position.y + CircularLayoutEngine.subBubbleRadius + 14
                            )
                            .allowsHitTesting(false)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
            }
        }
        .zIndex(200)
        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: hoveredSubAppIndex)
        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: optionKey.isHeld)
    }

    // MARK: - Window Preview (DockDoor style card)

    private func windowPreview() -> some View {
        Group {
            if closeMode == .none, let img = previewImage {
                let imgW = img.size.width
                let imgH = img.size.height
                let cardW = max(imgW, 160)
                let isZoomed = zoomState.zoom > 1.05

                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Button(action: closePreviewWindow) {
                            ZStack {
                                Circle()
                                    .fill(Color.red.opacity(0.85))
                                    .frame(width: 12, height: 12)
                                Image(systemName: "xmark")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundColor(.white.opacity(isHoveringPreview ? 1 : 0))
                            }
                        }
                        .buttonStyle(.plain)

                        Text(previewTitle)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        // Zoom indicator
                        if isZoomed {
                            Text(String(format: "%.0f%%", zoomState.zoom * 100))
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                    // Zoomable preview image
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(zoomState.zoom, anchor: zoomState.anchor)
                        .frame(width: imgW, height: imgH)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            if case .active(let loc) = phase {
                                let anchor = UnitPoint(
                                    x: max(0, min(1, loc.x / imgW)),
                                    y: max(0, min(1, loc.y / imgH))
                                )
                                if zoomState.zoom > 1.05 {
                                    withAnimation(.easeOut(duration: 0.08)) {
                                        zoomState.anchor = anchor
                                    }
                                } else {
                                    zoomState.anchor = anchor
                                }
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.bottom, 6)
                }
                .frame(width: cardW + 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 10)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(isZoomed ? 0.25 : 0.12), lineWidth: 1)
                )
                .scaleEffect(isHoveringPreview && !isZoomed ? 1.06 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHoveringPreview)
                // contentShape + interactions BEFORE .position() so hit-testing
                // matches the actual card area, not the entire parent frame.
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .onContinuousHover { phase in
                    if case .active = phase {
                        if !isHoveringPreview {
                            isHoveringPreview = true
                            cancelPreviewDismiss()
                            zoomState.startMonitoring()
                        }
                    } else {
                        isHoveringPreview = false
                        zoomState.stopMonitoring()
                        if zoomState.zoom > 1.0 {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                zoomState.zoom = 1.0
                            }
                        }
                        schedulePreviewDismiss()
                    }
                }
                .onTapGesture {
                    if isZoomed {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                            zoomState.zoom = 1.0
                        }
                    } else if let idx = expandedAppIndex, idx < apps.count,
                       let wIdx = hoveredSubAppIndex, wIdx < apps[idx].windows.count {
                        AppDiscoveryService.shared.activateWindow(apps[idx].windows[wIdx])
                        dismiss()
                    } else if let idx = hoveredAppIndex, idx < apps.count,
                              apps[idx].windows.count == 1 {
                        AppDiscoveryService.shared.activateWindow(apps[idx].windows[0])
                        dismiss()
                    }
                }
                .position(x: previewPosition.x, y: previewPosition.y)
                .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
    }

    // MARK: - Preview Dismiss Timer

    /// Schedule delayed preview dismissal (gives mouse time to reach the preview card)
    private func schedulePreviewDismiss() {
        previewDismissWorkItem?.cancel()
        let work = DispatchWorkItem { [self] in
            previewDismissWorkItem = nil
            withAnimation(quickSpring) { clearPreviewNow() }
        }
        previewDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func cancelPreviewDismiss() {
        previewDismissWorkItem?.cancel()
        previewDismissWorkItem = nil
    }

    // MARK: - Logic

    private func loadApps(around pt: CGPoint) {
        var items: [AppItem]

        if settings.appSourceMode == .manualEdit {
            items = loadPinnedApps()
        } else {
            items = AppDiscoveryService.shared.getRunningApps()
        }

        // Apply saved sub-app ordering
        for i in items.indices {
            items[i].windows = SubAppOrderManager.shared.applyOrder(
                bundleId: items[i].id, windows: items[i].windows
            )
        }
        center = pt
        CircularLayoutEngine.layoutApps(&items, center: pt, safeBounds: safeBounds)
        apps = items
        pushOffsets = Array(repeating: .zero, count: items.count)
        staggerFlags = Array(repeating: false, count: items.count)
    }

    /// Load pinned apps for manual edit mode, merging with running app data for windows.
    private func loadPinnedApps() -> [AppItem] {
        let pinned = PinnedAppsManager.shared.pinnedApps
        let runningApps = AppDiscoveryService.shared.getRunningApps()
        let runningByBundleId = Dictionary(runningApps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        return pinned.map { pin in
            if let running = runningByBundleId[pin.bundleId] {
                // App is running — use its full data (icon, windows, pid)
                var app = running
                app.isRunning = true
                return app
            } else {
                // App is not running — create stub with icon from bundle path
                let icon = NSWorkspace.shared.icon(forFile: pin.bundlePath)
                icon.size = NSSize(width: 32, height: 32)
                var app = AppItem(
                    id: pin.bundleId,
                    name: pin.name,
                    icon: icon,
                    pid: 0,
                    bundleURL: URL(fileURLWithPath: pin.bundlePath),
                    windows: []
                )
                app.isRunning = false
                return app
            }
        }
    }

    private func animateSubAppEntrance(count: Int) {
        subAppStaggerFlags = Array(repeating: false, count: count)
        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.04 / settings.subAppSpeed + 0.01) {
                withAnimation(subAppSpring) {
                    if i < subAppStaggerFlags.count { subAppStaggerFlags[i] = true }
                }
            }
        }
    }

    private func animateStaggeredEntrance() {
        // Batch-set all flags in one state update; per-view animation delays
        // (applied via .animation(jellySpring.delay(...), value:)) handle the stagger
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            withAnimation(jellySpring) {
                staggerFlags = Array(repeating: true, count: staggerFlags.count)
            }
        }
    }

    @State private var lastHandledMousePos: CGPoint = .zero

    private func handleMouseMove(_ loc: CGPoint) {
        mousePos = loc

        // Freeze all hover/switch logic when a sub-app is grabbed or being dragged
        if subAppDragIndex != nil || subAppReorderActive { return }

        // Skip if mouse barely moved (< 3pt) — avoids redundant O(n) scans at 60+ Hz
        let mdx = loc.x - lastHandledMousePos.x
        let mdy = loc.y - lastHandledMousePos.y
        if mdx * mdx + mdy * mdy < 9 { return }
        lastHandledMousePos = loc

        // Freeze all hover logic while inline tag input is active
        if inlineTagKey != nil { return }

        // In close mode, simplified hover tracking
        if closeMode == .mainApps {
            let effectiveR = CircularLayoutEngine.effectiveBubbleRadius(for: apps.count)
            let appIdx = CircularLayoutEngine.findClosestApp(
                to: loc, in: apps, offsets: pushOffsets, threshold: effectiveR + 20
            )
            if hoveredAppIndex != appIdx {
                withAnimation(quickSpring) { hoveredAppIndex = appIdx }
            }
            return
        }

        if closeMode == .subApps {
            if let idx = expandedAppIndex, idx < apps.count {
                if let sub = CircularLayoutEngine.findClosestSubApp(
                    to: loc, in: apps[idx].windows,
                    threshold: CircularLayoutEngine.subBubbleRadius + 18
                ) {
                    withAnimation(quickSpring) { hoveredSubAppIndex = sub }
                    return
                }
            }
            withAnimation(quickSpring) { hoveredSubAppIndex = nil }
            return
        }

        // Normal mode — existing logic

        // STEP 1: sub-apps first
        if let idx = expandedAppIndex, idx < apps.count {
            if let sub = CircularLayoutEngine.findClosestSubApp(to: loc, in: apps[idx].windows, threshold: CircularLayoutEngine.subBubbleRadius + 18) {
                let winId = apps[idx].windows[sub].id
                cancelPreviewDismiss()
                withAnimation(quickSpring) { hoveredSubAppIndex = sub; hoveredAppIndex = idx }
                if winId != previewForWindowId {
                    clearPreviewNow()
                    schedulePreview(for: idx, windowIndex: sub, windowId: winId)
                }
                return
            }
        }

        // STEP 2: main apps
        let effectiveR = CircularLayoutEngine.effectiveBubbleRadius(for: apps.count)
        let appIdx = CircularLayoutEngine.findClosestApp(to: loc, in: apps, offsets: pushOffsets, threshold: effectiveR + 20)

        if hoveredAppIndex != appIdx { withAnimation(quickSpring) { hoveredAppIndex = appIdx } }

        // STEP 3: switch/collapse
        if let idx = appIdx, let expanded = expandedAppIndex, idx != expanded {
            if apps[idx].windows.count > 1 {
                switchExpandedApp(to: idx)
            } else {
                collapseSubApps()
            }
            return
        }

        // STEP 4: expand
        if let idx = appIdx, expandedAppIndex == nil, apps[idx].windows.count > 1 {
            switchExpandedApp(to: idx)
            return
        }

        // STEP 4.5: preview for single-window apps (hover main bubble)
        if let idx = appIdx, expandedAppIndex == nil, apps[idx].windows.count == 1 {
            let win = apps[idx].windows[0]
            cancelPreviewDismiss()
            if win.id != previewForWindowId && !win.isMinimized {
                clearPreviewNow()
                let off = offset(for: idx)
                let anchor = CGPoint(x: apps[idx].position.x + off.x, y: apps[idx].position.y + off.y)
                schedulePreview(for: idx, windowIndex: 0, windowId: win.id, anchorOverride: anchor)
            }
            return
        }

        // STEP 5: clear sub hover (keep preview if mouse is on the preview card)
        if expandedAppIndex != nil {
            if isHoveringPreview || isMouseOverPreview(loc) { return }
            withAnimation(quickSpring) { hoveredSubAppIndex = nil }
            if previewImage != nil { schedulePreviewDismiss() }
        }

        // STEP 5b: clear single-window preview when hovering nothing
        if expandedAppIndex == nil && previewImage != nil && appIdx == nil {
            if !isHoveringPreview && !isMouseOverPreview(loc) { schedulePreviewDismiss() }
        }
    }

    private func collapseSubApps() {
        switchWorkItem?.cancel()
        switchWorkItem = nil
        clearPreviewNow()
        withAnimation(collapseAnim) {
            expandedAppIndex = nil
            hoveredSubAppIndex = nil
            recalcPushOffsets()
        }
        subAppStaggerFlags = []
    }

    private func switchExpandedApp(to newIdx: Int) {
        switchWorkItem?.cancel()
        clearPreviewNow()

        if expandedAppIndex != nil {
            withAnimation(collapseAnim) {
                expandedAppIndex = nil
                hoveredSubAppIndex = nil
                recalcPushOffsets()
            }
            subAppStaggerFlags = []

            let work = DispatchWorkItem { [self] in
                guard newIdx < apps.count else { return }
                withAnimation(softSpring) {
                    expandedAppIndex = newIdx
                    hoveredSubAppIndex = nil
                    layoutSubApps(for: newIdx)
                    recalcPushOffsets()
                }
                animateSubAppEntrance(count: apps[newIdx].windows.count)
            }
            switchWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        } else {
            withAnimation(softSpring) {
                expandedAppIndex = newIdx
                hoveredSubAppIndex = nil
                layoutSubApps(for: newIdx)
                recalcPushOffsets()
            }
            animateSubAppEntrance(count: apps[newIdx].windows.count)
        }
    }

    private func schedulePreview(for appIdx: Int, windowIndex wIdx: Int, windowId: Int, anchorOverride: CGPoint? = nil) {
        guard SettingsManager.shared.showPreview else { return }
        hoverTimer?.cancel()
        cancelPreviewDismiss()
        previewForWindowId = windowId

        let delay = SettingsManager.shared.previewDelay
        let work = DispatchWorkItem { [self] in
            guard appIdx < apps.count, wIdx < apps[appIdx].windows.count else { return }
            let win = apps[appIdx].windows[wIdx]
            guard win.id == windowId, !win.isMinimized else { return }
            let captureAnchor = anchorOverride ?? win.position
            let winName = win.name
            // Capture on background thread to avoid blocking UI
            AppDiscoveryService.shared.captureWindowPreviewAsync(cgWindowID: win.cgWindowID) { [self] img in
                guard let img = img else { return }
                guard previewForWindowId == windowId else { return } // stale
                withAnimation(quickSpring) {
                    previewImage = img
                    previewTitle = winName.isEmpty ? "Window" : winName

                    let cardW = max(img.size.width, 160) + 12
                    let cardH = img.size.height + 40
                    let pos = findBestPreviewPosition(
                        anchor: captureAnchor, cardSize: CGSize(width: cardW, height: cardH)
                    )
                    previewPosition = pos
                    previewFrame = CGRect(
                        x: pos.x - cardW / 2, y: pos.y - cardH / 2,
                        width: cardW, height: cardH
                    )
                }
            }
        }
        hoverTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Find the best position for the preview card that avoids overlapping bubbles.
    private func findBestPreviewPosition(anchor: CGPoint, cardSize: CGSize) -> CGPoint {
        let halfW = cardSize.width / 2
        let halfH = cardSize.height / 2
        let margin: CGFloat = 8
        let gap: CGFloat = CircularLayoutEngine.subBubbleRadius + 30

        // Collect all bubble positions & radii to avoid
        var obstacles: [(CGPoint, CGFloat)] = []
        // Center close button
        obstacles.append((center, 22))
        // Main app bubbles
        let mainR = CircularLayoutEngine.mainBubbleRadius
        for (i, app) in apps.enumerated() {
            let off = offset(for: i)
            obstacles.append((
                CGPoint(x: app.position.x + off.x, y: app.position.y + off.y),
                mainR * app.bubbleScale
            ))
        }
        // Sub-app bubbles (only if an app is expanded)
        if let expandedIdx = expandedAppIndex, expandedIdx < apps.count {
            let subR = CircularLayoutEngine.subBubbleRadius
            for w in apps[expandedIdx].windows {
                obstacles.append((w.position, subR))
            }
        }

        // Try 12 directions around the anchor, pick the one with least overlap
        let angles: [Double] = (0..<12).map { Double($0) * (.pi * 2 / 12) }
        // Also try the outward direction from center as first candidate
        let outDx = anchor.x - center.x
        let outDy = anchor.y - center.y
        let outAngle = atan2(outDy, outDx)

        var bestPos = CGPoint.zero
        var bestScore = Double.infinity

        for angle in [outAngle] + angles {
            let dist = max(halfH, halfW) + gap
            var px = anchor.x + cos(angle) * dist
            var py = anchor.y + sin(angle) * dist

            // Clamp to safe bounds
            let minX = safeBounds.minX + halfW + margin
            let maxX = safeBounds.maxX - halfW - margin
            let minY = safeBounds.minY + halfH + margin
            let maxY = safeBounds.maxY - halfH - margin
            px = min(max(px, minX), maxX)
            py = min(max(py, minY), maxY)

            let cardRect = CGRect(x: px - halfW, y: py - halfH,
                                  width: cardSize.width, height: cardSize.height)

            // Score: sum of overlap with each obstacle
            var score: Double = 0
            for (obPos, obR) in obstacles {
                let obRect = CGRect(x: obPos.x - obR, y: obPos.y - obR,
                                    width: obR * 2, height: obR * 2)
                let intersection = cardRect.intersection(obRect)
                if !intersection.isNull {
                    score += Double(intersection.width * intersection.height)
                }
            }

            if score < bestScore {
                bestScore = score
                bestPos = CGPoint(x: px, y: py)
                if score == 0 { break } // Perfect — no overlap at all
            }
        }

        return bestPos
    }

    private func isMouseOverPreview(_ loc: CGPoint) -> Bool {
        guard previewImage != nil else { return false }
        return previewFrame.insetBy(dx: -8, dy: -8).contains(loc)
    }

    private func clearPreviewNow() {
        hoverTimer?.cancel()
        hoverTimer = nil
        cancelPreviewDismiss()
        previewForWindowId = -1
        previewImage = nil
        previewTitle = ""
        isHoveringPreview = false
        previewFrame = .zero
        zoomState.stopMonitoring()
        zoomState.reset()
    }

    private func closePreviewWindow() {
        guard let idx = expandedAppIndex, idx < apps.count,
              let wIdx = hoveredSubAppIndex, wIdx < apps[idx].windows.count else { return }
        let window = apps[idx].windows[wIdx]
        AppDiscoveryService.shared.closeWindow(window)
        clearPreviewNow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            subAppStaggerFlags = []
            withAnimation(softSpring) {
                expandedAppIndex = nil; hoveredSubAppIndex = nil; recalcPushOffsets()
            }
            loadApps(around: center)
            animateStaggeredEntrance()
        }
    }

    private func isClickOnInlineTag(_ loc: CGPoint) -> Bool {
        guard inlineTagKey != nil else { return false }
        let tagRect = CGRect(
            x: inlineTagPosition.x - 65,
            y: inlineTagPosition.y - 20,
            width: 130,
            height: 40
        )
        return tagRect.contains(loc)
    }

    private func handleClick(at loc: CGPoint) {
        if inlineTagKey != nil {
            // If clicking on the tag input itself, let it handle focus
            if isClickOnInlineTag(loc) { return }
            // Clicking elsewhere dismisses the tag input
            dismissInlineTag()
            return
        }
        let dx = loc.x - center.x, dy = loc.y - center.y
        if sqrt(dx*dx + dy*dy) < 22 { dismiss(); return }

        // Click on preview card — let its own tap handler deal with it
        if previewImage != nil && isMouseOverPreview(loc) { return }

        // Click on a sub-app bubble — activate that window
        if let idx = expandedAppIndex, idx < apps.count,
           let sub = CircularLayoutEngine.findClosestSubApp(to: loc, in: apps[idx].windows, threshold: CircularLayoutEngine.subBubbleRadius + 12) {
            AppDiscoveryService.shared.activateWindow(apps[idx].windows[sub]); dismiss(); return
        }

        // Click on a main app bubble
        let clickR = CircularLayoutEngine.effectiveBubbleRadius(for: apps.count)
        if let idx = CircularLayoutEngine.findClosestApp(to: loc, in: apps, offsets: pushOffsets, threshold: clickR + 12) {
            // Non-running app (manual edit mode) — launch it
            if !apps[idx].isRunning {
                if let url = apps[idx].bundleURL {
                    NSWorkspace.shared.open(url)
                }
                dismiss()
                return
            }
            if apps[idx].windows.count <= 1 {
                // Single window — activate and dismiss
                if apps[idx].windows.count == 1 {
                    AppDiscoveryService.shared.activateWindow(apps[idx].windows[0])
                } else {
                    AppDiscoveryService.shared.activateApp(apps[idx])
                }
                dismiss()
            } else if expandedAppIndex == idx {
                // Clicking the already-expanded app — collapse it
                collapseSubApps()
            } else {
                // Clicking a different multi-window app — switch to it
                switchExpandedApp(to: idx)
            }
            return
        }

        // Clicked empty area — collapse expanded app or dismiss overlay
        clearPreviewNow()
        if expandedAppIndex != nil {
            collapseSubApps()
        } else {
            dismiss()
        }
    }

    private func tapApp(_ i: Int) {
        guard closeMode == .none else { return }
        // Non-running app (manual edit mode) — launch it
        if !apps[i].isRunning {
            if let url = apps[i].bundleURL {
                NSWorkspace.shared.open(url)
            }
            dismiss()
            return
        }
        if apps[i].windows.count <= 1 {
            if apps[i].windows.count == 1 {
                AppDiscoveryService.shared.activateWindow(apps[i].windows[0])
            } else {
                AppDiscoveryService.shared.activateApp(apps[i])
            }
            dismiss()
        } else if expandedAppIndex == i {
            collapseSubApps()
        } else {
            switchExpandedApp(to: i)
        }
    }

    private func dimLevel(for i: Int) -> Double {
        guard let e = expandedAppIndex else { return 0 }
        return i == e ? 0 : (hoveredSubAppIndex != nil ? 0.7 : 0.4)
    }

    private func offset(for i: Int) -> CGPoint { pushOffsets.indices.contains(i) ? pushOffsets[i] : .zero }

    private func layoutSubApps(for i: Int) {
        guard i < apps.count else { return }
        var w = apps[i].windows
        CircularLayoutEngine.layoutSubApps(
            &w,
            parentPosition: apps[i].position,
            parentAngle: apps[i].angle,
            center: center,
            safeBounds: safeBounds,
            clockwise: settings.subAppSortClockwise
        )
        apps[i].windows = w
    }

    // MARK: - Drag Connection Line & Ghost Bubble

    private func dragConnectionLine() -> some View {
        Group {
            if subAppReorderActive,
               let idx = expandedAppIndex, idx < apps.count {
                let off = offset(for: idx)
                let pp = CGPoint(x: apps[idx].position.x + off.x, y: apps[idx].position.y + off.y)
                ConnectionLineView(
                    from: pp, to: subAppDragPosition,
                    lineWidth: 1.5, opacity: 0.5, glowColor: .blue
                )
            }
        }
        .zIndex(90)
    }

    private func dragGhostBubble() -> some View {
        Group {
            if subAppReorderActive,
               let dragIdx = subAppDragIndex,
               let idx = expandedAppIndex, idx < apps.count,
               dragIdx < apps[idx].windows.count {
                let win = apps[idx].windows[dragIdx]
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .shadow(color: .blue.opacity(0.3), radius: 16, x: 0, y: 4)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.blue.opacity(0.6), lineWidth: 2.5)
                        )

                    Image(nsImage: apps[idx].icon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)

                    if win.isMinimized {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .gray.opacity(0.7))
                            .offset(x: 16, y: 16)
                    }
                }
                .frame(width: CircularLayoutEngine.subBubbleRadius * 2,
                       height: CircularLayoutEngine.subBubbleRadius * 2)
                .overlay(alignment: .bottom) {
                    Text(SubAppBubbleView.displayName(for: win.name))
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 60)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule()
                                .fill(Color(white: 0.2).opacity(0.75))
                                .shadow(color: .black.opacity(0.3), radius: 1.5)
                        )
                        .offset(y: -2)
                }
                .scaleEffect(1.15)
                .opacity(0.9)
                .animation(nil, value: subAppDragPosition)
                .position(x: subAppDragPosition.x, y: subAppDragPosition.y)
                .allowsHitTesting(false)
                .zIndex(300)
            }
        }
    }

    // MARK: - Sub-App Drag Reorder

    private func handleSubAppDrag(at loc: CGPoint, dragIdx: Int, appIdx: Int) {
        let windows = apps[appIdx].windows
        let count = windows.count
        guard count > 1 else { return }

        // Skip if cursor barely moved since last evaluation (4pt threshold)
        let mdx = loc.x - reorderState.lastReorderPosition.x
        let mdy = loc.y - reorderState.lastReorderPosition.y
        guard mdx * mdx + mdy * mdy >= 16 else { return }
        reorderState.lastReorderPosition = loc

        // Find which slot the cursor is closest to (by Euclidean distance)
        var bestIdx = -1
        var bestDist = CGFloat.greatestFiniteMagnitude
        for i in 0..<count where i != dragIdx {
            let dx = loc.x - windows[i].position.x
            let dy = loc.y - windows[i].position.y
            let d = sqrt(dx * dx + dy * dy)
            if d < bestDist { bestDist = d; bestIdx = i }
        }

        guard bestIdx >= 0, bestIdx != dragIdx else { return }

        // Only trigger when cursor actually overlaps with the target bubble
        let triggerRadius = CircularLayoutEngine.subBubbleRadius * 1.4
        guard bestDist < triggerRadius else { return }

        // Anti-oscillation: don't reverse back to the position we just came from
        let insertIdx = bestIdx
        if insertIdx == lastReorderFromIdx { return }

        // Insert semantics: remove → insert, all elements between shift
        let fromIdx = dragIdx
        withAnimation(softSpring) {
            let window = apps[appIdx].windows.remove(at: dragIdx)
            apps[appIdx].windows.insert(window, at: insertIdx)
            subAppDragIndex = insertIdx
            lastReorderFromIdx = fromIdx
            layoutSubApps(for: appIdx)
        }
    }

    // MARK: - Keyboard Reorder

    private func kbReorderSub(direction: Int) {
        guard kbInSubMode, let idx = expandedAppIndex, idx < apps.count else { return }
        let count = apps[idx].windows.count
        guard count > 1, kbFocusedSub >= 0, kbFocusedSub < count else { return }

        let targetIdx = (kbFocusedSub + direction + count) % count
        withAnimation(quickSpring) {
            let window = apps[idx].windows.remove(at: kbFocusedSub)
            apps[idx].windows.insert(window, at: targetIdx)
            kbFocusedSub = targetIdx
            hoveredSubAppIndex = targetIdx
            layoutSubApps(for: idx)
        }
        SubAppOrderManager.shared.saveOrder(
            bundleId: apps[idx].id,
            windows: apps[idx].windows
        )
    }

    private func recalcPushOffsets() {
        if let idx = expandedAppIndex {
            var offsets = CircularLayoutEngine.calculatePushOffsets(apps: apps, expandedIndex: idx, center: center)
            CircularLayoutEngine.clampPushOffsets(&offsets, apps: apps, safeBounds: safeBounds)
            pushOffsets = offsets
        } else if isKBMode && !kbInSubMode && kbFocusedApp < apps.count {
            var offsets = CircularLayoutEngine.calculateKBFocusPushOffsets(apps: apps, focusedIndex: kbFocusedApp)
            CircularLayoutEngine.clampPushOffsets(&offsets, apps: apps, safeBounds: safeBounds)
            pushOffsets = offsets
        } else {
            pushOffsets = Array(repeating: .zero, count: apps.count)
        }
    }

    private func dismiss() {
        switchWorkItem?.cancel()
        switchWorkItem = nil
        cancelLongPress()
        clearPreviewNow()
        optionKey.stopMonitoring()
        stopRightClickMonitor()
        subAppDragIndex = nil
        subAppReorderActive = false
        subAppDragOriginalIndex = nil
        lastReorderFromIdx = nil
        closeMode = .none
        withAnimation(.easeOut(duration: 0.18)) { appeared = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { isVisible = false }
    }

    // MARK: - Right-Click Context Menu

    private func startRightClickMonitor() {
        guard rightClickMonitor == nil else { return }
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [self] event in
            guard closeMode == .none else { return event }
            guard let window = event.window, let contentView = window.contentView else { return event }

            let windowHeight = window.frame.height
            let loc = CGPoint(x: event.locationInWindow.x, y: windowHeight - event.locationInWindow.y)

            // Sub-apps first (higher z-order)
            if let idx = expandedAppIndex, idx < apps.count,
               let sub = CircularLayoutEngine.findClosestSubApp(
                   to: loc, in: apps[idx].windows,
                   threshold: CircularLayoutEngine.subBubbleRadius + 12
               ) {
                let menu = buildContextMenu(for: idx, windowIdx: sub)
                NSMenu.popUpContextMenu(menu, with: event, for: contentView)
                return nil
            }

            // Main apps
            let effectiveR = CircularLayoutEngine.effectiveBubbleRadius(for: apps.count)
            if let idx = CircularLayoutEngine.findClosestApp(
                to: loc, in: apps, offsets: pushOffsets, threshold: effectiveR + 12
            ) {
                let menu = buildContextMenu(for: idx)
                NSMenu.popUpContextMenu(menu, with: event, for: contentView)
                return nil
            }

            return event
        }
    }

    private func stopRightClickMonitor() {
        if let m = rightClickMonitor { NSEvent.removeMonitor(m); rightClickMonitor = nil }
    }

    private func buildContextMenu(for appIdx: Int, windowIdx: Int? = nil) -> NSMenu {
        let menu = NSMenu()
        let app = apps[appIdx]
        let bundleId = app.id

        let tagKey: String
        let displayName: String
        var boundCGWindowID: CGWindowID? = nil

        if let wIdx = windowIdx, wIdx < app.windows.count {
            let win = app.windows[wIdx]
            tagKey = TagManager.key(for: bundleId, windowName: win.name)
            displayName = win.name.isEmpty ? app.name : win.name
            boundCGWindowID = win.cgWindowID > 0 ? win.cgWindowID : nil
        } else {
            tagKey = TagManager.key(for: bundleId)
            displayName = app.name
        }

        // ── Tag section ──
        let tagHeader = NSMenuItem(title: "Tags", action: nil, keyEquivalent: "")
        tagHeader.isEnabled = false
        tagHeader.attributedTitle = NSAttributedString(
            string: "Tags",
            attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor]
        )
        menu.addItem(tagHeader)

        let assignedIds = tagManager.assignments[tagKey] ?? []
        for tag in tagManager.presetTags {
            let assigned = assignedIds.contains(tag.id)
            let item = ClosureMenuItem(title: "\(tag.emoji) \(tag.name)") { [weak tagManager] in
                tagManager?.toggleTag(tag, for: tagKey)
            }
            item.state = assigned ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // "New tag" — triggers inline text field below the bubble
        let newTagItem = ClosureMenuItem(title: "New Tag...") { [self] in
            showInlineTagInput(for: tagKey)
        }
        menu.addItem(newTagItem)

        if !assignedIds.isEmpty {
            menu.addItem(.separator())
            let clear = ClosureMenuItem(title: "Clear Tags") { [weak tagManager] in
                tagManager?.clearTags(for: tagKey)
            }
            menu.addItem(clear)
        }

        menu.addItem(.separator())

        // ── Quick launch section ──
        let quickHeader = NSMenuItem(title: "Quick Launch", action: nil, keyEquivalent: "")
        quickHeader.isEnabled = false
        quickHeader.attributedTitle = NSAttributedString(
            string: "Quick Launch",
            attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor]
        )
        menu.addItem(quickHeader)

        // Sub-app: bind by cgWindowID (stable across title changes)
        // Main app: bind at app level (cgWindowID = nil)
        let currentSlot = quickLaunch.slot(for: bundleId, cgWindowID: boundCGWindowID)

        for slot in 1...9 {
            let existing = quickLaunch.bindings[slot]
            let isThisTarget = existing?.bundleId == bundleId
                && existing?.cgWindowID == boundCGWindowID.map({ UInt32($0) })
            let title: String
            if isThisTarget {
                title = "⌥\(slot) ✓"
            } else if let existing = existing {
                title = "⌥\(slot)  →  \(existing.displayName)"
            } else {
                title = "⌥\(slot)"
            }

            let item = ClosureMenuItem(title: title) { [weak quickLaunch] in
                quickLaunch?.bind(slot: slot, bundleId: bundleId, cgWindowID: boundCGWindowID, displayName: displayName)
            }
            if isThisTarget { item.state = .on }
            menu.addItem(item)
        }

        if currentSlot != nil {
            menu.addItem(.separator())
            let unbind = ClosureMenuItem(title: "Unbind") { [weak quickLaunch] in
                if let s = currentSlot { quickLaunch?.unbind(slot: s) }
            }
            menu.addItem(unbind)
        }

        return menu
    }
}
