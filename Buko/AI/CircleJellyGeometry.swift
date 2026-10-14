import Foundation
import CoreGraphics

/// Shared geometry for the painted droplet trail, boundary-inward fill, and
/// damped transformation into the recognized phrase's rounded rectangle.
nonisolated enum CircleJellyGeometry {
    static let sampleCount = 96

    struct Boundary {
        let center: CGPoint
        let radii: [CGFloat]
    }

    static func centroid(_ points: [CGPoint]) -> CGPoint? {
        guard points.count >= 3 else { return nil }
        // Translate first, avoiding cancellation with large document coordinates.
        let origin = points[0]
        var area: CGFloat = 0, x: CGFloat = 0, y: CGFloat = 0
        for index in points.indices {
            let a = points[index] - origin, b = points[(index + 1) % points.count] - origin
            let cross = a.x * b.y - b.x * a.y
            area += cross; x += (a.x + b.x) * cross; y += (a.y + b.y) * cross
        }
        guard abs(area) > 0.01 else { return nil }
        return CGPoint(x: origin.x + x / (3 * area), y: origin.y + y / (3 * area))
    }

    static func boundary(_ points: [CGPoint]) -> Boundary? {
        guard let center = centroid(points), CircleGeometry.path(points).contains(center) else { return nil }
        let radii = (0..<sampleCount).map { index -> CGFloat in
            let theta = angle(at: index), ray = CGPoint(x: cos(theta), y: sin(theta))
            var hits: [CGFloat] = []
            for i in points.indices {
                let a = points[i] - center, edge = points[(i + 1) % points.count] - points[i]
                let cross = ray.x * edge.y - ray.y * edge.x
                guard abs(cross) > 0.00001 else { continue }
                let distance = (a.x * edge.y - a.y * edge.x) / cross
                let along = (a.x * ray.y - a.y * ray.x) / cross
                if distance > 0, along >= 0, along <= 1 { hits.append(distance) }
            }
            return hits.min() ?? 0
        }
        guard radii.allSatisfy({ $0 > 0 && $0.isFinite }) else { return nil }
        return Boundary(center: center, radii: radii)
    }

    static let brushRadius: CGFloat = 12
    static let closeDuration: TimeInterval = 0.42
    static let fillDuration: TimeInterval = 0.82
    static let morphDuration: TimeInterval = 0.9

    /// Release continues the exact live brush, sweeps only the missing arc,
    /// then contracts a hole inside that same outline. Cached geometry avoids
    /// rebuilding/raycasting the whole selection on every animation frame.
    struct Release {
        let basePaint: CGPath
        let finalPaint: CGPath
        let completed: [CGPoint]
        let center: CGPoint
        let arc: [CGPoint]
        let distances: [CGFloat]
        let initialBlob: [CGPoint]
        let initialHead: CGPoint
        let tail: CGPoint?

        init(traced: [CGPoint], completed: [CGPoint], droplet: CircleDropletDynamics, time: TimeInterval) {
            self.completed = completed
            center = centroid(completed) ?? CircleGeometry.path(completed).boundingBoxOfPath.origin
            basePaint = paint(Array(traced.dropLast()))
            finalPaint = paint(completed)
            initialHead = droplet.sample(at: time).position
            initialBlob = droplet.contour(at: time, reduceMotion: false)
            tail = traced.dropLast().last
            // completedLoop preserves the raw samples before appending the gap.
            arc = [initialHead] + Array(completed.dropFirst(max(0, traced.count - 1)))
            var lengths: [CGFloat] = [0]
            for i in 1..<arc.count {
                lengths.append(lengths[i - 1] + CircleGeometry.distance(arc[i - 1], arc[i]))
            }
            distances = lengths
        }

        func closingPoints(progress: CGFloat) -> [CGPoint] {
            let distance = (distances.last ?? 0) * min(1, max(0, progress))
            var result = [initialHead]
            for i in 1..<arc.count {
                if distances[i] <= distance { result.append(arc[i]); continue }
                let fraction = (distance - distances[i - 1]) / max(0.0001, distances[i] - distances[i - 1])
                result.append(CGPoint(x: arc[i - 1].x + (arc[i].x - arc[i - 1].x) * fraction,
                                      y: arc[i - 1].y + (arc[i].y - arc[i - 1].y) * fraction))
                break
            }
            return result
        }

        func path(age: TimeInterval, reduceMotion: Bool) -> CGPath {
            if !reduceMotion, age < closeDuration {
                let progress = smoothstep(CGFloat(max(0, age) / closeDuration))
                var swept = closingPoints(progress: progress)
                if let releasedPoint = arc.dropFirst().first {
                    swept[0] = CGPoint(x: initialHead.x + (releasedPoint.x - initialHead.x) * progress,
                                       y: initialHead.y + (releasedPoint.y - initialHead.y) * progress)
                }
                let head = swept.last ?? initialHead
                let blob = initialBlob.enumerated().map { i, p in
                    let angle = CGFloat(i) * 2 * .pi / CGFloat(initialBlob.count)
                    let target = point(center: .zero, angle: angle, radius: brushRadius)
                    return CGPoint(x: head.x + (p.x - initialHead.x) * (1 - progress) + target.x * progress,
                                   y: head.y + (p.y - initialHead.y) * (1 - progress) + target.y * progress)
                }
                return basePaint.union(paint((tail.map { [$0] } ?? []) + swept)).union(smoothPath(blob))
            }
            let progress = reduceMotion ? 1 : fillProgress(CGFloat((age - closeDuration) / fillDuration))
            guard progress > 0 else { return finalPaint }
            let fill = CGMutablePath()
            fill.addPath(CircleGeometry.path(completed))
            if progress < 1 {
                let hole = pow(1 - progress, 1.25)
                let inner = completed.reversed().map { p in
                    let theta = atan2(p.y - center.y, p.x - center.x)
                    let ripple = 1 + 0.035 * sin(theta * 3 + CGFloat(age) * 9) * sin(.pi * progress)
                    let radius = hypot(p.x - center.x, p.y - center.y)
                    let inset = max(0, radius - brushRadius) / max(1, radius)
                    return CGPoint(x: center.x + (p.x - center.x) * inset * hole * ripple,
                                   y: center.y + (p.y - center.y) * inset * hole * ripple)
                }
                fill.addPath(smoothPath(inner))
            }
            return finalPaint.union(fill)
        }
    }

    static func roundedRectangle(_ rect: CGRect) -> Boundary {
        let half = CGSize(width: rect.width / 2, height: rect.height / 2)
        let corner = min(14, min(half.width, half.height))
        let radii = (0..<sampleCount).map { i -> CGFloat in
            let theta = angle(at: i)
            var low: CGFloat = 0, high = hypot(half.width, half.height)
            for _ in 0..<20 {
                let r = (low + high) / 2
                let x = abs(cos(theta) * r) - half.width + corner
                let y = abs(sin(theta) * r) - half.height + corner
                let distance = hypot(max(x, 0), max(y, 0)) + min(max(x, y), 0) - corner
                if distance > 0 { high = r } else { low = r }
            }
            return (low + high) / 2
        }
        return Boundary(center: CGPoint(x: rect.midX, y: rect.midY), radii: radii)
    }

    static func paint(_ points: [CGPoint]) -> CGPath {
        let line = CGMutablePath()
        guard let first = points.first else { return line }
        line.move(to: first)
        for point in points.dropFirst() { line.addLine(to: point) }
        return line.copy(strokingWithWidth: brushRadius * 2, lineCap: .round, lineJoin: .round, miterLimit: 2)
    }

    /// A hollow boundary shrinks its unfilled interior toward the centroid.
    /// Opposite winding gives native glass an actual hole, not an opacity mask.
    static func inwardFill(_ boundary: Boundary, age: TimeInterval, reduceMotion: Bool) -> CGPath {
        let t = max(0, age - closeDuration)
        let progress = reduceMotion ? 1 : smoothstep(CGFloat(t / fillDuration))
        let hole = pow(1 - progress, 1.25)
        let outer = (0..<sampleCount).map { i -> CGPoint in
            let theta = angle(at: i)
            let wobble = reduceMotion ? 0 : 1.8 * sin(CGFloat(t) * 18) * exp(-8 * CGFloat(t)) * (1 - progress)
            return point(center: boundary.center, angle: theta, radius: boundary.radii[i] + brushRadius + wobble)
        }
        let path = CGMutablePath()
        path.addPath(smoothPath(outer))
        if hole > 0.0001 {
            let inner = (0..<sampleCount).reversed().map { i -> CGPoint in
                let theta = angle(at: i)
                let ripple = 1 + 0.06 * sin(3 * theta + CGFloat(t) * 9) * sin(.pi * progress)
                return point(center: boundary.center, angle: theta,
                             radius: max(0, boundary.radii[i] - brushRadius) * hole * ripple)
            }
            path.addPath(smoothPath(inner))
        }
        return path
    }

    /// Edges enter the mold first. Delayed corner springs bulge slightly, while
    /// an area-preserving squeeze adds a short, damped soft-body oscillation.
    static func moldedContour(from source: Boundary, to target: Boundary,
                              age: TimeInterval, reduceMotion: Bool) -> [CGPoint] {
        let t = max(0, CGFloat(age))
        let finish = reduceMotion || age >= morphDuration
        let settling = smoothstep((t - 0.65) / 0.25)
        let centerProgress = finish ? 1 : spring(t, omega: 15, damping: 0.7)
        let center = CGPoint(x: source.center.x + (target.center.x - source.center.x) * centerProgress,
                             y: source.center.y + (target.center.y - source.center.y) * centerProgress)
        let squeeze = finish ? 1 : 1 + 0.09 * exp(-5 * t) * sin(18 * t) * (1 - settling)
        let halfWidth = target.radii[0], halfHeight = target.radii[sampleCount / 4]
        return (0..<sampleCount).map { i in
            let theta = angle(at: i), radius = target.radii[i]
            let corner = pow(abs(cos(theta) * radius / halfWidth * sin(theta) * radius / halfHeight), 4)
            let response = spring(max(0, t - 0.045 * corner), omega: 13, damping: 0.56)
            let blend = finish ? 1 : response + (1 - response) * settling
            let bulge = finish ? 0 : 5 * corner * exp(-5 * t) * sin(15 * t) * (1 - settling)
            let r = source.radii[i] + brushRadius + (radius - source.radii[i] - brushRadius) * blend + bulge
            return CGPoint(x: center.x + cos(theta) * r * squeeze,
                           y: center.y + sin(theta) * r / squeeze)
        }
    }

    static func spring(_ t: CGFloat, omega: CGFloat, damping: CGFloat) -> CGFloat {
        let root = sqrt(1 - damping * damping)
        return 1 - exp(-damping * omega * t) *
            (cos(omega * root * t) + damping / root * sin(omega * root * t))
    }

    static func smoothPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard points.count > 2, let first = points.first, let last = points.last else { return path }
        path.move(to: CGPoint(x: (first.x + last.x) / 2, y: (first.y + last.y) / 2))
        for i in points.indices {
            let next = points[(i + 1) % points.count], p = points[i]
            path.addQuadCurve(to: CGPoint(x: (p.x + next.x) / 2, y: (p.y + next.y) / 2), control: p)
        }
        path.closeSubpath()
        return path
    }

    static func point(center: CGPoint, angle: CGFloat, radius: CGFloat) -> CGPoint {
        CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }
    static func angle(at index: Int) -> CGFloat { CGFloat(index) * 2 * .pi / CGFloat(sampleCount) }
    // A normalized critically damped response closes the hole without reversal
    // or a pause hidden beneath the thick painted boundary.
    private static func fillProgress(_ value: CGFloat) -> CGFloat {
        let t = min(1, max(0, value))
        return (1 - (1 + 6 * t) * exp(-6 * t)) / (1 - 7 * exp(-6))
    }

    private static func smoothstep(_ value: CGFloat) -> CGFloat {
        let t = min(1, max(0, value)); return t * t * (3 - 2 * t)
    }
}

