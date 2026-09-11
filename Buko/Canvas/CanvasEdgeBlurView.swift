import CoreImage
import PencilKit
import UIKit

/// Real progressive Gaussian blur of the page's ink and grid, not just a soft
/// alpha edge. Cache a low-resolution page snapshot and three blur levels per
/// gesture; only masks and geometry move while the user pulls.
final class CanvasEdgeBlurView: UIView {
    private let images = (0..<3).map { _ in UIImageView() }
    private var edgeMasks: [[CAGradientLayer]] = []
    private var generation = 0
    private var prepared = false
    private(set) var snapshotRect = CGRect.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        for image in images {
            image.contentMode = .scaleToFill
            let mask = CALayer()
            let edges = (0..<4).map { _ in CAGradientLayer() }
            for edge in edges { mask.addSublayer(edge) }
            image.layer.mask = mask
            addSubview(image)
            edgeMasks.append(edges)
        }
        alpha = 0
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func invalidate() {
        generation += 1
        prepared = false
        images.forEach { $0.image = nil }
    }

    func prepare(drawing: PKDrawing, rect: CGRect, showsGrid: Bool, traits: UITraitCollection) {
        guard !prepared, !rect.isEmpty else { return }
        prepared = true
        generation += 1
        let token = generation
        snapshotRect = rect
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(0.65, 900 / max(rect.width, rect.height))
        format.opaque = true
        let background = (UIColor(named: "CanvasBackground") ?? .systemBackground).resolvedColor(with: traits)
        let gridColor = (traits.userInterfaceStyle == .dark ? UIColor.white : .black).withAlphaComponent(0.14)
        var inkImage = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            inkImage = drawing.image(from: rect, scale: format.scale)
        }
        let snapshot = UIGraphicsImageRenderer(size: rect.size, format: format).image { renderer in
            background.setFill()
            renderer.fill(CGRect(origin: .zero, size: rect.size))
            if showsGrid {
                let context = renderer.cgContext
                context.setStrokeColor(gridColor.cgColor)
                context.setLineWidth(0.65)
                for x in stride(from: ceil(rect.minX / 32) * 32, through: rect.maxX, by: 32) {
                    context.move(to: CGPoint(x: x - rect.minX, y: 0))
                    context.addLine(to: CGPoint(x: x - rect.minX, y: rect.height))
                }
                for y in stride(from: ceil(rect.minY / 32) * 32, through: rect.maxY, by: 32) {
                    context.move(to: CGPoint(x: 0, y: y - rect.minY))
                    context.addLine(to: CGPoint(x: rect.width, y: y - rect.minY))
                }
                context.strokePath()
            }
            inkImage.draw(in: CGRect(origin: .zero, size: rect.size))
        }
        guard let source = snapshot.cgImage else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let pyramid = Self.blurPyramid(source)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                for (view, image) in zip(self.images, pyramid) { view.image = UIImage(cgImage: image) }
            }
        }
    }

    nonisolated private static func blurPyramid(_ source: CGImage) -> [CGImage] {
        let context = CIContext(options: [.cacheIntermediates: false])
        let input = CIImage(cgImage: source)
        return [8.0, 22.0, 48.0].compactMap { radius in
            let output = input.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: input.extent)
            return context.createCGImage(output, from: input.extent)
        }
    }

    func update(scale: CGFloat, offset: CGPoint, boundary: CGRect, strength: CGFloat) {
        alpha = min(1, strength)
        guard strength > 0, !snapshotRect.isEmpty else { return }
        let imageFrame = PageGeometry.screenRect(snapshotRect, scale: scale, offset: offset)
        let edgeFrame = PageGeometry.screenRect(boundary, scale: scale, offset: offset)
            .offsetBy(dx: -imageFrame.minX, dy: -imageFrame.minY)
        let band = 72 + min(1.5, strength) * 150
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, image) in images.enumerated() {
            image.frame = imageFrame
            image.layer.mask?.frame = image.bounds
            let width = band * [1.0, 0.70, 0.40][index]
            let masks = edgeMasks[index]
            masks[0].frame = CGRect(x: edgeFrame.minX, y: edgeFrame.minY, width: edgeFrame.width, height: width)
            masks[1].frame = CGRect(x: edgeFrame.minX, y: edgeFrame.maxY - width, width: edgeFrame.width, height: width)
            masks[2].frame = CGRect(x: edgeFrame.minX, y: edgeFrame.minY, width: width, height: edgeFrame.height)
            masks[3].frame = CGRect(x: edgeFrame.maxX - width, y: edgeFrame.minY, width: width, height: edgeFrame.height)
            for (edgeIndex, mask) in masks.enumerated() {
                let reversed = edgeIndex == 1 || edgeIndex == 3
                mask.colors = reversed ? [UIColor.clear.cgColor, UIColor.black.cgColor] : [UIColor.black.cgColor, UIColor.clear.cgColor]
                mask.locations = [0, 1]
                mask.startPoint = .zero
                mask.endPoint = edgeIndex < 2 ? CGPoint(x: 0, y: 1) : CGPoint(x: 1, y: 0)
            }
        }
        CATransaction.commit()
    }
}
