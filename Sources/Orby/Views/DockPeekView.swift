import SwiftUI

/// SwiftUI view for DockPeek preview panel — DockDoor-style window thumbnails.
struct DockPeekView: View {
    let windows: [WindowItem]
    let appIcon: NSImage
    let appName: String
    let bundleId: String

    @State private var thumbnailImages: [Int: NSImage] = [:]
    @State private var hoveredWindowId: Int?
    @State private var hoveredTrafficLight: String?

    private var isSingleWindow: Bool { windows.count == 1 }
    private var thumbWidth: CGFloat { isSingleWindow ? 240 : 200 }
    private var thumbHeight: CGFloat { isSingleWindow ? 140 : 130 }

    var body: some View {
        VStack(spacing: 0) {
            if windows.isEmpty {
                emptyStateView
            } else {
                // Header
                HStack(spacing: 5) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)

                    Text(appName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)

                    Spacer()

                    if windows.count > 1 {
                        Text("\(windows.count)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 5)

                // Thumbnails row
                HStack(spacing: 8) {
                    ForEach(windows) { window in
                        thumbnailCard(for: window)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .fixedSize()  // Let the view wrap tightly to its content
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.25))
            }
            .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onReceive(NotificationCenter.default.publisher(for: .dockPeekThumbnailReady)) { notification in
            guard let userInfo = notification.userInfo,
                  let windowId = userInfo["windowId"] as? Int,
                  let image = userInfo["image"] as? NSImage else { return }
            withAnimation(.easeIn(duration: 0.12)) {
                thumbnailImages[windowId] = image
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        HStack(spacing: 10) {
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(appName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                Text("No open windows")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Thumbnail Card

    private func thumbnailCard(for window: WindowItem) -> some View {
        let isHovered = hoveredWindowId == window.id

        return VStack(spacing: 0) {
            // Thumbnail image
            ZStack {
                if let img = thumbnailImages[window.id] {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: thumbWidth, height: thumbHeight)
                        .clipped()
                } else {
                    // Loading placeholder — same fixed size as loaded thumbnail
                    Color.white.opacity(0.04)
                        .frame(width: thumbWidth, height: thumbHeight)
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.5)
                                .tint(.white.opacity(0.2))
                        )
                }

                // Minimized overlay
                if window.isMinimized {
                    Color.black.opacity(0.55)
                    VStack(spacing: 3) {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 18, weight: .light))
                            .foregroundColor(.white.opacity(0.5))
                        Text("已最小化")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }

                // Traffic lights on hover (top-left)
                if isHovered {
                    VStack {
                        HStack(spacing: 4) {
                            trafficDot(color: .red, symbol: "xmark", key: "close:\(window.id)") {
                                AppDiscoveryService.shared.closeWindow(window)
                                DockPeekService.shared.refreshPreview()
                            }
                            trafficDot(color: .yellow, symbol: "minus", key: "min:\(window.id)") {
                                AppDiscoveryService.shared.minimizeWindow(window)
                                DockPeekService.shared.refreshPreview()
                            }
                            trafficDot(color: .green, symbol: "arrow.up.left.and.arrow.down.right", key: "full:\(window.id)") {
                                AppDiscoveryService.shared.toggleFullscreenWindow(window)
                                DockPeekService.shared.refreshPreview()
                            }
                            Spacer()
                        }
                        .padding(6)
                        Spacer()
                    }
                }
            }
            .frame(width: thumbWidth, height: thumbHeight)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Window title below thumbnail
            Text(windowDisplayName(window))
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.55))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: thumbWidth, alignment: .leading)
                .padding(.top, 4)
                .padding(.horizontal, 2)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(isHovered ? 0.08 : 0))
        )
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            if case .active = phase {
                hoveredWindowId = window.id
            } else if hoveredWindowId == window.id {
                hoveredWindowId = nil
            }
        }
        .onTapGesture {
            AppDiscoveryService.shared.activateWindow(window)
            DockPeekService.shared.dismissPreview()
        }
    }

    // MARK: - Traffic Light Dot

    private func trafficDot(
        color: Color, symbol: String, key: String,
        action: @escaping () -> Void
    ) -> some View {
        let isHot = hoveredTrafficLight == key
        return ZStack {
            Circle()
                .fill(color)
                .frame(width: 11, height: 11)
                .shadow(color: color.opacity(0.4), radius: 2, x: 0, y: 0)
            if isHot {
                Image(systemName: symbol)
                    .font(.system(size: 5.5, weight: .bold))
                    .foregroundColor(.black.opacity(0.7))
            }
        }
        .contentShape(Circle().size(width: 16, height: 16))
        .onContinuousHover { phase in
            if case .active = phase {
                hoveredTrafficLight = key
            } else if hoveredTrafficLight == key {
                hoveredTrafficLight = nil
            }
        }
        .onTapGesture { action() }
    }

    // MARK: - Helpers

    private func windowDisplayName(_ window: WindowItem) -> String {
        let name = window.displayName.isEmpty
            ? WindowItem.computeDisplayName(for: window.name)
            : window.displayName
        return name.isEmpty ? appName : name
    }
}
