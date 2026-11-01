import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Two fingers translate to select; one finger scrolls. Only the initial motion
/// arbitrates with pinch. A loop is validated on release, not while starting it.
final class CircleGestureRecognizer: UIGestureRecognizer {
    var singleFinger = false
    var preview: (([CGPoint]) -> Void)?
    private(set) var points: [CGPoint] = []
    private var fingers: [UITouch] = []
    private var initialSeparation: CGFloat = 0
    private var lifting = false
    private var releasedFingers: Set<UITouch> = []

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touches.allSatisfy({ $0.type == .direct }) else { reject(); return }
        guard !lifting else { state = .cancelled; return }
        fingers.append(contentsOf: touches)
        let required = singleFinger ? 1 : 2
        guard fingers.count <= required else { reject(); return }
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
        let point = center
        if !singleFinger, state == .possible, let start = points.first {
            let translation = CircleGeometry.distance(start, point)
            let spread = abs(separation - initialSeparation)
            if Self.isPinch(translation: translation, spread: spread, separation: initialSeparation) {
                state = .failed; return
            }
            if translation >= 12 && translation > spread * 1.25 { state = .began }
        }
        guard let previous = points.last, CircleGeometry.distance(previous, point) >= 2 else { return }
        points.append(point)
        if points.count > 700 { state = .cancelled; return }
        if state == .began || state == .changed { state = .changed }
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

    private func reject() { state = state == .possible ? .failed : .cancelled }

    static func isPinch(translation: CGFloat, spread: CGFloat, separation: CGFloat) -> Bool {
        spread >= max(8, separation * 0.06) && spread > translation * 0.8
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .cancelled }
    override func reset() {
        fingers = []; points = []; initialSeparation = 0; lifting = false; releasedFingers = []
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
