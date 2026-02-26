import SwiftUI

struct ConnectionLineView: View {
    let from: CGPoint
    let to: CGPoint
    var lineWidth: CGFloat = 2.0
    var opacity: Double = 0.3
    var glowColor: Color = .white

    var body: some View {
        Canvas { context, size in
            let midX = (from.x + to.x) / 2
            let midY = (from.y + to.y) / 2
            let dx = to.x - from.x, dy = to.y - from.y
            let control = CGPoint(x: midX + (-dy * 0.1), y: midY + (dx * 0.1))

            var path = Path()
            path.move(to: from)
            path.addQuadCurve(to: to, control: control)

            // Soft glow
            context.stroke(path,
                with: .color(glowColor.opacity(opacity * 0.4)),
                style: StrokeStyle(lineWidth: lineWidth + 4, lineCap: .round))

            // Main line
            context.stroke(path,
                with: .color(Color.white.opacity(opacity * 0.9)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
        .allowsHitTesting(false)
    }
}
