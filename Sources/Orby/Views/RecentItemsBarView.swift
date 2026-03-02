import SwiftUI
import QuickLookThumbnailing

struct RecentItemsBarView: View {
    let items: [RecentItem]
    let safeBounds: CGRect
    let appeared: Bool
    var onItemClicked: ((RecentItem) -> Void)?
    @Binding var itemFrames: [String: CGRect]
    @Binding var hoveredRecentItemId: String?

    @State private var barAppeared = false
    @State private var hoveredItemId: String?
    @State private var previewImage: NSImage?
    @State private var previewItemName: String = ""
    @State private var previewNoWindow: Bool = false
    @State private var previewAppIcon: NSImage?
    @State private var previewCenterX: CGFloat = 0
    @State private var hoverWorkItem: DispatchWorkItem?

    var body: some View {
        if !items.isEmpty {
            ZStack {
                previewCard

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(items) { item in
                            recentItemCell(item)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .frame(maxWidth: min(safeBounds.width - 32, 600))
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                )
                .position(
                    x: safeBounds.midX,
                    y: safeBounds.maxY - 56
                )
            }
            .opacity(barAppeared ? 1 : 0)
            .offset(y: barAppeared ? 0 : 30)
            .animation(.spring(response: 0.35, dampingFraction: 0.75).delay(0.1), value: barAppeared)
            .onAppear {
                if appeared { barAppeared = true }
            }
            .onChange(of: appeared) { newValue in
                barAppeared = newValue
                if !newValue { clearPreview() }
            }
        }
    }

    // MARK: - Hover Preview Card

    @ViewBuilder
    private var previewCard: some View {
        if let img = previewImage {
            let maxW: CGFloat = 280
            let maxH: CGFloat = 200
            let imgW = img.size.width
            let imgH = img.size.height
            let scale = min(maxW / max(imgW, 1), maxH / max(imgH, 1), 1)
            let w = imgW * scale
            let h = imgH * scale

            previewCardContainer(height: h + 30) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: w, height: h)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(previewItemName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
            }
        } else if previewNoWindow, let icon = previewAppIcon {
            previewCardContainer(height: 100) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)

                Text(previewItemName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)

