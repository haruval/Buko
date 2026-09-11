import PencilKit
import UIKit

/// One scroll camera owns writing, overview navigation, and the document backdrop.
final class CanvasHostView: UIView, UIGestureRecognizerDelegate {
    let canvas = PKCanvasView()
    private let surface = UIView()
    private let backdrop = CanvasBackdrop()
    private let guides = CanvasGuidesView()
    private let edgeMask = CanvasEdgeMask.makeLayer()
    private let camera = CanvasCameraAnimator()
    private var guideRect = CGRect.zero
    private var lastViewportSize = CGSize.zero
    private var documentHeight: CGFloat = 6_000
    private var pageFitScale: CGFloat = 1
    private var isPinching = false
    private var isSnapping = false
    private var snapProgress: CGFloat?
    private var tool: CanvasSession.Tool = .pen
    private(set) var isUpdatingInk = false

    private var documentSize: CGSize { CGSize(width: PageGeometry.workspaceWidth, height: documentHeight) }
    private var isOverview: Bool { PageGeometry.isOverview(scale: canvas.zoomScale, fitScale: pageFitScale) }
    private var inkColor: UIColor { traitCollection.userInterfaceStyle == .dark ? .white : .black }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        addSubview(surface)
        surface.addSubview(backdrop)
        surface.addSubview(canvas)
        addSubview(guides)
        // Disable PencilKit's implicit appearance conversion. We own the single ink
        // presentation explicitly, including old strokes and undo/redo snapshots.
        canvas.overrideUserInterfaceStyle = .light
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.alwaysBounceVertical = true
        canvas.bouncesZoom = true
        canvas.showsHorizontalScrollIndicator = false
        canvas.showsVerticalScrollIndicator = false
        canvas.maximumZoomScale = 4
        canvas.accessibilityLabel = "Note canvas"
        canvas.accessibilityHint = "Pinch out to look around. Tap with a finger or Pencil to return to writing at that location."
        canvas.pinchGestureRecognizer?.addTarget(self, action: #selector(pinchChanged(_:)))
        let focusTap = UITapGestureRecognizer(target: self, action: #selector(focusTapped(_:)))
        focusTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue), NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        focusTap.delegate = self
        canvas.addGestureRecognizer(focusTap)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: CanvasHostView, _: UITraitCollection) in
            view.applyAppearance()
        }
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func load(_ drawing: PKDrawing) {
        canvas.drawing = MonochromeInk.recolor(drawing, to: inkColor)
        documentHeight = max(6_000, drawing.bounds.isNull ? 0 : drawing.bounds.maxY + 2_000)
    }

    func configure(tool: CanvasSession.Tool, allowsFingerDrawing: Bool, showsGrid: Bool) {
        self.tool = tool
        canvas.drawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly
        backdrop.showsGrid = showsGrid
        applyTool()
        updateViewport()
    }

    private func applyTool() {
        canvas.tool = tool == .pen ? PKInkingTool(.pen, color: inkColor, width: 2.5) : PKEraserTool(.vector)
    }

    private func applyAppearance() {
        normalizeDisplayedInk()
        applyTool()
        updateViewport()
    }

    func normalizeDisplayedInk() {
        guard !isUpdatingInk, canvas.drawing.strokes.contains(where: { !MonochromeInk.matches($0.ink.color, inkColor) }) else { return }
        isUpdatingInk = true
        let manager = canvas.undoManager
        let wasRegistering = manager?.isUndoRegistrationEnabled == true
        if wasRegistering { manager?.disableUndoRegistration() }
        canvas.drawing = MonochromeInk.recolor(canvas.drawing, to: inkColor)
        if wasRegistering { manager?.enableUndoRegistration() }
        isUpdatingInk = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        let oldSize = lastViewportSize
        let oldScale = max(canvas.zoomScale, 0.001)
        let oldCenter = PageGeometry.documentPoint(CGPoint(x: oldSize.width / 2, y: oldSize.height / 2), scale: oldScale, offset: canvas.contentOffset)
        surface.frame = bounds
        backdrop.frame = bounds
        canvas.frame = bounds
        guides.frame = bounds
        if oldSize == .zero {
            pageFitScale = PageGeometry.fitScale(for: bounds.size)
            canvas.contentSize = documentSize
            canvas.minimumZoomScale = PageGeometry.minimumScale(viewport: bounds.size, document: documentSize)
            canvas.zoomScale = pageFitScale
            canvas.contentOffset = CGPoint(x: PageGeometry.pageOriginX * pageFitScale, y: 0)
        } else if oldSize != bounds.size {
            stopAnimations()
            let relativeScale = oldScale / pageFitScale
            pageFitScale = PageGeometry.fitScale(for: bounds.size)
            canvas.minimumZoomScale = PageGeometry.minimumScale(viewport: bounds.size, document: documentSize)
            canvas.zoomScale = min(canvas.maximumZoomScale, max(canvas.minimumZoomScale, relativeScale * pageFitScale))
            canvas.contentOffset = clampedOffset(center: oldCenter, scale: canvas.zoomScale)
            guides.hide(animated: false)
        }
        lastViewportSize = bounds.size
        applyAppearance()
    }

    func updateViewport() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let scale = canvas.zoomScale
        let offset = canvas.contentOffset
        backdrop.update(scale: scale, offset: offset, document: documentSize)
        let documentFrame = PageGeometry.screenRect(CGRect(origin: .zero, size: documentSize), scale: scale, offset: offset)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        edgeMask.frame = documentFrame.insetBy(dx: -32, dy: -32)
        surface.layer.mask = isOverview && CanvasEdgeMask.image != nil ? edgeMask : nil
        CATransaction.commit()
        if !guideRect.isEmpty {
            guides.update(rect: PageGeometry.screenRect(guideRect, scale: scale, offset: offset), snapProgress: snapProgress)
        }
        let canDraw = !isOverview && !isPinching && !isSnapping
        if canvas.drawingGestureRecognizer.isEnabled != canDraw {
            canvas.drawingGestureRecognizer.isEnabled = canDraw
        }
    }

    @objc private func pinchChanged(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            stopAnimations()
            isPinching = true
            guideRect = PageGeometry.pageRect(viewport: bounds.size, scale: canvas.zoomScale, offset: canvas.contentOffset)
            guides.show()
            updateViewport()
        case .ended:
            isPinching = false
            DispatchQueue.main.async { [weak self] in self?.finishPinch() }
        case .cancelled, .failed:
            isPinching = false
            guides.hide(animated: true)
            updateViewport()
        default:
            break
        }
    }

    private func finishPinch() {
        guard !isPinching else { return }
        if canvas.zoomScale < canvas.minimumZoomScale {
            // UIScrollView's native zoom rubber band settles back to its minimum.
            guides.hide(animated: true)
        } else if PageGeometry.shouldSnap(scale: canvas.zoomScale, fitScale: pageFitScale) {
            let center = PageGeometry.documentPoint(CGPoint(x: bounds.midX, y: bounds.midY), scale: canvas.zoomScale, offset: canvas.contentOffset)
            focus(on: center)
        } else {
            guides.hide(animated: true)
        }
        updateViewport()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        isOverview && !isPinching && !isSnapping
    }

    @objc private func focusTapped(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, isOverview else { return }
        // Coordinates in the host are viewport coordinates, unlike a scroll view's bounds.
        let point = recognizer.location(in: self)
        focus(on: PageGeometry.documentPoint(point, scale: canvas.zoomScale, offset: canvas.contentOffset))
    }

    private func focus(on center: CGPoint) {
        camera.cancel()
        guideRect = PageGeometry.focusedRect(center: center, viewport: bounds.size, document: documentSize)
        let startScale = canvas.zoomScale
        let startCenter = PageGeometry.documentPoint(CGPoint(x: bounds.midX, y: bounds.midY), scale: startScale, offset: canvas.contentOffset)
        let targetCenter = CGPoint(x: guideRect.midX, y: guideRect.midY)
        isSnapping = true
        snapProgress = 0
        guides.show()
        updateViewport()
        camera.animate { [weak self] progress in
            guard let self else { return }
            let eased: CGFloat = progress >= 1 ? 1 : 1 - exp(-8 * progress) * cos(10 * progress)
            let scale = startScale + (self.pageFitScale - startScale) * eased
            let center = CGPoint(x: startCenter.x + (targetCenter.x - startCenter.x) * eased,
                                 y: startCenter.y + (targetCenter.y - startCenter.y) * eased)
            self.snapProgress = progress
            self.canvas.zoomScale = max(self.canvas.minimumZoomScale, min(self.canvas.maximumZoomScale, scale))
            self.canvas.contentOffset = self.clampedOffset(center: center, scale: self.canvas.zoomScale)
            self.updateViewport()
        } completion: { [weak self] in
            guard let self else { return }
            self.isSnapping = false
            self.snapProgress = nil
            self.guides.hide(animated: false)
            self.updateViewport()
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private func clampedOffset(center: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(x: min(max(0, center.x * scale - bounds.width / 2), max(0, documentSize.width * scale - bounds.width)),
                y: min(max(0, center.y * scale - bounds.height / 2), max(0, documentSize.height * scale - bounds.height)))
    }

    func stopAnimations() {
        camera.cancel()
        isSnapping = false
        snapProgress = nil
    }

    func extendIfNeeded() {
        guard lastViewportSize != .zero, !isOverview, !isPinching, !isSnapping, canvas.zoomScale > 0 else { return }
        let visibleBottom = (canvas.contentOffset.y + canvas.bounds.height) / canvas.zoomScale
        let drawingBottom = canvas.drawing.bounds.isNull ? 0 : canvas.drawing.bounds.maxY
        let neededHeight = max(visibleBottom, drawingBottom) + 1_500
        guard neededHeight > documentHeight else { return }
        documentHeight = (neededHeight / 2_000).rounded(.up) * 2_000
        canvas.contentSize = CGSize(width: documentSize.width * canvas.zoomScale, height: documentHeight * canvas.zoomScale)
        canvas.minimumZoomScale = PageGeometry.minimumScale(viewport: bounds.size, document: documentSize)
        updateViewport()
    }
}
