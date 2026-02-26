import SwiftUI

struct SubAppBubbleView: View {
    let window: WindowItem
    let parentIcon: NSImage
    let isHovered: Bool
    let showLabel: Bool
    let isInCloseMode: Bool
    var tags: [AppTag] = []
    var quickSlot: Int? = nil

    private let size: CGFloat = CircularLayoutEngine.subBubbleRadius * 2

    var body: some View {
        ZStack {
            // Frosted glass circle
            Circle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .shadow(color: .black.opacity(isHovered ? 0.18 : 0.08), radius: isHovered ? 14 : 8, x: 0, y: isHovered ? 6 : 4)
                .overlay(
                    Circle()
                        .strokeBorder(
                            Color.white.opacity(isHovered ? 0.35 : 0.15),
                            lineWidth: 1
                        )
                )

            // Parent app icon
            Image(nsImage: parentIcon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.58, height: size * 0.58)
                .opacity(isHovered ? 1.0 : 0.9)

            // Minimized indicator
            if window.isMinimized {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .gray.opacity(0.7))
                    .offset(x: size * 0.28, y: size * 0.28)
            }
        }
        .frame(width: size, height: size)
        .opacity(window.isMinimized ? 0.6 : 1.0)
        .scaleEffect(isHovered ? 1.2 : 1.0)
        // Tag labels
        .overlay(alignment: .bottom) {
            if !tags.isEmpty && !isInCloseMode {
                HStack(spacing: 2) {
                    ForEach(tags.prefix(2)) { tag in
                        Text(tag.name)
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 42)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule()
                                    .fill(tag.color.opacity(0.85))
                                    .shadow(color: tag.color.opacity(0.5), radius: 1.5)
                            )
                    }
                    if tags.count > 2 {
                        Text("+\(tags.count - 2)")
                            .font(.system(size: 7, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule()
                                    .fill(Color.gray.opacity(0.7))
                            )
                    }
                }
                .offset(y: -2)
            }
        }
        // Quick launch slot badge
        .overlay(alignment: .topTrailing) {
            if let slot = quickSlot, !isInCloseMode {
                Text("\(slot)")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 16, height: 16)
                    .background(
                        Circle()
                            .fill(Color.blue.opacity(0.9))
                            .shadow(color: .black.opacity(0.3), radius: 2)
                    )
                    .offset(x: 3, y: -3)
            }
        }
        // Close badge — outside the scaled frame
        .overlay(alignment: .topLeading) {
            if isInCloseMode {
                closeBadge
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
        }
        .modifier(JellyWobble(isActive: isInCloseMode, seed: window.id))
        // Tooltip label
        .overlay(alignment: .bottom) {
            if showLabel && !isInCloseMode {
                Text(displayName)
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
                    .offset(y: size * 0.5 + 14)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .position(x: window.position.x, y: window.position.y)
        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: isHovered)
    }

    private var closeBadge: some View {
        let badgeSize: CGFloat = isHovered ? 22 : 18
        return ZStack {
            Circle()
                .fill(Color.red)
                .frame(width: badgeSize, height: badgeSize)
                .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
                .shadow(color: .red.opacity(isHovered ? 0.5 : 0.2), radius: isHovered ? 6 : 3)
            Image(systemName: "xmark")
                .font(.system(size: isHovered ? 10 : 8, weight: .bold))
                .foregroundColor(.white)
        }
        .offset(x: -2, y: -2)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isHovered)
    }

    private var displayName: String {
        let title = window.name
        guard !title.isEmpty else { return "Window" }

        for sep in [" — ", "—", " \u{2013} ", "\u{2013}"] {
            if let range = title.range(of: sep, options: .backwards) {
                let workspace = String(title[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !workspace.isEmpty { return workspace }
            }
        }

        if let range = title.range(of: " - ", options: .backwards) {
            let workspace = String(title[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !workspace.isEmpty { return workspace }
        }

        return title
    }
}
