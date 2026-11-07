import PencilKit
import UIKit

/// Read-only ink layers. Only their cameras move during reflow; the editor's
/// drawing, undo stack and save callbacks never participate in the animation.
final class AutofillCanvasPreview: UIView, PKCanvasViewDelegate {
    private final class Band {
        var spring: AutofillReflowSpring
        let indices: [Int]
        var drawing: PKDrawing
        let bounds: CGRect
        var canvas: PKCanvasView?

        init(strokes: [(index: Int, stroke: PKStroke)], spring: AutofillReflowSpring, color: UIColor) {
            self.spring = spring; indices = strokes.map(\.index)
            var presentation = InkPresentation()
            drawing = presentation.refresh(PKDrawing(strokes: strokes.map(\.stroke)), to: color)
            bounds = drawing.bounds
        }
    }

    private let backdrop = CanvasBackdrop()
    private let proposedInk = UIView()
    private let insertedCanvas = makeCanvas()
    private var waitingForInk = false
    private var acceptedFade: UIViewPropertyAnimator?
    private let animator = CanvasCameraAnimator()
    private var bands: [Band] = []
    private var labels: [UILabel] = []
    private var result: AutofillLayout.Result?
    private var style = UIUserInterfaceStyle.light
    private weak var editor: PKCanvasView?
    private var returning = false
    var didSettle: ((Int?) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        addSubview(backdrop)
        addSubview(proposedInk)
        proposedInk.addSubview(insertedCanvas)
        insertedCanvas.delegate = self
        isHidden = true; accessibilityElementsHidden = true
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    private static func makeCanvas() -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.isUserInteractionEnabled = false; canvas.backgroundColor = .clear; canvas.isOpaque = false
        canvas.accessibilityElementsHidden = true
        canvas.overrideUserInterfaceStyle = .light
        canvas.minimumZoomScale = 0.01; canvas.maximumZoomScale = 8
        canvas.contentInsetAdjustmentBehavior = .never
        return canvas
    }

    func show(_ result: AutofillLayout.Result, style: UIUserInterfaceStyle, from editor: PKCanvasView) {
        finishAcceptedFade()
        animator.cancel()
        let now = CACurrentMediaTime(), wasHidden = isHidden
        self.editor = editor
        let oldMotions = Dictionary(uniqueKeysWithValues: bands.flatMap { band in band.indices.map { ($0, band.spring) } })
        self.result = result; self.style = style; returning = false
        backdrop.overrideUserInterfaceStyle = style
        // Layout keeps original stroke order/identities. Equal displacements share
        // one native, tiled PencilKit layer, even when they span many pages.
        var groups: [AutofillReflowSpring: [(index: Int, stroke: PKStroke)]] = [:]
        for (index, pair) in zip(result.original.strokes, result.existing.strokes).enumerated() {
            let (before, after) = pair
            var spring = oldMotions[index] ?? AutofillReflowSpring()
            // Subpixel rounding prevents floating-point noise in concatenated
            // transforms from allocating one renderer per individual stroke.
            let displacement = ((after.transform.ty - before.transform.ty) * 1024).rounded() / 1024
            spring.retarget(displacement, at: now,
                            reduceMotion: UIAccessibility.isReduceMotionEnabled)
            groups[spring, default: []].append((index, before))
        }
        bands.forEach { $0.canvas?.removeFromSuperview() }
        bands = groups.map { Band(strokes: $0.value, spring: $0.key, color: inkColor) }
        if wasHidden {
            proposedInk.alpha = 0
            waitingForInk = true
        }
        isHidden = false
        updateInsertedInk()
        if !waitingForInk || result.inserted.strokes.isEmpty || UIAccessibility.isReduceMotionEnabled {
            revealInk()
        }
        // Prepare native tiles before starting the clock, so first-use renderer
        // setup cannot consume the opening frames or jump past the original ink.
        render(at: now)
        let preparation = CACurrentMediaTime() - now
        bands.forEach { $0.spring.delay(by: preparation) }
        animate()
    }

    func dismiss(animated: Bool) {
        // Closing the popup after a save leaves the color transition running.
        guard acceptedFade == nil else { return }
        guard result != nil, animated, !UIAccessibility.isReduceMotionEnabled else {
            clear(); didSettle?(nil); return
        }
        let now = CACurrentMediaTime()
        returning = true
        for band in bands { band.spring.retarget(0, at: now) }
        waitingForInk = false
        setInkOpacity(0, duration: 0.18)
        animate()
    }

    /// Crossfade the green ink on its original paper into the same ink on the
    /// saved page. Keeping the tiles in place preserves the first frame's color.
    func fadeAcceptedInk() {
        finishAcceptedFade()
        guard result != nil, !isHidden, window != nil, !UIAccessibility.isReduceMotionEnabled else { return }
        waitingForInk = false
        let fade = UIViewPropertyAnimator(duration: 0.66, curve: .easeInOut) { [weak self] in self?.alpha = 0 }
        acceptedFade = fade
        fade.addCompletion { [weak self] _ in self?.finishAcceptedFade() }
        fade.startAnimation()
        didSettle?(nil)
    }

    func finishAcceptedFade() {
        guard let fade = acceptedFade else { return }
        acceptedFade = nil
        if fade.state == .active { fade.stopAnimation(true) }
        clear()
        alpha = 1
    }

