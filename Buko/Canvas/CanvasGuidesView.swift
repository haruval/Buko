import UIKit

final class CanvasGuidesView: UIView {
    private let sharp = CAShapeLayer()
    private let glow = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        sharp.fillColor = nil
        sharp.lineWidth = 1.8
        sharp.lineCap = .round
        sharp.lineJoin = .round
        glow.shadowOffset = .zero
        layer.addSublayer(glow)
        layer.addSublayer(sharp)
        alpha = 0
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func show() {
        layer.removeAllAnimations()
        alpha = 1
    }

    func hide(animated: Bool) {
        UIView.animate(withDuration: animated && !UIAccessibility.isReduceMotionEnabled ? 0.18 : 0,
                       delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) { self.alpha = 0 }
    }

    func update(rect: CGRect, snapProgress: CGFloat?) {
        let rect = rect.insetBy(dx: 3, dy: 3)
        let fill = min(1, (snapProgress ?? 0) / 0.45)
        let fade = max(0, ((snapProgress ?? 0) - 0.45) / 0.55)
        let horizontal = 22 + (rect.width / 2 - 22) * fill
        let vertical = 22 + (rect.height / 2 - 22) * fill
        let path = UIBezierPath()
        for (point, dx, dy) in [
            (CGPoint(x: rect.minX, y: rect.minY), CGFloat(1), CGFloat(1)),
            (CGPoint(x: rect.maxX, y: rect.minY), CGFloat(-1), CGFloat(1)),
            (CGPoint(x: rect.minX, y: rect.maxY), CGFloat(1), CGFloat(-1)),
            (CGPoint(x: rect.maxX, y: rect.maxY), CGFloat(-1), CGFloat(-1))
        ] {
            path.move(to: CGPoint(x: point.x + dx * horizontal, y: point.y))
            path.addLine(to: point)
            path.addLine(to: CGPoint(x: point.x, y: point.y + dy * vertical))
        }
        let color = (UIColor(named: "AccentColor") ?? .systemGreen).resolvedColor(with: traitCollection)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sharp.path = path.cgPath
        sharp.strokeColor = color.cgColor
        sharp.opacity = Float(1 - fade)
        // Core Animation shadows use a Gaussian falloff; the outline softens as it fades.
        glow.shadowPath = path.cgPath.copy(strokingWithWidth: 2, lineCap: .round, lineJoin: .round, miterLimit: 1)
        glow.shadowColor = color.cgColor
        glow.shadowRadius = 1 + fade * 16
        glow.shadowOpacity = snapProgress == nil ? 0 : Float((1 - fade) * 0.9)
        CATransaction.commit()
    }
}
