import UIKit
import UIKit.UIGestureRecognizerSubclass

/// A short arbitration window distinguishes a curving two-finger translation
/// from a straight pan or changing finger separation (pinch). Pencil never enters.
final class CircleGestureRecognizer: UIGestureRecognizer {
    var singleFinger = false
    var preview: (([CGPoint]) -> Void)?
    private(set) var points: [CGPoint] = []
    private var fingers: [UITouch] = []
    private var initialSeparation: CGFloat = 0
    private var travel: CGFloat = 0
    private var lifting = false
    private var releasedFingers: Set<UITouch> = []

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touches.allSatisfy({ $0.type == .direct }) else { state = .failed; return }
        guard !lifting else { state = .cancelled; return }
        fingers.append(contentsOf: touches)
        let required = singleFinger ? 1 : 2
        guard fingers.count <= required else { state = .failed; return }
        guard fingers.count == required else { points = [center]; return }
        initialSeparation = separation
        points = [center]
        if singleFinger { state = .began; preview?(points) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard state == .possible || state == .began || state == .changed else { return }
        guard !lifting else { return }
        guard fingers.count == (singleFinger ? 1 : 2) else {
            // Allow slightly staggered finger placement without delaying an
            // ordinary pan beyond its normal touch slop.
            if let start = points.first, CircleGeometry.distance(start, center) < 8 { return }
            state = .failed; return
        }
        if !singleFinger, abs(separation / max(1, initialSeparation) - 1) > 0.16 {
            state = state == .possible ? .failed : .cancelled; return
        }
        let point = center
        guard let previous = points.last, CircleGeometry.distance(previous, point) >= 2 else { return }
        travel += CircleGeometry.distance(previous, point)
        points.append(point)
        if points.count > 700 { state = .cancelled; return }
        if state == .possible {
            // Detect curvature without requiring a completed circle. Until this
            // decision UIScrollView retains the touches through failure dependencies.
            if travel >= 26, points.count >= 5 {
                let a = points[0], b = points[points.count / 2], c = point
                let u = CGPoint(x: b.x - a.x, y: b.y - a.y)
                let v = CGPoint(x: c.x - b.x, y: c.y - b.y)
                let turn = abs(atan2(u.x * v.y - u.y * v.x, u.x * v.x + u.y * v.y))
                if turn > 0.20 { state = .began }
                else if travel > 140 { state = .failed; return }
            }
        } else { state = .changed }
        if state == .began || state == .changed {
            preview?(points)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard state == .possible || state == .began || state == .changed else { return }
        // Freeze the two-finger midpoint at the first lift. A trailing finger
        // cannot move the selection; completion waits until both are released.
        if !lifting, let last = points.last, CircleGeometry.distance(last, center) >= 2 {
            points.append(center)
            if state == .began || state == .changed { preview?(points) }
        }
        lifting = true
        releasedFingers.formUnion(touches)
        guard fingers.allSatisfy({ releasedFingers.contains($0) }) else { return }
        if state == .began || state == .changed {
            if let completed = CircleGeometry.completedLoop(points) {
                points = completed
                state = .ended
            } else { state = .cancelled }
        } else { state = .failed }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .cancelled }
    override func reset() { fingers = []; points = []; travel = 0; initialSeparation = 0; lifting = false; releasedFingers = [] }
    private var center: CGPoint {
        let positions = fingers.map { $0.location(in: view) }
        return CGPoint(x: positions.map(\.x).reduce(0, +) / CGFloat(positions.count),
                       y: positions.map(\.y).reduce(0, +) / CGFloat(positions.count))
    }
    private var separation: CGFloat {
        fingers.count == 2 ? CircleGeometry.distance(fingers[0].location(in: view), fingers[1].location(in: view)) : 1
    }
}