    /// Rotation, teardown and Reduce Motion finish at the exact destination.
    func settle() {
        animator.cancel()
        guard result != nil else { return }
        if returning { clear(); didSettle?(nil) }
        else {
            bands.forEach { $0.spring.settle() }
            // An offscreen drawing may have no visible tiles to report.
            if waitingForInk { revealInk() }
            render(at: CACurrentMediaTime())
            if acceptedFade == nil { didSettle?(result?.pageCount) }
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { finishAcceptedFade(); settle() }
    }

    private func animate() {
        render(at: CACurrentMediaTime())
        animator.animate(duration: AutofillReflowSpring.duration, step: { [weak self] _ in
            guard let self else { return }
            if UIAccessibility.isReduceMotionEnabled { self.settle() }
            else { self.render(at: CACurrentMediaTime()) }
        }, completion: { [weak self] in self?.settle() })
    }

    private func clear() {
        animator.cancel()
        waitingForInk = false
        proposedInk.layer.removeAllAnimations()
        bands.forEach { $0.canvas?.removeFromSuperview() }; bands = []
        labels.forEach { $0.removeFromSuperview() }; labels = []
        insertedCanvas.drawing = PKDrawing()
        result = nil; returning = false; isHidden = true
    }

    private var inkColor: UIColor { style == .dark ? .white : .black }

    private func updateInsertedInk() {
        guard let result else { return }
        var presentation = InkPresentation()
        insertedCanvas.drawing = presentation.refresh(result.inserted, to: Self.green(style))
        labels.forEach { $0.removeFromSuperview() }; labels = []
        if !result.missing.isEmpty {
            for line in result.lines {
                let label = UILabel()
                label.text = line.text; label.textColor = Self.green(style)
                label.numberOfLines = 1; label.adjustsFontSizeToFitWidth = true; label.minimumScaleFactor = 0.5
                proposedInk.addSubview(label); labels.append(label)
            }
        }
    }

    static func green(_ style: UIUserInterfaceStyle) -> UIColor {
        style == .dark ? UIColor(red: 0.49, green: 0.85, blue: 0.59, alpha: 0.85)
            : UIColor(red: 0.12, green: 0.42, blue: 0.23, alpha: 0.80)
    }

    func project(from editor: PKCanvasView, style: UIUserInterfaceStyle, showsGrid: Bool, document: CGSize) {
        if self.style != style || UIAccessibility.isReduceMotionEnabled { finishAcceptedFade() }
        guard result != nil else { return }
        self.editor = editor
        if self.style != style {
            self.style = style; backdrop.overrideUserInterfaceStyle = style
            for band in bands {
                var presentation = InkPresentation()
                band.drawing = presentation.refresh(band.drawing, to: inkColor)
                band.canvas?.drawing = band.drawing
            }
            updateInsertedInk()
        }
        backdrop.frame = bounds; backdrop.showsGrid = showsGrid
        backdrop.update(scale: editor.zoomScale, offset: editor.contentOffset, document: document)
        render(at: CACurrentMediaTime())
    }

    private func render(at time: TimeInterval) {
        guard let editor, let result else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let scale = editor.zoomScale, offset = editor.contentOffset
        for band in bands {
            let displacement = band.spring.sample(at: time).position
            let projected = PageGeometry.screenRect(band.bounds.offsetBy(dx: 0, dy: displacement), scale: scale, offset: offset)
            // Keep off-screen groups as ink data; allocate native renderers only
            // near the viewport. No full-note bitmap or per-frame stroke rebuild.
            guard projected.intersects(bounds.insetBy(dx: -64, dy: -64)) else {
                band.canvas?.removeFromSuperview(); band.canvas = nil; continue
            }
            if band.canvas == nil {
                let canvas = Self.makeCanvas(); canvas.drawing = band.drawing
                insertSubview(canvas, belowSubview: proposedInk); band.canvas = canvas
            }
            project(band.canvas!, editor: editor, displacement: displacement)
        }
        if proposedInk.frame != bounds { proposedInk.frame = bounds }
        project(insertedCanvas, editor: editor, displacement: 0)
        for (line, label) in zip(result.lines, labels) {
            label.frame = PageGeometry.screenRect(line.frame, scale: scale, offset: offset)
            label.font = .systemFont(ofSize: result.letterHeight * scale)
        }
    }

    private func project(_ canvas: PKCanvasView, editor: PKCanvasView, displacement: CGFloat) {
        if canvas.frame != bounds { canvas.frame = bounds }
        if canvas.zoomScale != editor.zoomScale { canvas.zoomScale = editor.zoomScale }
        if canvas.contentSize != editor.contentSize { canvas.contentSize = editor.contentSize }
        if canvas.contentInset != editor.contentInset { canvas.contentInset = editor.contentInset }
        let offset = CGPoint(x: editor.contentOffset.x, y: editor.contentOffset.y - displacement * editor.zoomScale)
        if canvas.contentOffset != offset { canvas.contentOffset = offset }
    }

    func canvasViewDidFinishRendering(_ canvasView: PKCanvasView) {
        if waitingForInk && canvasView === insertedCanvas { revealInk() }
    }

    private func revealInk() {
        waitingForInk = false
        setInkOpacity(1, duration: 0.48)
    }

    private func setInkOpacity(_ value: CGFloat, duration: TimeInterval) {
        if UIAccessibility.isReduceMotionEnabled {
            proposedInk.layer.removeAllAnimations()
            proposedInk.alpha = value
        } else if proposedInk.alpha != value {
            UIView.animate(withDuration: duration, delay: 0,
                           options: [.beginFromCurrentState, .curveEaseInOut, .allowUserInteraction]) {
                self.proposedInk.alpha = value
            }
        }
    }
}
