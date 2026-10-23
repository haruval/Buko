import UIKit
import UIKit.UIGestureRecognizerSubclass

/// A short arbitration window distinguishes a curving two-finger translation
/// from a straight pan or changing finger separation (pinch). Pencil never enters.
final class CircleGestureRecognizer: UIGestureRecognizer {
    var singleFinger = false
    var singleFingerBand = false
    var bandEnabled = false
    var bandPreview: ((CGRect) -> Void)?
    private(set) var isBand = false
    private(set) var bandRect = CGRect.zero
    private var initialFingers: [CGPoint] = []
    var preview: (([CGPoint]) -> Void)?
    private(set) var points: [CGPoint] = []
    private var fingers: [UITouch] = []
    private var initialSeparation: CGFloat = 0
    private var travel: CGFloat = 0
    private var lifting = false
    private var releasedFingers: Set<UITouch> = []

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touches.allSatisfy({ $0.type == .direct }) else { reject(); return }
        guard !lifting else { state = .cancelled; return }
        fingers.append(contentsOf: touches)
        let required = singleFinger || singleFingerBand ? 1 : 2
        guard fingers.count <= required else { reject(); return }
        guard fingers.count == required else { points = [center]; return }
        initialSeparation = separation
        initialFingers = fingers.map { $0.location(in: view) }
        points = [center]
        if singleFingerBand {
            isBand = true
            bandRect = BandGeometry.pointerRect(from: center, to: center)
            state = .began
        } else if singleFinger { state = .began; preview?(points) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard state == .possible || state == .began || state == .changed else { return }
        guard !lifting else { return }
        guard fingers.count == (singleFinger || singleFingerBand ? 1 : 2) else {
            // Allow slightly staggered finger placement without delaying an
            // ordinary pan beyond its normal touch slop.
            if let start = points.first, CircleGeometry.distance(start, center) < 8 { return }
            state = .failed; return
        }
        if !singleFinger, !singleFingerBand, abs(separation / max(1, initialSeparation) - 1) > 0.16 {
            state = state == .possible ? .failed : .cancelled; return
        }
        let point = center
        guard let previous = points.last, CircleGeometry.distance(previous, point) >= 2 else { return }
        travel += CircleGeometry.distance(previous, point)
        points.append(point)
        if points.count > 700 { state = .cancelled; return }
        let current = fingers.map { $0.location(in: view) }
        if isBand {
            if singleFingerBand, let start = points.first {
                bandRect = BandGeometry.pointerRect(from: start, to: point)
            } else {
                guard BandGeometry.remainsHorizontal(initial: initialFingers, current: current) else { state = .cancelled; return }
                bandRect = BandGeometry.rect(initial: initialFingers, current: current)
            }
            state = .changed; bandPreview?(bandRect); return
        }
        if state == .possible {
            // Detect curvature without requiring a completed circle. Until this
            // decision UIScrollView retains the touches through failure dependencies.
            if travel >= 26, points.count >= 5 {
                let a = points[0], b = points[points.count / 2], c = point
                let u = CGPoint(x: b.x - a.x, y: b.y - a.y)
                let v = CGPoint(x: c.x - b.x, y: c.y - b.y)
                let turn = abs(atan2(u.x * v.y - u.y * v.x, u.x * v.x + u.y * v.y))
                if turn > 0.20 { state = .began }
                else if bandEnabled, !singleFinger,
                        BandGeometry.canStart(points: points, initial: initialFingers, current: current) {
                    isBand = true
                    bandRect = BandGeometry.rect(initial: initialFingers, current: current)
                    state = .began; bandPreview?(bandRect); return
                } else if travel > 140 { state = .failed; return }
            }
        } else { state = .changed }
        if state == .began || state == .changed {
            preview?(points)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard state == .possible || state == .began || state == .changed else { return }
        if singleFingerBand, !lifting, let start = points.first {
            bandRect = BandGeometry.pointerRect(from: start, to: center)
            bandPreview?(bandRect)
        }
        // Freeze the two-finger midpoint at the first lift. A trailing finger
        // cannot move the selection; completion waits until both are released.
        if !lifting, let last = points.last, CircleGeometry.distance(last, center) >= 2 {
            points.append(center)
            if !isBand, state == .began || state == .changed { preview?(points) }
        }
        lifting = true
        releasedFingers.formUnion(touches)
        guard fingers.allSatisfy({ releasedFingers.contains($0) }) else { return }
        if isBand {
            state = bandRect.width >= 100 && (!singleFingerBand || bandRect.height >= 24) ? .ended : .cancelled
            return
        }
        if state == .began || state == .changed {
            if let completed = CircleGeometry.completedLoop(points) {
                points = completed
                state = .ended
            } else { state = .cancelled }
        } else { state = .failed }
    }

    private func reject() { state = state == .possible ? .failed : .cancelled }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .cancelled }
    override func reset() {
        fingers = []; points = []; travel = 0; initialSeparation = 0; lifting = false; releasedFingers = []
        initialFingers = []; isBand = false; bandRect = .zero
    }
    private var center: CGPoint {
        let positions = fingers.map { $0.location(in: view) }
        return CGPoint(x: positions.map(\.x).reduce(0, +) / CGFloat(positions.count),
                       y: positions.map(\.y).reduce(0, +) / CGFloat(positions.count))
    }
    private var separation: CGFloat {
        fingers.count == 2 ? CircleGeometry.distance(fingers[0].location(in: view), fingers[1].location(in: view)) : 1
    }
}
