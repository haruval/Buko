import PencilKit
import SwiftUI

struct NoteCanvas: UIViewRepresentable {
    let note: Note
    let session: CanvasSession
    let onDrawingChange: (Data) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, onDrawingChange: onDrawingChange)
    }

    func makeUIView(context: Context) -> CanvasHostView {
        let host = CanvasHostView()
        let canvas = host.canvas
        do {
            canvas.drawing = note.drawingData.isEmpty ? PKDrawing() : try PKDrawing(data: note.drawingData)
        } catch {
            canvas.isUserInteractionEnabled = false
            Task { @MainActor in
                session.loadError = "This drawing couldn’t be opened. Its saved data has been preserved."
            }
        }
        host.documentHeight = max(6_000, canvas.drawing.bounds.isNull ? 0 : canvas.drawing.bounds.maxY + 2_000)
        canvas.delegate = context.coordinator
        context.coordinator.host = host
        session.canvas = canvas
        configure(canvas)
        return host
    }

    func updateUIView(_ host: CanvasHostView, context: Context) {
        context.coordinator.onDrawingChange = onDrawingChange
        configure(host.canvas)
    }

    private func configure(_ canvas: PKCanvasView) {
        canvas.drawingPolicy = session.allowsFingerDrawing ? .anyInput : .pencilOnly
        switch session.tool {
        case .pen:
            // PencilKit adapts its canonical ink colors to the canvas appearance.
            canvas.tool = PKInkingTool(.pen, color: .black, width: 2.5)
        case .eraser:
            canvas.tool = PKEraserTool(.vector)
        }
    }

    static func dismantleUIView(_ host: CanvasHostView, coordinator: Coordinator) {
        host.canvas.delegate = nil
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let session: CanvasSession
        var onDrawingChange: (Data) -> Void
        weak var host: CanvasHostView?

        init(session: CanvasSession, onDrawingChange: @escaping (Data) -> Void) {
            self.session = session
            self.onDrawingChange = onDrawingChange
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onDrawingChange(canvasView.drawing.dataRepresentation())
            session.refreshUndoState()
            host?.extendIfNeeded()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            host?.updateGuideFrame()
            host?.extendIfNeeded()
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            host?.updateGuideFrame()
        }
    }
}

/// PencilKit remains the only scroll/zoom owner. Corner guides are a noninteractive
/// overlay in viewport coordinates; the writing surface has no permanent page edges.
final class CanvasHostView: UIView {
    let canvas = PKCanvasView()
    private let guides = UIView()
    private let cornerLayer = CAShapeLayer()
    private var guideRect = CGRect.zero
    private var lastViewportSize = CGSize.zero
    var documentHeight: CGFloat = 6_000
    private var hasPositionedPage = false
    private var pageFitScale: CGFloat = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(named: "CanvasBackground")
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.alwaysBounceVertical = true
        canvas.showsHorizontalScrollIndicator = false
        canvas.showsVerticalScrollIndicator = false
        canvas.maximumZoomScale = 4
        canvas.accessibilityLabel = "Note canvas"
        canvas.accessibilityHint = "Write with Apple Pencil. Drag to move. Pinch to zoom; release near page size to snap to fit."
        addSubview(canvas)