                Text("无打开窗口")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.45))
            }
        }
    }

    private func previewCardContainer<Content: View>(height: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 4) {
            content()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .position(
            x: clampX(previewCenterX),
            y: safeBounds.maxY - 56 - 50 - height / 2
        )
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    private func clampX(_ x: CGFloat) -> CGFloat {
        let margin: CGFloat = 160
        return min(max(x, safeBounds.minX + margin), safeBounds.maxX - margin)
    }

    // MARK: - Item Cell (icon)

    private func recentItemCell(_ item: RecentItem) -> some View {
        Button {
            onItemClicked?(item)
        } label: {
            VStack(spacing: 4) {
                Image(nsImage: item.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)

                Text(item.name)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 56)
            }
            .frame(width: 64, height: 72)
            .scaleEffect(hoveredItemId == item.id ? 1.08 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: hoveredItemId)
            .background(
                GeometryReader { geo in
                    let cs = CoordinateSpace.named("orbyCanvas")
                    Color.clear
                        .onAppear {
                            itemFrames[item.id] = geo.frame(in: cs)
                        }
                        .onChange(of: geo.frame(in: cs).origin.x) { _ in
                            itemFrames[item.id] = geo.frame(in: cs)
                        }
                        .onChange(of: hoveredItemId) { newId in
                            if newId == item.id {
                                previewCenterX = geo.frame(in: cs).midX
                            }
                        }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onContinuousHover { phase in
            if case .active = phase {
                if hoveredItemId != item.id {
                    hoveredItemId = item.id
                    hoveredRecentItemId = item.id
                    previewImage = nil
                    previewItemName = ""
                    previewNoWindow = false
                    previewAppIcon = nil
                    schedulePreview(for: item)
                }
            } else if hoveredItemId == item.id {
                hoveredItemId = nil
                hoveredRecentItemId = nil
                schedulePreviewDismiss()
            }
        }
    }

    // MARK: - Preview Generation

    private func schedulePreview(for item: RecentItem) {
        hoverWorkItem?.cancel()
        let itemId = item.id
        let work = DispatchWorkItem {
            generatePreview(for: item, expectedId: itemId)
        }
        hoverWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func schedulePreviewDismiss() {
        hoverWorkItem?.cancel()
        let work = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.12)) {
                previewImage = nil
                previewItemName = ""
                previewNoWindow = false
                previewAppIcon = nil
            }
        }
        hoverWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func generatePreview(for item: RecentItem, expectedId: String) {
        if item.kind == .application {
            captureAppWindow(for: item, expectedId: expectedId)
        } else {
            generateQLPreview(for: item, expectedId: expectedId)
        }
    }

    /// Capture the first on-screen window of the app matching this bundle path
    private func captureAppWindow(for item: RecentItem, expectedId: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let running = NSWorkspace.shared.runningApplications.first {
                $0.activationPolicy == .regular && $0.bundleURL == item.url
            }
            guard let pid = running?.processIdentifier else {
                // App not running — show "no window" placeholder
                DispatchQueue.main.async {
                    guard self.hoveredItemId == expectedId else { return }
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                        self.previewImage = nil
                        self.previewNoWindow = true
                        self.previewAppIcon = item.icon
                        self.previewItemName = item.name
                    }
                }
                return
            }

            // Find a visible window for this pid via CGWindowList
            guard let list = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
            ) as? [[String: Any]] else { return }

            var windowID: CGWindowID = 0
            for info in list {
                guard let wPid = info[kCGWindowOwnerPID as String] as? pid_t, wPid == pid,
                      let wid = info[kCGWindowNumber as String] as? CGWindowID,
                      let layer = info[kCGWindowLayer as String] as? Int, layer == 0
                else { continue }
                if let b = info[kCGWindowBounds as String] as? [String: Any],
                   let w = (b["Width"] as? NSNumber)?.doubleValue,
                   let h = (b["Height"] as? NSNumber)?.doubleValue,
                   w > 50, h > 50 {
                    windowID = wid
                    break
                }
            }

            // App running but no visible window — show "no window" placeholder
            guard windowID > 0 else {
                let icon = item.icon
                let name = item.name
                DispatchQueue.main.async {
                    guard self.hoveredItemId == expectedId else { return }
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                        self.previewImage = nil
                        self.previewNoWindow = true
                        self.previewAppIcon = icon
                        self.previewItemName = name
                    }
                }
                return
            }

            // Capture
            guard let cgImage = CGWindowListCreateImage(
                .null, .optionIncludingWindow, windowID,
                [.boundsIgnoreFraming, .nominalResolution]
            ) else {
                DispatchQueue.main.async {
                    self.generateQLPreview(for: item, expectedId: expectedId)
                }
                return
            }

            let pixelW = CGFloat(cgImage.width)
            let pixelH = CGFloat(cgImage.height)
            guard pixelW > 0, pixelH > 0 else { return }

            let maxSize: CGFloat = 400
            let s = min(maxSize / pixelW, maxSize / pixelH, 1.0)
            let newW = pixelW * s
            let newH = pixelH * s

            let resized = NSImage(size: NSSize(width: newW, height: newH))
            resized.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            let rep = NSBitmapImageRep(cgImage: cgImage)
            rep.draw(in: NSRect(x: 0, y: 0, width: newW, height: newH))
            resized.unlockFocus()

            DispatchQueue.main.async {
                guard self.hoveredItemId == expectedId else { return }
                withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                    self.previewNoWindow = false
                    self.previewAppIcon = nil
                    self.previewImage = resized
                    self.previewItemName = item.name
                }
            }
        }
    }

    /// QLThumbnailGenerator for file/folder content preview
    private func generateQLPreview(for item: RecentItem, expectedId: String) {
        let size = CGSize(width: 560, height: 400)
        let request = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: size,
            scale: 2.0,
            representationTypes: .all
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumb, _ in
            DispatchQueue.main.async {
                guard self.hoveredItemId == expectedId, let thumb else { return }
                withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                    self.previewImage = thumb.nsImage
                    self.previewItemName = item.name
                }
            }
        }
    }

    private func clearPreview() {
        hoverWorkItem?.cancel()
        hoverWorkItem = nil
        previewImage = nil
        previewItemName = ""
        previewNoWindow = false
        previewAppIcon = nil
        hoveredItemId = nil
    }
}
