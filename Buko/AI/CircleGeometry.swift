import Foundation
import CoreGraphics

/// Thresholds are in screen points; polygon coordinates are supplied by the caller.
nonisolated enum CircleGeometry {
    static func path(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }

    static func isLoop(_ points: [CGPoint]) -> Bool {
        guard points.count >= 12, let first = points.first, let last = points.last else { return false }
        let bounds = path(points).boundingBoxOfPath
        guard bounds.width >= 40, bounds.height >= 28 else { return false }
        let length = zip(points, points.dropFirst()).reduce(CGFloat.zero) { $0 + distance($1.0, $1.1) }
        let area = abs(zip(points, points.dropFirst() + [first]).reduce(CGFloat.zero) {
            $0 + $1.0.x * $1.1.y - $1.1.x * $1.0.y
        }) / 2
        return distance(first, last) <= max(26, min(bounds.width, bounds.height) * 0.48)
            && length >= 110 && length < 3.5 * (bounds.width + bounds.height)
            && area > bounds.width * bounds.height * 0.38
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}
