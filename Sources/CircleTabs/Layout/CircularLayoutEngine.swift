import Foundation

struct CircularLayoutEngine {
    static let mainBubbleRadius: CGFloat = 30
    static let subBubbleRadius: CGFloat = 28
    static let ring1Radius: CGFloat = 110
    static let subAppArcRadius: CGFloat = 95

    // MARK: - Adaptive Sizing

    /// Bubble scale: full size for ≤16 apps, gentle shrink for 17+
    static func bubbleScale(for count: Int) -> CGFloat {
        if count <= 16 { return 1.0 }
        return max(0.78, 16.0 / CGFloat(count))
    }

    /// Effective bubble radius after scaling
    static func effectiveBubbleRadius(for count: Int) -> CGFloat {
        mainBubbleRadius * bubbleScale(for: count)
    }

    /// Adaptive ring radius that grows to fit all apps in a single ring
    static func ringRadius(for count: Int) -> CGFloat {
        let scale = bubbleScale(for: count)
        let bubbleR = mainBubbleRadius * scale
        let gap: CGFloat = max(8, 12 * scale)
        let spacing = bubbleR * 2 + gap
        return max(ring1Radius, CGFloat(count) * spacing / (2 * .pi))
    }

    // MARK: - Layout

    /// Layout all main apps in a single adaptive ring around center
    static func layoutApps(_ apps: inout [AppItem], center: CGPoint) {
        let count = apps.count
        guard count > 0 else { return }

        let scale = bubbleScale(for: count)
        let radius = ringRadius(for: count)

        let angleStep = (2 * Double.pi) / Double(count)
        let startAngle = -Double.pi / 2

        for i in 0..<count {
            let angle = startAngle + angleStep * Double(i)
            apps[i].position = CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
            apps[i].ringIndex = 0
            apps[i].angle = angle
            apps[i].bubbleScale = scale
        }
    }

    /// Layout sub-apps (windows) in an arc beyond the parent app
    static func layoutSubApps(
        _ windows: inout [WindowItem],
        parentPosition: CGPoint,
        parentAngle: Double,
        center: CGPoint
    ) {
        let count = windows.count
        guard count > 0 else { return }

        let minAngularGap = Double(subBubbleRadius * 2 + 8) / Double(subAppArcRadius)
        let neededAngle = Double(count - 1) * minAngularGap
        let maxFanAngle = Double.pi * 1.2
        let fanAngle = count == 1 ? 0 : min(maxFanAngle, neededAngle)

        let startAngle = parentAngle - fanAngle / 2

        for i in 0..<count {
            let angle: Double
            if count == 1 {
                angle = parentAngle
            } else {
                angle = startAngle + fanAngle * Double(i) / Double(count - 1)
            }

            let x = parentPosition.x + subAppArcRadius * cos(angle)
            let y = parentPosition.y + subAppArcRadius * sin(angle)

            windows[i].position = CGPoint(x: x, y: y)
            windows[i].angle = angle
        }
    }

    /// Calculate push-away offsets for non-expanded apps
    static func calculatePushOffsets(
        apps: [AppItem],
        expandedIndex: Int,
        center: CGPoint
    ) -> [CGPoint] {
        guard expandedIndex >= 0, expandedIndex < apps.count else {
            return Array(repeating: .zero, count: apps.count)
        }

        let expandedApp = apps[expandedIndex]
        var offsets = Array(repeating: CGPoint.zero, count: apps.count)

        for i in 0..<apps.count {
            guard i != expandedIndex else { continue }
            let app = apps[i]

            let dx = app.position.x - expandedApp.position.x
            let dy = app.position.y - expandedApp.position.y
            let distance = sqrt(dx * dx + dy * dy)

            if distance < subAppArcRadius + mainBubbleRadius * 3 {
                let pushStrength: CGFloat = max(0, 1 - distance / (subAppArcRadius + mainBubbleRadius * 3))
                let pushDistance = pushStrength * 40

                let awayDx = app.position.x - expandedApp.position.x
                let awayDy = app.position.y - expandedApp.position.y
                let awayDist = max(sqrt(awayDx * awayDx + awayDy * awayDy), 1)

                offsets[i] = CGPoint(
                    x: (awayDx / awayDist) * pushDistance,
                    y: (awayDy / awayDist) * pushDistance
                )
            }
        }

        return offsets
    }

    /// Find the app closest to a given point within a threshold.
    /// Pass `offsets` to account for push-away offsets (visual position = base + offset).
    static func findClosestApp(to point: CGPoint, in apps: [AppItem], offsets: [CGPoint] = [], threshold: CGFloat = 50) -> Int? {
        var closestIndex: Int?
        var closestDistance: CGFloat = .greatestFiniteMagnitude

        for (index, app) in apps.enumerated() {
            let off = offsets.indices.contains(index) ? offsets[index] : .zero
            let dx = point.x - (app.position.x + off.x)
            let dy = point.y - (app.position.y + off.y)
            let distance = sqrt(dx * dx + dy * dy)

            if distance < threshold && distance < closestDistance {
                closestDistance = distance
                closestIndex = index
            }
        }

        return closestIndex
    }

    /// Find the sub-app closest to a given point
    static func findClosestSubApp(to point: CGPoint, in windows: [WindowItem], threshold: CGFloat = 40) -> Int? {
        var closestIndex: Int?
        var closestDistance: CGFloat = .greatestFiniteMagnitude

        for (index, window) in windows.enumerated() {
            let dx = point.x - window.position.x
            let dy = point.y - window.position.y
            let distance = sqrt(dx * dx + dy * dy)

            if distance < threshold && distance < closestDistance {
                closestDistance = distance
                closestIndex = index
            }
        }

        return closestIndex
    }
}