        guides.isUserInteractionEnabled = false
        guides.isAccessibilityElement = false
        guides.alpha = 0
        cornerLayer.fillColor = UIColor.clear.cgColor
        cornerLayer.lineWidth = 1.8
        cornerLayer.lineCap = .round
        cornerLayer.lineJoin = .round
        guides.layer.addSublayer(cornerLayer)
        addSubview(guides)
        canvas.pinchGestureRecognizer?.addTarget(self, action: #selector(pinchChanged(_:)))
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: CanvasHostView, _: UITraitCollection) in
            view.updateGuideFrame()
        }
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        let oldSize = lastViewportSize
        let oldScale = canvas.zoomScale
        let oldCenter = CGPoint(x: (canvas.contentOffset.x + oldSize.width / 2) / oldScale,
                                y: (canvas.contentOffset.y + oldSize.height / 2) / oldScale)
        canvas.frame = bounds
        guides.frame = bounds
        if !hasPositionedPage {
            hasPositionedPage = true
            pageFitScale = PageGeometry.fitScale(for: bounds.size)
            canvas.minimumZoomScale = pageFitScale * 0.3
            canvas.contentSize = CGSize(width: PageGeometry.workspaceWidth, height: documentHeight)
            canvas.zoomScale = pageFitScale
            canvas.contentOffset = CGPoint(x: PageGeometry.pageOriginX * pageFitScale, y: 0)
        } else if oldSize != bounds.size {
            // Preserve relative magnification and reading position through rotation/resizing.
            let relativeScale = oldScale / pageFitScale
            pageFitScale = PageGeometry.fitScale(for: bounds.size)
            canvas.minimumZoomScale = pageFitScale * 0.3
            canvas.zoomScale = min(canvas.maximumZoomScale, max(canvas.minimumZoomScale, relativeScale * pageFitScale))
            canvas.contentOffset = CGPoint(
                x: max(0, oldCenter.x * canvas.zoomScale - bounds.width / 2),
                y: max(0, oldCenter.y * canvas.zoomScale - bounds.height / 2)
            )
            guides.alpha = 0
        }
        lastViewportSize = bounds.size
        updateGuideFrame()
    }

    @objc private func pinchChanged(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            guideRect = PageGeometry.pageRect(viewport: bounds.size, scale: canvas.zoomScale, offset: canvas.contentOffset)
            updateGuideFrame()
            setGuidesVisible(true)
        case .ended:
            setGuidesVisible(false)
            // Let PencilKit finish consuming the pinch before applying the fit detent.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.canvas.pinchGestureRecognizer?.state != .began,
                      self.canvas.pinchGestureRecognizer?.state != .changed,
                      PageGeometry.shouldSnap(scale: self.canvas.zoomScale, fitScale: self.pageFitScale) else { return }
                self.canvas.zoom(to: self.guideRect, animated: !UIAccessibility.isReduceMotionEnabled)
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
        case .cancelled, .failed:
            setGuidesVisible(false)
        default:
            break
        }
    }

    private func setGuidesVisible(_ visible: Bool) {
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.18,
                       delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.guides.alpha = visible ? 1 : 0
        }
    }

    func updateGuideFrame() {
        guard !guideRect.isEmpty else { return }
        let rect = PageGeometry.screenRect(guideRect, scale: canvas.zoomScale, offset: canvas.contentOffset).insetBy(dx: 3, dy: 3)
        let length: CGFloat = min(22, min(rect.width, rect.height) / 4)
        let path = UIBezierPath()
        for (point, dx, dy) in [
            (CGPoint(x: rect.minX, y: rect.minY), CGFloat(1), CGFloat(1)),
            (CGPoint(x: rect.maxX, y: rect.minY), CGFloat(-1), CGFloat(1)),
            (CGPoint(x: rect.minX, y: rect.maxY), CGFloat(1), CGFloat(-1)),
            (CGPoint(x: rect.maxX, y: rect.maxY), CGFloat(-1), CGFloat(-1))
        ] {
            path.move(to: CGPoint(x: point.x + dx * length, y: point.y))
            path.addLine(to: point)
            path.addLine(to: CGPoint(x: point.x, y: point.y + dy * length))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cornerLayer.path = path.cgPath
        cornerLayer.strokeColor = UIColor(named: "AccentColor")?.resolvedColor(with: traitCollection).withAlphaComponent(0.8).cgColor
        CATransaction.commit()
    }

    func extendIfNeeded() {
        guard hasPositionedPage, !canvas.isZooming, canvas.zoomScale > 0 else { return }
        let visibleBottom = (canvas.contentOffset.y + canvas.bounds.height) / canvas.zoomScale
        let drawingBottom = canvas.drawing.bounds.isNull ? 0 : canvas.drawing.bounds.maxY
        let neededHeight = max(visibleBottom, drawingBottom) + 1_500
        guard neededHeight > documentHeight else { return }
        documentHeight = (neededHeight / 2_000).rounded(.up) * 2_000
        canvas.contentSize = CGSize(width: PageGeometry.workspaceWidth * canvas.zoomScale, height: documentHeight * canvas.zoomScale)
        updateGuideFrame()
    }
}
