import SwiftUI

/// One-shot jelly squash-stretch triggered by slot index change during reorder
private struct JellyBounce: ViewModifier {
    let trigger: Int

    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: 1 + phase * 0.12, y: 1 - phase * 0.10)
            .onChange(of: trigger) { _ in
                // Kick off the squash
                withAnimation(.easeOut(duration: 0.06)) {
                    phase = 1
                }
                // Bounce back with jelly overshoot
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.3)) {
                        phase = 0
                    }
                }
            }
    }
}

struct SubAppBubbleView: View {
    let window: WindowItem
    let parentIcon: NSImage
    let isHovered: Bool
    let showLabel: Bool
    let isInCloseMode: Bool
    var tags: [AppTag] = []
    var quickSlot: Int? = nil
    var kbFocused: Bool = false
    var kbShortcut: String? = nil
    var isDragging: Bool = false
    var isReorderMode: Bool = false
    var slotIndex: Int = 0       // current slot position — for jelly bounce trigger
    var isGrabbed: Bool = false   // pressed but not yet dragging

    private let size: CGFloat = CircularLayoutEngine.subBubbleRadius * 2
    private var highlighted: Bool { isHovered || kbFocused || isDragging }

    var body: some View {
        ZStack {
            // Frosted glass circle
            Circle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .shadow(color: .black.opacity(highlighted ? 0.18 : 0.08), radius: highlighted ? 14 : 8, x: 0, y: highlighted ? 6 : 4)
                .overlay(
                    Circle()
                        .strokeBorder(
                            Color.white.opacity(highlighted ? 0.35 : 0.15),
                            lineWidth: kbFocused ? 2.5 : 1
                        )
                )
                .overlay(
                    kbFocused ? Circle()
                        .strokeBorder(Color.orange.opacity(0.8), lineWidth: 2.5)
                        .shadow(color: Color.orange.opacity(0.5), radius: 8)
                    : nil
                )

            // Parent app icon
            Image(nsImage: parentIcon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.58, height: size * 0.58)
                .opacity(highlighted ? 1.0 : 0.9)

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
        .scaleEffect(
            isDragging ? 0.7
            : isGrabbed ? 1.08
            : isReorderMode && !isDragging ? 0.92
            : highlighted ? 1.2
            : 1.0
        )
        .opacity(isDragging ? 0.2 : 1.0)
        // Window name label — placed AFTER opacity so it stays visible during drag
        .overlay(alignment: .bottom) {
            VStack(spacing: 2) {
                Text(displayName)
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

                if !tags.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(tags.prefix(2)) { tag in
                            Text(tag.name)
                                .font(.system(size: 7, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 36)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule()
                                        .fill(tag.color.opacity(0.85))
                                        .shadow(color: tag.color.opacity(0.5), radius: 1)
                                )
                        }
                        if tags.count > 2 {
                            Text("+\(tags.count - 2)")
                                .font(.system(size: 6, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.9))
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule()
                                        .fill(Color.gray.opacity(0.7))
                                )
                        }
                    }
                }
            }
            .offset(y: -2)
        }
        // Slot indicator — dashed ring showing where the dragged item will land
        .overlay {
            if isDragging {
                Circle()
                    .strokeBorder(Color.blue.opacity(0.6), style: StrokeStyle(lineWidth: 2.5, dash: [5, 3]))
                    .frame(width: size + 6, height: size + 6)
            }
        }
        // Jelly bounce when this bubble shifts to a new slot
        .modifier(JellyBounce(trigger: slotIndex))
        // Keyboard shortcut badge — keycap style
        .overlay(alignment: .topLeading) {
            if let key = kbShortcut, !isInCloseMode {
                let isSpace = key == "␣"
                Text(isSpace ? "Space" : key)
                    .font(.system(size: isSpace ? 8 : 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, isSpace ? 6 : 4)
                    .padding(.vertical, isSpace ? 2.5 : 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: isSpace
                                        ? [Color.orange, Color.orange.opacity(0.6)]
                                        : [Color(white: 0.38), Color(white: 0.18)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.5
                            )
                    )
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1.5)
                    .offset(x: -3, y: -3)
            }
        }
        // Quick launch slot badge — hide in keyboard mode
        .overlay(alignment: .topTrailing) {
            if let slot = quickSlot, !isInCloseMode, kbShortcut == nil {
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
        .animation(.spring(response: 0.2, dampingFraction: 0.75), value: window.position.x)
        .animation(.spring(response: 0.2, dampingFraction: 0.75), value: window.position.y)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isGrabbed)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isDragging)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isReorderMode)
        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: highlighted)
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

    static func displayName(for title: String) -> String {
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

    private var displayName: String {
        Self.displayName(for: window.name)
    }
}
