import Foundation
import CoreGraphics

nonisolated enum BandGeometry {
    /// Opposite corners let one pointer supply the upper and lower band edges.
    static func pointerRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    static func canStart(points: [CGPoint], initial: [CGPoint], current: [CGPoint]) -> Bool {
        guard points.count >= 5, initial.count == 2, current.count == 2,
              abs(initial[0].y - initial[1].y) >= 24,
              abs(initial[0].y - initial[1].y) <= 500,
              abs(initial[0].x - initial[1].x) <= 56,
              let first = points.first, let last = points.last else { return false }
        let dx = last.x - first.x
        guard abs(dx) >= 44 else { return false }
        let travel = zip(points, points.dropFirst()).reduce(CGFloat.zero) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
        return abs(dx) >= travel * 0.96 && remainsHorizontal(initial: initial, current: current)
            && points.allSatisfy { abs($0.y - first.y) <= 12 }
    }

    static func remainsHorizontal(initial: [CGPoint], current: [CGPoint]) -> Bool {
        guard initial.count == 2, current.count == 2 else { return false }
        let a = CGPoint(x: current[0].x - initial[0].x, y: current[0].y - initial[0].y)
        let b = CGPoint(x: current[1].x - initial[1].x, y: current[1].y - initial[1].y)
        return abs(a.y) <= 16 && abs(b.y) <= 16 && abs(a.x - b.x) <= 18
    }

    static func rect(initial: [CGPoint], current: [CGPoint]) -> CGRect {
        guard initial.count == 2, current.count == 2 else { return .zero }
        let startX = (initial[0].x + initial[1].x) / 2
        let endX = (current[0].x + current[1].x) / 2
        let ys = (initial + current).map(\.y)
        return CGRect(x: min(startX, endX), y: ys.min()!, width: abs(endX - startX), height: ys.max()! - ys.min()!)
    }
}
