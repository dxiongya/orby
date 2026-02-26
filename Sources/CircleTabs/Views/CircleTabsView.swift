import SwiftUI

private let jellySpring = Animation.spring(response: 0.32, dampingFraction: 0.68)
private let subAppSpring = Animation.spring(response: 0.35, dampingFraction: 0.5)
private let softSpring = Animation.spring(response: 0.2, dampingFraction: 0.75)
private let quickSpring = Animation.spring(response: 0.18, dampingFraction: 0.7)
private let collapseAnim = Animation.easeOut(duration: 0.12)

enum CloseMode: Equatable {
    case none
    case mainApps
    case subApps
}

/// Monitors Option key press/release via local event monitor
private class OptionKeyState: ObservableObject {
    @Published var isHeld = false
    private var monitor: Any?

    func startMonitoring() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let option = event.modifierFlags.contains(.option)
            if self?.isHeld != option {
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.12)) {
                        self?.isHeld = option
                    }
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

struct CircleTabsView: View {
    @Binding var isVisible: Bool

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
    @State private var switchWorkItem: DispatchWorkItem?
    @State private var safeBounds: CGRect = .zero

    // Close mode state
    @State private var closeMode: CloseMode = .none
    @State private var longPressWorkItem: DispatchWorkItem?
    @State private var longPressStartPos: CGPoint?
    @State private var longPressTriggered = false
    @State private var isDragging = false

    // Option key state for showing all sub-app labels
    @StateObject private var optionKey = OptionKeyState()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                backgroundLayer

