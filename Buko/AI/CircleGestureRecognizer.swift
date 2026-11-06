import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Two fingers translate to select; one finger scrolls. Only the initial motion
/// arbitrates with pinch. A loop is validated on release, not while starting it.
final class CircleGestureRecognizer: UIGestureRecognizer {
    var singleFinger = false
    var preview: (([CGPoint]) -> Void)?
    var cancelPreview: (() -> Void)?
    private(set) var points: [CGPoint] = []
    private var fingers: [UITouch] = []
    private var initialSeparation: CGFloat = 0
    private var initialPositions: [CGPoint] = []
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
        initialPositions = fingers.map { $0.location(in: view) }
        points = [center]
        if singleFinger { state = .began }
        // Show the tool at the midpoint as soon as the pair lands. A genuine
        // pinch can still win before translation claims this recognizer.
        preview?(points)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard state == .possible || state == .began || state == .changed else { return }
        guard !lifting else { return }
        guard fingers.count == (singleFinger ? 1 : 2) else {
            // Allow slightly staggered finger placement without delaying an
            // ordinary pan beyond its normal touch slop.
            if let start = points.first, CircleGeometry.distance(start, center) < 14 { return }
            reject(); return
        }
        let point = center
        if !singleFinger, state == .possible, let start = points.first {
            let translation = CircleGeometry.distance(start, point)
            let spread = abs(separation - initialSeparation)
            let current = fingers.map { $0.location(in: view) }
            let motion = zip(initialPositions, current).map { CGPoint(x: $1.x - $0.x, y: $1.y - $0.y) }
            if Self.movesTogether(motion[0], motion[1], separation: initialSeparation, spread: spread) {
                state = .began
            } else if Self.isPinch(translation: translation, spread: spread, separation: initialSeparation) {
                reject(); return
            }
        }
        guard let previous = points.last, CircleGeometry.distance(previous, point) >= 2 else { return }
        points.append(point)
        if points.count > 700 { state = .cancelled; return }
        if state == .began || state == .changed { state = .changed }
        preview?(points)
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
            } else { reject() }
        } else { reject() }
    }

    private func reject() {
        cancelPreview?()
        state = state == .possible ? .failed : .cancelled
    }

    static func movesTogether(_ a: CGPoint, _ b: CGPoint, separation: CGFloat, spread: CGFloat) -> Bool {
        let first = hypot(a.x, a.y), second = hypot(b.x, b.y)
        let translation = hypot((a.x + b.x) / 2, (a.y + b.y) / 2)
        // Both fingers must move in broadly the same direction. A stationary
        // finger plus a moving finger is neither co-translation nor a loop.
        guard min(first, second) >= 2, a.x * b.x + a.y * b.y >= first * second * 0.5 else { return false }
        let closePair = separation <= 120
        return translation >= (closePair ? 4 : 10)
            && spread <= max(closePair ? 12 : 6, translation * (closePair ? 1.2 : 0.65))
    }

    static func isPinch(translation: CGFloat, spread: CGFloat, separation: CGFloat) -> Bool {
        spread >= max(12, separation * 0.08) && spread > translation * 1.5
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { reject() }
    override func reset() {
        cancelPreview?()
        fingers = []; points = []; initialPositions = []; initialSeparation = 0; lifting = false; releasedFingers = []
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
