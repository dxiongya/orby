import SwiftUI

struct AppBubbleView: View {
    let app: AppItem
    let isHovered: Bool
    let isExpanded: Bool
    let dimLevel: Double
    let offset: CGPoint

    private var size: CGFloat { CircularLayoutEngine.mainBubbleRadius * 2 * app.bubbleScale }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                // Frosted glass circle background
                Circle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .shadow(color: .black.opacity(isHovered ? 0.18 : 0.10), radius: isHovered ? 18 : 12, x: 0, y: isHovered ? 8 : 5)
                    .shadow(color: .white.opacity(0.06), radius: 2, x: 0, y: -1)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isHovered ? 0.35 : 0.2),
                                        Color.white.opacity(isHovered ? 0.15 : 0.08)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )

                // App icon — large and prominent
                Image(nsImage: app.icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.68, height: size * 0.68)
            }
            .frame(width: size, height: size)
            .scaleEffect(isHovered ? 1.18 : 1.0)

            // Name label
            if isHovered || isExpanded {
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
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: offset.x)
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: offset.y)
        .animation(.easeInOut(duration: 0.2), value: dimLevel)
    }
}