                if center.x >= 0 && appeared {
                    connectionLines()
                    subAppConnectionLines()
                    mainAppBubbles()
                    subAppBubbles()
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
                    handleMouseMove(value.location)
                    if !isDragging {
                        isDragging = true
                        longPressStartPos = value.location
                        if closeMode == .none {
                            startLongPressDetection(at: value.location)
                        }
                    } else if let start = longPressStartPos {
                        let dx = value.location.x - start.x
                        let dy = value.location.y - start.y
                        if sqrt(dx * dx + dy * dy) > 8 {
                            cancelLongPress()
                        }
                    }
                }
                .onEnded { value in
                    isDragging = false
                    cancelLongPress()

                    if longPressTriggered {
                        longPressTriggered = false
                        return
                    }

                    if closeMode != .none {
                        handleCloseModeTap(at: value.location)
                    } else {
                        handleClick(at: value.location)
                    }
                }
        )
        .onReceive(NotificationCenter.default.publisher(for: .escapePressed)) { _ in
            if closeMode != .none {
                withAnimation(quickSpring) { closeMode = .none }
            } else {
                dismiss()
            }
        }
    }

    // MARK: - Long Press Detection

    private func startLongPressDetection(at location: CGPoint) {
        longPressWorkItem?.cancel()

        let work = DispatchWorkItem { [self] in
            // Check sub-apps first (higher z-order)
            if let idx = expandedAppIndex, idx < apps.count,
               let _ = CircularLayoutEngine.findClosestSubApp(
                   to: location, in: apps[idx].windows,
                   threshold: CircularLayoutEngine.subBubbleRadius + 18
               ) {
                enterCloseMode(.subApps)
                return
            }

            // Then check main apps
            let effectiveR = CircularLayoutEngine.effectiveBubbleRadius(for: apps.count)
            if let _ = CircularLayoutEngine.findClosestApp(
                to: location, in: apps, offsets: pushOffsets, threshold: effectiveR + 20
            ) {
                enterCloseMode(.mainApps)
            }
        }
        longPressWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func cancelLongPress() {
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
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
            ) {
                AppDiscoveryService.shared.terminateApp(apps[idx])
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

    // MARK: - Close Mode Hint

    private func closeModeHint() -> some View {
        Group {
            if closeMode != .none {
                Text(closeMode == .mainApps ? "点击关闭应用 · ESC 退出" : "点击关闭窗口 · ESC 退出")
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
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main!
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

        let cursorPos = CGPoint(x: rawX, y: rawY)
        mousePos = cursorPos
        loadApps(around: cursorPos)
        optionKey.startMonitoring()
        withAnimation(jellySpring) { appeared = true }
        animateStaggeredEntrance()
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
                isInCloseMode: closeMode == .mainApps
            )
            .zIndex(hoveredAppIndex == i ? 100 : 0)
            .offset(x: flyX, y: flyY)
            .scaleEffect(vis ? 1.0 : 0.35)
            .opacity(vis ? 1.0 : 0)
            .animation(jellySpring.delay(Double(i) * 0.015), value: vis)
            .onTapGesture { tapApp(i) }
        }
    }

    // MARK: - Sub App Bubbles

    private func subAppBubbles() -> some View {
        Group {
            if let idx = expandedAppIndex, idx < apps.count {
                ForEach(apps[idx].windows.indices, id: \.self) { wIdx in
                    let vis = subAppStaggerFlags.indices.contains(wIdx) ? subAppStaggerFlags[wIdx] : false
                    SubAppBubbleView(
                        window: apps[idx].windows[wIdx],
                        parentIcon: apps[idx].icon,
                        isHovered: hoveredSubAppIndex == wIdx,
                        showLabel: hoveredSubAppIndex == wIdx || optionKey.isHeld,
                        isInCloseMode: closeMode == .subApps
                    )
                    .zIndex(hoveredSubAppIndex == wIdx ? 100 : 0)
                    .scaleEffect(vis ? 1.0 : 0.01)
                    .opacity(vis ? 1.0 : 0)
                    .animation(subAppSpring.delay(Double(wIdx) * 0.04), value: vis)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                    .onTapGesture {
                        guard closeMode == .none else { return }
                        AppDiscoveryService.shared.activateWindow(apps[idx].windows[wIdx])
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Window Preview (DockDoor style card)

    private func windowPreview() -> some View {
        Group {
            if closeMode == .none, let img = previewImage {
                let imgW = img.size.width
                let imgH = img.size.height
                let cardW = max(imgW, 160)

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
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: imgW, height: imgH)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
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
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
                .scaleEffect(isHoveringPreview ? 1.06 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHoveringPreview)
                .position(x: previewPosition.x, y: previewPosition.y)
                .onContinuousHover { phase in
                    if case .active = phase {
                        isHoveringPreview = true
                    } else {
                        isHoveringPreview = false
                    }
                }
                .onTapGesture {
                    if let idx = expandedAppIndex, idx < apps.count,
                       let wIdx = hoveredSubAppIndex, wIdx < apps[idx].windows.count {
                        AppDiscoveryService.shared.activateWindow(apps[idx].windows[wIdx])
                        dismiss()
                    }
                }
                .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
    }

    // MARK: - Logic

    private func loadApps(around pt: CGPoint) {
        var items = AppDiscoveryService.shared.getRunningApps()
        center = pt
        CircularLayoutEngine.layoutApps(&items, center: pt, safeBounds: safeBounds)
        apps = items
        pushOffsets = Array(repeating: .zero, count: items.count)
        staggerFlags = Array(repeating: false, count: items.count)
    }

    private func animateSubAppEntrance(count: Int) {
        subAppStaggerFlags = Array(repeating: false, count: count)
        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.04 + 0.01) {
                withAnimation(subAppSpring) {
                    if i < subAppStaggerFlags.count { subAppStaggerFlags[i] = true }
                }
            }
        }
    }

    private func animateStaggeredEntrance() {
        for i in staggerFlags.indices {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.008 + 0.01) {
                withAnimation(jellySpring) {
                    if i < staggerFlags.count { staggerFlags[i] = true }
                }
            }
        }
    }

    private func handleMouseMove(_ loc: CGPoint) {
        mousePos = loc

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

        // STEP 5: clear sub hover (but keep preview if mouse is over it)
        if expandedAppIndex != nil {
            let overPreview = isHoveringPreview || isMouseOverPreview(loc)
            if overPreview { return }
            withAnimation(quickSpring) { hoveredSubAppIndex = nil }
            clearPreviewNow()
        }

        // STEP 6: collapse near center
        if expandedAppIndex != nil, appIdx == nil {
            let inSub: Bool
            if let idx = expandedAppIndex, idx < apps.count {
                inSub = CircularLayoutEngine.findClosestSubApp(to: loc, in: apps[idx].windows, threshold: CircularLayoutEngine.subBubbleRadius + 35) != nil
            } else { inSub = false }
            let overPreview = isHoveringPreview || isMouseOverPreview(loc)
            if !inSub && !overPreview {
                let dx = loc.x - center.x, dy = loc.y - center.y
                if sqrt(dx*dx + dy*dy) < CircularLayoutEngine.ring1Radius * 0.3 {
                    collapseSubApps()
                }
            }
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

    private func schedulePreview(for appIdx: Int, windowIndex wIdx: Int, windowId: Int) {
        guard SettingsManager.shared.showPreview else { return }
        hoverTimer?.cancel()
        previewForWindowId = windowId

        let delay = SettingsManager.shared.previewDelay
        let work = DispatchWorkItem { [self] in
            guard appIdx < apps.count, wIdx < apps[appIdx].windows.count else { return }
            let win = apps[appIdx].windows[wIdx]
            guard win.id == windowId else { return }
            if let img = AppDiscoveryService.shared.captureWindowPreview(cgWindowID: win.cgWindowID) {
                withAnimation(quickSpring) {
                    previewImage = img
                    previewTitle = win.name.isEmpty ? "Window" : win.name

                    let cardW = max(img.size.width, 160) + 12
                    let cardH = img.size.height + 40
                    let pos = findBestPreviewPosition(
                        anchor: win.position, cardSize: CGSize(width: cardW, height: cardH),
                        expandedIdx: appIdx
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
    private func findBestPreviewPosition(anchor: CGPoint, cardSize: CGSize, expandedIdx: Int) -> CGPoint {
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
        // Sub-app bubbles
        if expandedIdx < apps.count {
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
        // Add 20px margin to make it easier to reach
        return previewFrame.insetBy(dx: -20, dy: -20).contains(loc)
    }

    private func clearPreviewNow() {
        hoverTimer?.cancel()
        hoverTimer = nil
        previewForWindowId = -1
        previewImage = nil
        previewTitle = ""
        isHoveringPreview = false
        previewFrame = .zero
    }

    private func closePreviewWindow() {
        guard let idx = expandedAppIndex, idx < apps.count,
              let wIdx = hoveredSubAppIndex, wIdx < apps[idx].windows.count else { return }
        let window = apps[idx].windows[wIdx]
        AppDiscoveryService.shared.closeWindow(window)
        clearPreviewNow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            subAppStaggerFlags = []
            withAnimation(softSpring) {
                expandedAppIndex = nil; hoveredSubAppIndex = nil; recalcPushOffsets()
            }
            loadApps(around: center)
            animateStaggeredEntrance()
        }
    }

    private func handleClick(at loc: CGPoint) {
        let dx = loc.x - center.x, dy = loc.y - center.y
        if sqrt(dx*dx + dy*dy) < 22 { dismiss(); return }
        if let idx = expandedAppIndex, idx < apps.count,
           let sub = CircularLayoutEngine.findClosestSubApp(to: loc, in: apps[idx].windows, threshold: CircularLayoutEngine.subBubbleRadius + 12) {
            AppDiscoveryService.shared.activateWindow(apps[idx].windows[sub]); dismiss(); return
        }
        let clickR = CircularLayoutEngine.effectiveBubbleRadius(for: apps.count)
        if let idx = CircularLayoutEngine.findClosestApp(to: loc, in: apps, offsets: pushOffsets, threshold: clickR + 12) {
            if apps[idx].windows.count <= 1 { AppDiscoveryService.shared.activateApp(apps[idx]); dismiss() }
        }
    }

    private func tapApp(_ i: Int) {
        guard closeMode == .none else { return }
        if apps[i].windows.count <= 1 {
            AppDiscoveryService.shared.activateApp(apps[i]); dismiss()
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
        CircularLayoutEngine.layoutSubApps(&w, parentPosition: apps[i].position, parentAngle: apps[i].angle, center: center, safeBounds: safeBounds)
        apps[i].windows = w
    }

    private func recalcPushOffsets() {
        if let idx = expandedAppIndex {
            var offsets = CircularLayoutEngine.calculatePushOffsets(apps: apps, expandedIndex: idx, center: center)
            CircularLayoutEngine.clampPushOffsets(&offsets, apps: apps, safeBounds: safeBounds)
            pushOffsets = offsets
        } else { pushOffsets = Array(repeating: .zero, count: apps.count) }
    }

    private func dismiss() {
        switchWorkItem?.cancel()
        switchWorkItem = nil
        cancelLongPress()
        clearPreviewNow()
        optionKey.stopMonitoring()
        closeMode = .none
        withAnimation(.easeOut(duration: 0.18)) { appeared = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { isVisible = false }
    }
}
