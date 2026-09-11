import CoreImage
import UIKit

final class CanvasBackdrop: UIView {
    private let grid = CAShapeLayer()
    var showsGrid = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(named: "CanvasBackground")
        isUserInteractionEnabled = false
        grid.fillColor = nil
        grid.lineWidth = 0.65
        layer.addSublayer(grid)
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func update(scale: CGFloat, offset: CGPoint, document: CGSize) {
        grid.isHidden = !showsGrid
        guard showsGrid, scale > 0 else { return }
        let spacing: CGFloat = 32
        let left = max(0, offset.x / scale)
        let top = max(0, offset.y / scale)
        let right = min(document.width, (offset.x + bounds.width) / scale)
        let bottom = min(document.height, (offset.y + bounds.height) / scale)
        guard right >= left, bottom >= top else { grid.path = nil; return }
        let path = UIBezierPath()
        for x in stride(from: (left / spacing).rounded(.up) * spacing, through: right, by: spacing) {
            path.move(to: CGPoint(x: x * scale - offset.x, y: top * scale - offset.y))
            path.addLine(to: CGPoint(x: x * scale - offset.x, y: bottom * scale - offset.y))
        }
        for y in stride(from: (top / spacing).rounded(.up) * spacing, through: bottom, by: spacing) {
            path.move(to: CGPoint(x: left * scale - offset.x, y: y * scale - offset.y))
            path.addLine(to: CGPoint(x: right * scale - offset.x, y: y * scale - offset.y))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        grid.path = path.cgPath
        grid.strokeColor = (traitCollection.userInterfaceStyle == .dark ? UIColor.white : .black).withAlphaComponent(0.14).cgColor
        CATransaction.commit()
    }
}

/// A small cached Gaussian mask, stretched at its solid center. Core Image runs
/// once, never once per pinch frame; the native scroll view supplies rubber-banding.
enum CanvasEdgeMask {
    static let image: CGImage? = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 384, height: 384), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 96, y: 96, width: 192, height: 192))
        }
        guard let input = CIImage(image: image) else { return nil }
        let blurred = input.applyingGaussianBlur(sigma: 24).cropped(to: input.extent)
        return CIContext().createCGImage(blurred, from: input.extent)
    }()

    static func makeLayer() -> CALayer {
        let mask = CALayer()
        mask.contents = image
        mask.contentsCenter = CGRect(x: 0.5, y: 0.5, width: 1.0 / 384, height: 1.0 / 384)
        return mask
    }
}
