import UIKit

/// Synthetic touch objects exercise the production recognizer state machine.
/// They do not claim physical UIKit/Pencil delivery or human gesture reliability.
@MainActor enum RoundTwoGestureChecks {
    private final class Finger: UITouch {
        var point: CGPoint
        init(_ point: CGPoint) { self.point = point; super.init() }
        override var type: UITouch.TouchType { .direct }
        override func location(in view: UIView?) -> CGPoint { point }
    }
    static func run() -> String {
        for index in 0..<24 {
            let angle = Double(index) * .pi / 12
            let a = CGPoint(x: cos(angle) * 6, y: sin(angle) * 6)
            let b = CGPoint(x: cos(angle) * 5, y: sin(angle) * 5)
            precondition(CircleGestureRecognizer.movesTogether(a, b, separation: 30, spread: 4))
            precondition(!CircleGestureRecognizer.movesTogether(a, CGPoint(x: -b.x, y: -b.y), separation: 30, spread: 11))
        }
        precondition(CircleGestureRecognizer.isPinch(translation: 1, spread: 18, separation: 32))
        precondition(!CircleGestureRecognizer.isPinch(translation: 14, spread: 10, separation: 32))
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 600, height: 800))
        let gesture = CircleGestureRecognizer(); view.addGestureRecognizer(gesture)
        var displayed = CGPoint.zero, cancelled = false
        gesture.preview = { displayed = $0.last ?? .zero }
        gesture.cancelPreview = { cancelled = true }
        let a = Finger(CGPoint(x: 402, y: 300)), b = Finger(CGPoint(x: 438, y: 300))
        let event = UIEvent()
        gesture.touchesBegan([a], with: event)
        gesture.touchesBegan([b], with: event)
        precondition(displayed == CGPoint(x: 420, y: 300), "Initial indicator must be the midpoint")
        for index in 1...120 {
            let angle = Double(index) * 2 * .pi / 120
            let center = CGPoint(x: 300 + cos(angle) * 120, y: 300 + sin(angle) * 120)
            a.point = CGPoint(x: center.x - 18, y: center.y)
            b.point = CGPoint(x: center.x + 18, y: center.y)
            gesture.touchesMoved([a, b], with: event)
            precondition(hypot(displayed.x - center.x, displayed.y - center.y) < 0.01, "Indicator follows both fingers' midpoint")
        }
        precondition(gesture.state == .changed, "Co-translation must claim the circle")
        gesture.touchesEnded([a], with: event)
        let frozen = gesture.points
        b.point.y += 40; gesture.touchesMoved([b], with: event)
        precondition(gesture.points == frozen, "Trailing finger must not change the selection")
        gesture.touchesEnded([b], with: event)
        precondition(gesture.state == .ended && !cancelled)
        let pinchView = UIView(frame: view.bounds)
        let pinch = CircleGestureRecognizer(); pinchView.addGestureRecognizer(pinch)
        let c = Finger(CGPoint(x: 200, y: 200)), d = Finger(CGPoint(x: 230, y: 200))
        pinch.cancelPreview = { cancelled = true }
        pinch.touchesBegan([c, d], with: event)
        c.point.x -= 10; d.point.x += 10
        pinch.touchesMoved([c, d], with: event)
        // UIKit may reset .failed immediately outside a real event dispatch.
        precondition(pinch.state != .began && pinch.state != .changed && cancelled,
                     "Spread must yield and remove provisional indicator")
        return "Gesture checks passed: midpoint, 24 directions, closed loop, staggered lift, pinch handoff"
    }
}