/// A damped position/velocity spring evaluated analytically between touch events.
/// The renderer can keep moving after the finger stops without mutating view state
/// every frame. Retargeting preserves momentum rather than restarting a tween.
nonisolated struct CircleDropletDynamics {
    var position: CGPoint
    var velocity = CGPoint.zero
    var target: CGPoint
    var updatedAt: TimeInterval

    init(at point: CGPoint, time: TimeInterval) { position = point; target = point; updatedAt = time }

    func sample(at time: TimeInterval) -> (position: CGPoint, velocity: CGPoint) {
        let t = CGFloat(max(0, time - updatedAt))
        let omega: CGFloat = 24, damping: CGFloat = 0.64
        let decay = damping * omega, frequency = omega * sqrt(1 - damping * damping)
        func axis(_ p: CGFloat, _ v: CGFloat, _ goal: CGFloat) -> (CGFloat, CGFloat) {
            let a = p - goal, b = (v + decay * a) / frequency
            let c = cos(frequency * t), s = sin(frequency * t), e = exp(-decay * t)
            return (goal + e * (a * c + b * s), e * ((b * frequency - decay * a) * c - (a * frequency + decay * b) * s))
        }
        let x = axis(position.x, velocity.x, target.x), y = axis(position.y, velocity.y, target.y)
        return (CGPoint(x: x.0, y: y.0), CGPoint(x: x.1, y: y.1))
    }

    mutating func follow(_ point: CGPoint, at time: TimeInterval) {
        let current = sample(at: time)
        position = current.position; velocity = current.velocity; target = point; updatedAt = time
        // A short tether keeps the droplet under the finger even after fast jumps.
        let d = hypot(position.x - target.x, position.y - target.y)
        if d > 18 {
            position = CGPoint(x: target.x + (position.x - target.x) * 18 / d,
                               y: target.y + (position.y - target.y) * 18 / d)
        }
    }

    func contour(at time: TimeInterval, reduceMotion: Bool) -> [CGPoint] {
        let value = sample(at: time)
        let center = reduceMotion ? target : value.position
        let speed = hypot(value.velocity.x, value.velocity.y)
        let lag = hypot(center.x - target.x, center.y - target.y)
        let stretch = reduceMotion ? 0 : min(0.6, speed / 1100 + lag / 65)
        let heading = atan2(value.velocity.y + (target.y - center.y) * 12,
                            value.velocity.x + (target.x - center.x) * 12)
        return (0..<48).map { i in
            let angle = CGFloat(i) * 2 * .pi / 48
            let r = 24 * (1 + stretch * cos(2 * (angle - heading)) + 0.12 * stretch * sin(3 * (angle - heading)))
            return CircleJellyGeometry.point(center: center, angle: angle, radius: r)
        }
    }
}

private extension CGPoint {
    nonisolated static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
}
