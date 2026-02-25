import SwiftUI

struct SubAppBubbleView: View {
    let window: WindowItem
    let parentIcon: NSImage
    let isHovered: Bool
    let showLabel: Bool

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
        }
        .frame(width: size, height: size)
        .scaleEffect(isHovered ? 1.2 : 1.0)
        // Tooltip label — only on hover, floats below without affecting layout
        .overlay(alignment: .bottom) {
            if showLabel {
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

    /// Parse window title — prioritize workspace/project name.
    private var displayName: String {
        let title = window.name
        guard !title.isEmpty else { return "Window" }

        // Priority 1: workspace name after em dash (Cursor/VS Code: "file — workspace")
        for sep in [" — ", "—", " \u{2013} ", "\u{2013}"] {
            if let range = title.range(of: sep, options: .backwards) {
                let workspace = String(title[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !workspace.isEmpty { return workspace }
            }
        }

        // Priority 2: after hyphen (common: "file - ProjectName")
        if let range = title.range(of: " - ", options: .backwards) {
            let workspace = String(title[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !workspace.isEmpty { return workspace }
        }

        // Fallback: full title
        return title
    }
}
