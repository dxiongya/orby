import SwiftUI

/// Organic jelly wobble — snappy frequency, per-bubble unique phase
struct JellyWobble: ViewModifier {
    let isActive: Bool
    let seed: Int

    func body(content: Content) -> some View {
        if isActive {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = Double(abs(seed) % 1000) / 1000.0 * .pi * 2
                // ~1.5 Hz rotation, ±2.5°
                let rotation = sin(t * 9.5 + phase) * 2.5
                // Faster squish at ~2 Hz, 1.8% amplitude
                let squish = 1.0 + sin(t * 13.0 + phase * 1.3) * 0.018
                content
                    .rotationEffect(.degrees(rotation))
                    .scaleEffect(x: squish, y: 2.0 - squish)
            }
        } else {
            content
        }
    }
}

struct AppBubbleView: View {
    let app: AppItem
    let isHovered: Bool
    let isExpanded: Bool
    let dimLevel: Double
    let offset: CGPoint
    let isInCloseMode: Bool
    var tags: [AppTag] = []
    var quickSlot: Int? = nil
    var kbFocused: Bool = false
    var kbShortcut: String? = nil

    private var size: CGFloat { CircularLayoutEngine.mainBubbleRadius * 2 * app.bubbleScale }
    private var highlighted: Bool { isHovered || kbFocused }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                // Frosted glass circle background
                Circle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .shadow(color: .black.opacity(highlighted ? 0.18 : 0.10), radius: highlighted ? 18 : 12, x: 0, y: highlighted ? 8 : 5)
                    .shadow(color: .white.opacity(0.06), radius: 2, x: 0, y: -1)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(highlighted ? 0.35 : 0.2),
                                        Color.white.opacity(highlighted ? 0.15 : 0.08)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: kbFocused ? 2.5 : 1
                            )
                    )
                    .overlay(
                        // Keyboard focus ring
                        kbFocused ? Circle()
                            .strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 2.5)
                            .shadow(color: Color.accentColor.opacity(0.5), radius: 8)
                        : nil
                    )

                // App icon
                Image(nsImage: app.icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.68, height: size * 0.68)
            }
            .frame(width: size, height: size)
            // Tag labels — inside the scale so they follow the bubble
            .overlay(alignment: .bottom) {
                if !tags.isEmpty && !isInCloseMode {
                    HStack(spacing: 3) {
                        ForEach(tags.prefix(2)) { tag in
                            Text(tag.name)
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 52)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(tag.color.opacity(0.85))
                                        .shadow(color: tag.color.opacity(0.5), radius: 2)
                                )
                        }
                        if tags.count > 2 {
                            Text("+\(tags.count - 2)")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.9))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.gray.opacity(0.7))
                                )
                        }
                    }
                    .offset(y: -3)
                }
            }
            .scaleEffect(highlighted ? 1.18 : 1.0)
            // Keyboard shortcut badge — keycap style
            .overlay(alignment: .topLeading) {
                if let key = kbShortcut, !isInCloseMode {
                    let isSpace = key == "␣"
                    Text(isSpace ? "Space" : key)
                        .font(.system(size: isSpace ? 9 : 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, isSpace ? 7 : 5)
                        .padding(.vertical, isSpace ? 3.5 : 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: isSpace
                                            ? [Color.accentColor, Color.accentColor.opacity(0.6)]
                                            : [Color(white: 0.38), Color(white: 0.18)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 0.5
                                )
                        )
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                        .offset(x: -4, y: -4)
                }
            }
            // Quick launch slot badge — hide in keyboard mode
            .overlay(alignment: .topTrailing) {
                if let slot = quickSlot, !isInCloseMode, kbShortcut == nil {
                    Text("\(slot)")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .frame(width: 18, height: 18)
                        .background(
                            Circle()
                                .fill(Color.blue.opacity(0.9))
                                .shadow(color: .black.opacity(0.3), radius: 2)
                        )
                        .offset(x: 4, y: -4)
                }
            }
            // Close badge — rendered OUTSIDE the scaled frame so it stays prominent
            .overlay(alignment: .topLeading) {
                if isInCloseMode {
                    closeBadge
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
            .modifier(JellyWobble(isActive: isInCloseMode, seed: app.id.hashValue))

            // Name label — show on hover, expand, or keyboard focus
            if !isInCloseMode && (highlighted || isExpanded) {
                Text(app.name)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.5))
                    )
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .opacity(1.0 - dimLevel * 0.6)
        .position(
            x: app.position.x + offset.x,
            y: app.position.y + offset.y
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: highlighted)
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: offset.x)
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: offset.y)
        .animation(.easeInOut(duration: 0.2), value: dimLevel)
    }

    private var closeBadge: some View {
        let badgeSize: CGFloat = isHovered ? 26 : 20
        return ZStack {
            Circle()
                .fill(Color.red)
                .frame(width: badgeSize, height: badgeSize)
                .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 1)
                .shadow(color: .red.opacity(isHovered ? 0.5 : 0.2), radius: isHovered ? 8 : 4)
            Image(systemName: "xmark")
                .font(.system(size: isHovered ? 12 : 9, weight: .bold))
                .foregroundColor(.white)
        }
        .offset(x: -2, y: -2)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isHovered)
    }
}
