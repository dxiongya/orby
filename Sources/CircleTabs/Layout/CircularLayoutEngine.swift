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

    // MARK: - Available Arc

    /// Compute the longest contiguous arc of on-screen angles at a given radius from center.
    /// `safeBounds` is the usable screen rect (excluding dock & menu bar) in view coordinates.
    /// Returns (startAngle, arcSpan). Full circle → arcSpan ≈ 2π.
    static func computeAvailableArc(
        center: CGPoint,
        radius: CGFloat,
        margin: CGFloat,
        safeBounds: CGRect
    ) -> (startAngle: Double, arcSpan: Double) {
        let n = 360
        var valid = [Bool](repeating: false, count: n)

        for i in 0..<n {
            let angle = Double(i) / Double(n) * 2 * .pi - .pi
            let x = center.x + radius * cos(angle)
            let y = center.y + radius * sin(angle)
            valid[i] = x >= safeBounds.minX + margin && x <= safeBounds.maxX - margin
                    && y >= safeBounds.minY + margin && y <= safeBounds.maxY - margin
        }

        // Find longest contiguous run (double-array for wrap-around)
        let doubled = valid + valid
        var bestStart = 0, bestLen = 0, curStart = 0, curLen = 0

        for i in 0..<doubled.count {
            if doubled[i] {
                if curLen == 0 { curStart = i }
                curLen += 1
                if curLen > bestLen { bestLen = curLen; bestStart = curStart }
            } else {
                curLen = 0
            }
        }

        bestLen = min(bestLen, n)

        if bestLen == 0 {
            // Fallback: arc toward screen center
            let dx = safeBounds.midX - center.x
            let dy = safeBounds.midY - center.y
            return (atan2(dy, dx) - .pi / 4, .pi / 2)
        }

        let startAngle = Double(bestStart % n) / Double(n) * 2 * .pi - .pi
        let arcSpan = Double(bestLen) / Double(n) * 2 * .pi

        return (startAngle, arcSpan)
    }

    // MARK: - Layout

    /// Layout apps around center. Each ring independently decides:
    /// - Full circle available → perfect circular ring
    /// - Partial arc (near edge) → grow radius, distribute in visible arc
    /// ≤16 apps → 1 ring. >16 apps → 2 rings (half each).
    static func layoutApps(_ apps: inout [AppItem], center: CGPoint, safeBounds: CGRect) {
        let count = apps.count
        guard count > 0 else { return }

        let scale = bubbleScale(for: count)
        let bubbleR = mainBubbleRadius * scale
        let gap: CGFloat = max(8, 12 * scale)
        let margin = bubbleR + 12
        let spacing = bubbleR * 2 + gap
        let rGap = bubbleR * 2 + 16
        let maxRadius = min(safeBounds.width, safeBounds.height) * 0.8

        // Ring distribution: ≤16 → 1 ring; >16 → 2 rings
        let numRings = count <= 16 ? 1 : 2
        var ringCounts: [Int]
        if numRings == 1 {
            ringCounts = [count]
        } else {
            let half = count / 2
            ringCounts = [half, count - half]
        }

        var appIndex = 0
        var prevRadius: CGFloat = 0

        for ring in 0..<numRings {
            let n = ringCounts[ring]
            let neededLength = CGFloat(n) * spacing

            // Base radius for this ring
            var radius: CGFloat
            if ring == 0 {
                radius = max(ring1Radius, neededLength / (2 * .pi))
            } else {
                radius = prevRadius + rGap
            }

            // Check if full circle fits at this radius
            let arc = computeAvailableArc(center: center, radius: radius, margin: margin, safeBounds: safeBounds)

            if arc.arcSpan >= 2 * .pi * 0.95 {
                // NORMAL: perfect circle
                prevRadius = radius
                let step = (2 * .pi) / Double(n)
                for j in 0..<n {
                    let angle = -.pi / 2 + step * Double(j)
                    apps[appIndex].position = CGPoint(
                        x: center.x + radius * cos(angle),
                        y: center.y + radius * sin(angle)
                    )
                    apps[appIndex].ringIndex = ring
                    apps[appIndex].angle = angle
                    apps[appIndex].bubbleScale = scale
                    appIndex += 1
                }
            } else {
                // EDGE: grow radius until visible arc fits all apps
                var r = radius
                var a = arc
                for _ in 0..<30 {
                    let availableLength = r * a.arcSpan
                    if availableLength >= neededLength || r >= maxRadius { break }
                    r += 15
                    a = computeAvailableArc(center: center, radius: r, margin: margin, safeBounds: safeBounds)
                }
                prevRadius = r

                for j in 0..<n {
                    let angle: Double
                    if n == 1 {
                        angle = a.startAngle + a.arcSpan / 2
                    } else {
                        let step = a.arcSpan / Double(n)
                        angle = a.startAngle + step * 0.5 + step * Double(j)
                    }
                    apps[appIndex].position = CGPoint(
                        x: center.x + r * cos(angle),
                        y: center.y + r * sin(angle)
                    )
                    apps[appIndex].ringIndex = ring
                    apps[appIndex].angle = angle
                    apps[appIndex].bubbleScale = scale
                    appIndex += 1
                }
            }
        }
    }

    /// Layout sub-apps (windows) in an arc around the parent app.
    /// Uses available arc so sub-apps stay on screen. Fan is centered on parentAngle.
    static func layoutSubApps(
        _ windows: inout [WindowItem],
        parentPosition: CGPoint,
        parentAngle: Double,
        center: CGPoint,
        safeBounds: CGRect
    ) {
        let count = windows.count
        guard count > 0 else { return }

        let margin = subBubbleRadius + 12
        let arc = computeAvailableArc(center: parentPosition, radius: subAppArcRadius, margin: margin, safeBounds: safeBounds)

        let minAngularGap = Double(subBubbleRadius * 2 + 8) / Double(subAppArcRadius)
        let neededAngle = Double(count - 1) * minAngularGap
        let maxFanAngle = Double.pi * 1.2
        let fanAngle = count == 1 ? 0 : min(maxFanAngle, min(arc.arcSpan * 0.9, neededAngle))

        // Center fan on parentAngle, clamped within available arc
        let arcEnd = arc.startAngle + arc.arcSpan
        var fanCenter = parentAngle
        let halfFan = fanAngle / 2
        if arc.arcSpan < 2 * .pi * 0.95 {
            fanCenter = max(arc.startAngle + halfFan, min(arcEnd - halfFan, fanCenter))
        }

        let fanStart = fanCenter - halfFan

        for i in 0..<count {
            let angle: Double
            if count == 1 {
                angle = fanCenter
            } else {
                angle = fanStart + fanAngle * Double(i) / Double(count - 1)
            }

            windows[i].position = CGPoint(
                x: parentPosition.x + subAppArcRadius * cos(angle),
                y: parentPosition.y + subAppArcRadius * sin(angle)
            )
            windows[i].angle = angle
        }
    }

    /// Clamp push offsets so visual positions (base + offset) stay within safe bounds
    static func clampPushOffsets(
        _ offsets: inout [CGPoint],
        apps: [AppItem],
        safeBounds: CGRect,
        margin: CGFloat = 10
    ) {
        for i in 0..<min(offsets.count, apps.count) {
            let r = mainBubbleRadius * apps[i].bubbleScale + margin
            let vx = apps[i].position.x + offsets[i].x
            let vy = apps[i].position.y + offsets[i].y
            if vx < safeBounds.minX + r { offsets[i].x += (safeBounds.minX + r - vx) }
            if vx > safeBounds.maxX - r { offsets[i].x -= (vx - (safeBounds.maxX - r)) }
            if vy < safeBounds.minY + r { offsets[i].y += (safeBounds.minY + r - vy) }
            if vy > safeBounds.maxY - r { offsets[i].y -= (vy - (safeBounds.maxY - r)) }
        }
    }

    // MARK: - Push Offsets

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
