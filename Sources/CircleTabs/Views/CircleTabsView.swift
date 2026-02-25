import SwiftUI

private let jellySpring = Animation.spring(response: 0.22, dampingFraction: 0.72)
private let subAppSpring = Animation.spring(response: 0.35, dampingFraction: 0.5)
private let softSpring = Animation.spring(response: 0.2, dampingFraction: 0.75)
private let quickSpring = Animation.spring(response: 0.18, dampingFraction: 0.7)
private let collapseAnim = Animation.easeOut(duration: 0.12)

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
    @State private var subAppStaggerFlags: [Bool] = []
    @State private var isHoveringPreview = false
    @State private var previewTitle: String = ""
    @State private var switchWorkItem: DispatchWorkItem?
    @State private var safeBounds: CGRect = .zero

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
                .onChanged { handleMouseMove($0.location) }
                .onEnded { handleClick(at: $0.location) }
        )
        .onExitCommand { dismiss() }
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
        // Safe bounds excluding dock & menu bar, in flipped (SwiftUI) coordinates
        let topInset = sf.maxY - vf.maxY       // menu bar
        let bottomInset = vf.minY - sf.minY     // dock (bottom)
        let leftInset = vf.minX - sf.minX       // dock (left side)
        let rightInset = sf.maxX - vf.maxX      // dock (right side)
        safeBounds = CGRect(
            x: leftInset,
            y: topInset,
            width: w - leftInset - rightInset,
            height: h - topInset - bottomInset
        )

        let cursorPos = CGPoint(x: rawX, y: rawY)
        mousePos = cursorPos
        // center is set ONLY inside loadApps (to the adjusted ring center)
        loadApps(around: cursorPos)
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
        .scaleEffect(appeared ? 1.0 : 0.8)
        .animation(jellySpring, value: appeared)
        .onTapGesture { dismiss() }
    }

    // MARK: - Connection Lines

    private func connectionLines() -> some View {
        Group {
            if let i = hoveredAppIndex, i < apps.count {
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
            if let idx = expandedAppIndex, idx < apps.count,
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
            AppBubbleView(
                app: apps[i],
                isHovered: hoveredAppIndex == i,
                isExpanded: expandedAppIndex == i,
                dimLevel: dimLevel(for: i),
                offset: offset(for: i)
            )
            .scaleEffect(vis ? 1.0 : 0.01)
            .opacity(vis ? 1.0 : 0)
            .animation(jellySpring.delay(Double(i) * 0.008), value: vis)
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
                        showLabel: hoveredSubAppIndex == wIdx
                    )
                    .zIndex(hoveredSubAppIndex == wIdx ? 100 : 0)
                    .scaleEffect(vis ? 1.0 : 0.01)
                    .opacity(vis ? 1.0 : 0)
                    .animation(subAppSpring.delay(Double(wIdx) * 0.04), value: vis)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                    .onTapGesture {
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
            if let img = previewImage {
                let imgW = img.size.width
                let imgH = img.size.height
                let cardW = max(imgW, 160)

                VStack(spacing: 0) {
                    // Title bar with close button
                    HStack(spacing: 6) {
                        // Close button (red circle)
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

                    // Preview image
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
                    // Click preview → activate that window
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
        center = pt  // close icon stays at cursor position
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

        // STEP 1: When sub-apps are expanded, check sub-apps FIRST (they render on top)
        if let idx = expandedAppIndex, idx < apps.count {
            if let sub = CircularLayoutEngine.findClosestSubApp(to: loc, in: apps[idx].windows, threshold: CircularLayoutEngine.subBubbleRadius + 18) {
                let winId = apps[idx].windows[sub].id
                withAnimation(quickSpring) { hoveredSubAppIndex = sub; hoveredAppIndex = idx }
                if winId != previewForWindowId {
                    clearPreviewNow()
                    schedulePreview(for: idx, windowIndex: sub, windowId: winId)
                }
                return // sub-app takes priority — skip main app checks
            }
        }

        // STEP 2: Check main apps — use visual positions (base + push offsets)
        let effectiveR = CircularLayoutEngine.effectiveBubbleRadius(for: apps.count)
        let appIdx = CircularLayoutEngine.findClosestApp(to: loc, in: apps, offsets: pushOffsets, threshold: effectiveR + 20)

        if hoveredAppIndex != appIdx { withAnimation(quickSpring) { hoveredAppIndex = appIdx } }

        // STEP 3: If hovering a DIFFERENT main app than the expanded one → switch/collapse
        if let idx = appIdx, let expanded = expandedAppIndex, idx != expanded {
            if apps[idx].windows.count > 1 {
                switchExpandedApp(to: idx)
            } else {
                collapseSubApps()
            }
            return
        }

        // STEP 4: If no app is expanded but hovering a multi-window app → expand
        if let idx = appIdx, expandedAppIndex == nil, apps[idx].windows.count > 1 {
            switchExpandedApp(to: idx)
            return
        }

        // STEP 5: Cursor not near any sub-app — clear sub-app hover
        if expandedAppIndex != nil {
            if isHoveringPreview { return }
            withAnimation(quickSpring) { hoveredSubAppIndex = nil }
            clearPreviewNow()
        }

        // STEP 6: Not near any main app or sub-app → collapse if near center
        if expandedAppIndex != nil, appIdx == nil {
            let inSub: Bool
            if let idx = expandedAppIndex, idx < apps.count {
                inSub = CircularLayoutEngine.findClosestSubApp(to: loc, in: apps[idx].windows, threshold: CircularLayoutEngine.subBubbleRadius + 35) != nil
            } else { inSub = false }
            if !inSub && !isHoveringPreview {
                let dx = loc.x - center.x, dy = loc.y - center.y
                if sqrt(dx*dx + dy*dy) < CircularLayoutEngine.ring1Radius * 0.3 {
                    collapseSubApps()
                }
            }
        }
    }

    /// Collapse current sub-apps and restore brightness
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

    /// Smoothly switch from one expanded app to another:
    /// collapse old sub-apps first, then expand new from parent position.
    private func switchExpandedApp(to newIdx: Int) {
        // Cancel any pending switch
        switchWorkItem?.cancel()
        clearPreviewNow()

        if expandedAppIndex != nil {
            // Phase 1: collapse old sub-apps + restore brightness
            withAnimation(collapseAnim) {
                expandedAppIndex = nil
                hoveredSubAppIndex = nil
                recalcPushOffsets()
            }
            subAppStaggerFlags = []

            // Phase 2: after collapse, expand new sub-apps from parent
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
            // No app currently expanded, expand directly
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
        hoverTimer?.cancel()
        previewForWindowId = windowId

        let work = DispatchWorkItem { [self] in
            guard appIdx < apps.count, wIdx < apps[appIdx].windows.count else { return }
            let win = apps[appIdx].windows[wIdx]
            guard win.id == windowId else { return }
            if let img = AppDiscoveryService.shared.captureWindowPreview(cgWindowID: win.cgWindowID) {
                withAnimation(quickSpring) {
                    previewImage = img
                    previewTitle = win.name.isEmpty ? "Window" : win.name

                    // Position preview outward from center, past the sub-app bubble
                    let dx = win.position.x - center.x
                    let dy = win.position.y - center.y
                    let dist = sqrt(dx * dx + dy * dy)
                    let normX = dist > 0 ? dx / dist : 0
                    let normY = dist > 0 ? dy / dist : 1
                    let offset = img.size.height / 2 + CircularLayoutEngine.subBubbleRadius + 50
                    previewPosition = CGPoint(
                        x: win.position.x + normX * offset,
                        y: win.position.y + normY * offset
                    )
                }
            }
        }
        hoverTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    private func clearPreviewNow() {
        hoverTimer?.cancel()
        hoverTimer = nil
        previewForWindowId = -1
        previewImage = nil
        previewTitle = ""
        isHoveringPreview = false
    }

    private func closePreviewWindow() {
        guard let idx = expandedAppIndex, idx < apps.count,
              let wIdx = hoveredSubAppIndex, wIdx < apps[idx].windows.count else { return }
        let window = apps[idx].windows[wIdx]
        AppDiscoveryService.shared.closeWindow(window)
        clearPreviewNow()
        // Reload after window closes
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
        clearPreviewNow()
        withAnimation(.easeOut(duration: 0.18)) { appeared = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { isVisible = false }
    }
}
