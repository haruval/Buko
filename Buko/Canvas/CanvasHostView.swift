import PencilKit
import UIKit
import SwiftUI

/// Stable ink coordinates and camera for a vertically stacked page notebook.
final class CanvasHostView: UIView, UIGestureRecognizerDelegate {
    let canvas = PKCanvasView()
    let circleIntent = CircleIntentState()
    let cube = CubeState()
    private let cubeContainer = CubeOverlayContainer()
    private var cubeHosting: UIHostingController<CubeOverlay>?
    private let circleGesture = CircleGestureRecognizer()
    private let circleContainer = CircleOverlayContainer()
    private var circleHosting: UIHostingController<CircleIntentOverlay>?
    private let bandHighlight = BandHighlightState()
    private var bandHosting: UIHostingController<BandHighlight>?
    private var capturedBand: CGRect?
    var onBandSelection: ((PKDrawing, CGRect) -> Void)?

    var onPageChange: ((Int, Int) -> Void)?
    var preparedHandwriting: ((AutofillProposal) -> HandwritingSampler.Result)?
    var captureAutofillDocument: (() -> AutofillDocument?)?
    var persistAutofill: ((AutofillDocument, AutofillDocument) throws -> Void)?
    var onUndoStateChange: (() -> Void)?
    private let autofillPreview = AutofillCanvasPreview(frame: .zero)
    private var previewPageCount: Int?
    private var displayedPageCount: Int { previewPageCount ?? pageCount }
    #if DEBUG
    private var zoomTestArea: UIAccessibilityElement?
    #endif
    private let pagePull: PagePullState
    private let surface = UIView()
    private let backdrop = CanvasBackdrop()
    private let edgeBlur = CanvasEdgeBlurView()
    private let guides = CanvasGuidesView()
    private let edgeMask = CanvasEdgeMask.makeLayer()
    private let bezelMask = CanvasEdgeMask.makeLayer()
    private let pageMask = CAShapeLayer()
    private let transitionShade = CALayer()
    private var transitionGradients: [CAGradientLayer] = []
    private let camera = CanvasCameraAnimator()
    private var guideRect = CGRect.zero
    private var lastViewportSize = CGSize.zero
    private var pageCount = 1
    private var pageIndex = 0
    private var pageFitScale: CGFloat = 1
    private var isPinching = false
    private var isSnapping = false
    private var isTurningPage = false
    private var creationOrigin = CGPoint.zero
    private var zoomDetentLatched = false
    private var isEnteringOverview = false
    private var bezelProgress: CGFloat = 0
    private var pinchStartScale: CGFloat = 1
    private var snapProgress: CGFloat?
    private var tool: CanvasSession.Tool = .pen
    private var isUpdatingViewport = false
    private var isLayingOut = false
    private var lastPull: CGFloat = 0
    private var wasArmed = false
    private var isPullActive = false
    private var dragStartOffset: CGFloat = 0
    private var canCreateFromPull = false
    private var previousScrollOffset: CGFloat = 0
    private var lastWheelInput: CFTimeInterval = 0
    private var wheelCanCreate = false
    private var pageTurnPending = false
    private var wheelEnd: DispatchWorkItem?
    private(set) var isUpdatingInk = false

    private var documentSize: CGSize {
        CGSize(width: PageGeometry.workspaceWidth,
               height: NotebookPaging.documentHeight(count: displayedPageCount))
    }
    private var currentPageRect: CGRect { NotebookPaging.rect(for: pageIndex) }
    private var boundaryRect: CGRect {
        return CGRect(x: PageGeometry.pageOriginX, y: 0, width: PageGeometry.pageWidth,
                      height: documentSize.height)
    }
    private var isOverview: Bool { PageGeometry.isOverview(scale: canvas.zoomScale, fitScale: pageFitScale) }
    private var inkPresentation = InkPresentation()
    var canonicalDrawing: PKDrawing { inkPresentation.canonical(canvas.drawing) }

    private var presentationStyle: UIUserInterfaceStyle = .unspecified
    private var inkColor: UIColor { presentationStyle == .dark ? .white : .black }

    init(pagePull: PagePullState) {
        self.pagePull = pagePull
        super.init(frame: .zero)
        backgroundColor = .black
        clipsToBounds = true
        addSubview(surface)
        surface.addSubview(backdrop)
        surface.addSubview(canvas)
        surface.addSubview(autofillPreview)
        surface.addSubview(edgeBlur)
        circleIntent.insertion.currentDocument = { [weak self] in self?.captureAutofillDocument?() }
        circleIntent.insertion.preparedHandwriting = { [weak self] proposal in self?.preparedHandwriting?(proposal) ?? HandwritingSampler.Result() }
        circleIntent.insertion.previewChanged = { [weak self] in self?.showAutofillPreview($0, animatedReturn: $1) }
        autofillPreview.didSettle = { [weak self] count in self?.finishAutofillReflow(pageCount: count) }
        circleIntent.insertion.commit = { [weak self] before, after in
            guard let self else { throw AutofillEditError.unavailable }
            try self.applyAutofill(from: before, to: after)
        }
        circleIntent.insertion.accepted = { [weak self] in self?.circleIntent.cancel() }
        layer.addSublayer(transitionShade)
        for _ in 0..<4 {
            let gradient = CAGradientLayer()
            gradient.colors = [UIColor.black.cgColor, UIColor.black.cgColor,
                               UIColor.black.withAlphaComponent(0.4).cgColor, UIColor.clear.cgColor]
            gradient.locations = [0, 0.16, 0.52, 1]
            transitionShade.addSublayer(gradient)
            transitionGradients.append(gradient)
        }
        addSubview(guides)
        let bandHosting = UIHostingController(rootView: BandHighlight(state: bandHighlight))
        bandHosting.view.backgroundColor = .clear
        bandHosting.view.isUserInteractionEnabled = false
        self.bandHosting = bandHosting
        addSubview(bandHosting.view)
        let hosting = UIHostingController(rootView: CircleIntentOverlay(state: circleIntent))
        hosting.view.backgroundColor = .clear
        circleHosting = hosting
        circleContainer.state = circleIntent
        addSubview(circleContainer)
        circleContainer.addSubview(hosting.view)
        let cubeHosting = UIHostingController(rootView: CubeOverlay(state: cube))
        cubeHosting.view.backgroundColor = .clear
        self.cubeHosting = cubeHosting
        cubeContainer.state = cube
        addSubview(cubeContainer)
        cubeContainer.addSubview(cubeHosting.view)
        circleGesture.addTarget(self, action: #selector(circleChanged(_:)))
        circleGesture.delegate = self
        circleGesture.cancelsTouchesInView = true
        circleGesture.preview = { [weak self] in self?.circleIntent.trace($0) }
        circleGesture.bandPreview = { [weak self] rect in
            self?.circleIntent.cancelTracing()
            self?.bandHighlight.rect = rect
        }
        addGestureRecognizer(circleGesture)
        canvas.panGestureRecognizer.require(toFail: circleGesture)
        canvas.pinchGestureRecognizer?.require(toFail: circleGesture)
        canvas.drawingGestureRecognizer.require(toFail: circleGesture)
        canvas.overrideUserInterfaceStyle = .light
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.alwaysBounceVertical = true
        canvas.bouncesZoom = true
        canvas.panGestureRecognizer.allowedScrollTypesMask = .all
        canvas.panGestureRecognizer.addTarget(self, action: #selector(panChanged(_:)))
        canvas.showsHorizontalScrollIndicator = false
        canvas.showsVerticalScrollIndicator = false
        canvas.maximumZoomScale = 4
        canvas.accessibilityLabel = "Note canvas"
        canvas.accessibilityHint = "Scroll freely through pages. At the bottom, lift and pull again to add a page. Pinch out to look around, then tap to return to writing."
        canvas.pinchGestureRecognizer?.addTarget(self, action: #selector(pinchChanged(_:)))
        let focusTap = UITapGestureRecognizer(target: self, action: #selector(focusTapped(_:)))
        focusTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue), NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        focusTap.delegate = self
        canvas.addGestureRecognizer(focusTap)
        canvas.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Next page or add page", target: self, selector: #selector(accessibleNextPage)),
            UIAccessibilityCustomAction(name: "Previous page", target: self, selector: #selector(accessiblePreviousPage))
        ]
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: CanvasHostView, _: UITraitCollection) in
            view.setAppearance(view.traitCollection.userInterfaceStyle)
        }
    }

    required init?(coder: NSCoder) { fatalError("Use init(pagePull:)") }

    func load(_ drawing: PKDrawing, savedPageCount: Int, pageIndex: Int) {
        canvas.drawing = MonochromeInk.recolor(drawing, to: inkColor)
        pageCount = max(1, savedPageCount)
        self.pageIndex = min(max(0, pageIndex), pageCount - 1)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.syncPageState()
            if self.pageCount != savedPageCount { self.onPageChange?(self.pageCount, self.pageIndex) }
        }
    }

    func configure(tool: CanvasSession.Tool, allowsFingerDrawing: Bool, showsGrid: Bool, colorScheme: ColorScheme) {
        setAppearance(colorScheme == .dark ? .dark : .light)
        if self.tool != tool { cancelCircleInteraction(); circleIntent.cancelPending() }
        self.tool = tool
        if tool != .cube { cube.despawn() }
        circleGesture.singleFinger = tool == .circle
        circleGesture.singleFingerBand = tool == .band
        circleGesture.bandEnabled = tool == .pen || tool == .eraser
        let policy: PKCanvasViewDrawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly
        if canvas.drawingPolicy != policy { canvas.drawingPolicy = policy }
        if backdrop.showsGrid != showsGrid { invalidateEdgeSnapshot() }
        backdrop.showsGrid = showsGrid
        applyTool()
        updateViewport()
        syncCubeTool()
    }

    private func syncCubeTool() {
        guard tool == .cube, !cube.active, window != nil, bounds.width > 0, canvas.isUserInteractionEnabled else { return }
        cube.scrollWhileDragging = { [weak self] delta in self?.scrollForCube(by: delta) }
        cube.updateNotebook(bounds: boundaryRect, viewportHeight: bounds.height)
        cube.spawn(bounds: boundaryRect, at: viewportCenter(), scale: canvas.zoomScale, offset: canvas.contentOffset)
    }

    private func scrollForCube(by delta: CGFloat) {
        guard tool == .cube, !isOverview, !isPinching, !isSnapping, !pageTurnPending else { return }
        let minimum = -canvas.contentInset.top
        let maximum = max(minimum, boundaryRect.maxY * canvas.zoomScale - bounds.height)
        let y = min(maximum, max(minimum, canvas.contentOffset.y + delta))
        guard abs(y - canvas.contentOffset.y) > 0.01 else { return }
        // This is viewport travel only. It must never arm pull-to-create pages.
        isUpdatingViewport = true
        canvas.setContentOffset(CGPoint(x: canvas.contentOffset.x, y: y), animated: false)
        isUpdatingViewport = false
        updateViewport()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { cube.shutdown() } else { syncCubeTool() }
    }

    private func applyTool() {
        // Reassigning a PencilKit tool cancels its active gestures. SwiftUI updates
        // pull feedback during scrolling, so unchanged tools must be left alone.
        if tool != .eraser {
            if let current = canvas.tool as? PKInkingTool, current.inkType == .pen,
               current.width == 2.5, MonochromeInk.matches(current.color, inkColor) { return }
            canvas.tool = PKInkingTool(.pen, color: inkColor, width: 2.5)
        } else if !(canvas.tool is PKEraserTool) {
            canvas.tool = PKEraserTool(.vector)
        }
    }

    private func setAppearance(_ style: UIUserInterfaceStyle) {
        guard style != .unspecified, style != presentationStyle else { return }
        presentationStyle = style
        backdrop.overrideUserInterfaceStyle = style
        circleHosting?.overrideUserInterfaceStyle = style
        cubeHosting?.overrideUserInterfaceStyle = style
        invalidateEdgeSnapshot()
        applyAppearance()
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
        let recolored = inkPresentation.refresh(canvas.drawing, to: inkColor)
        // Refresh the entire note, including unmounted/off-screen tiles. Merely
        // clearing/reassigning a drawing with unchanged IDs refreshes visible ink
        // but can leave other pages cached. Canonical IDs are restored on save.
        canvas.drawing = PKDrawing()
        canvas.drawing = recolored
        if wasRegistering { manager?.enableUndoRegistration() }
        isUpdatingInk = false
    }

    func drawingDidChange() {
        // The popup is already idle while a declined preview is springing home.
        // Undo or programmatic edits must still remove that visual immediately.
        if previewPageCount != nil { circleIntent.cancel() }
        else { circleIntent.drawingDidChange() }
    }

    private func showAutofillPreview(_ result: AutofillLayout.Result?, animatedReturn: Bool = false) {
        if let result {
            // Retain any temporary pages until moving ink has finished crossing
            // them. Decline releases them only after the return spring settles.
            previewPageCount = max(previewPageCount ?? pageCount, result.pageCount)
            autofillPreview.show(result, style: presentationStyle, from: canvas)
        } else { autofillPreview.dismiss(animated: animatedReturn) }
        // An opaque paper preview covers the ink without hiding the real input
        // view. Its alpha must stay at one for Pencil/touch and accessibility.
        canvas.contentSize = CGSize(width: documentSize.width * canvas.zoomScale,
                                    height: documentSize.height * canvas.zoomScale)
        invalidateEdgeSnapshot()
        updateViewport()
    }

    private func finishAutofillReflow(pageCount count: Int?) {
        let previousCount = displayedPageCount
        previewPageCount = count
        canvas.contentSize = CGSize(width: documentSize.width * canvas.zoomScale,
                                    height: documentSize.height * canvas.zoomScale)
        if displayedPageCount < previousCount {
            canvas.contentOffset = clampedOffset(center: viewportCenter(), scale: canvas.zoomScale)
        }
        invalidateEdgeSnapshot()
        updateViewport()
    }

    private func applyAutofill(from before: AutofillDocument, to after: AutofillDocument) throws {
        guard let persistAutofill else { throw AutofillEditError.unavailable }
        // Decode before persisting; a failed decode cannot leave model and canvas apart.
        let drawing = try AutofillDocument.drawing(after.ink)
        try persistAutofill(before, after)
        let manager = canvas.undoManager
        let registering = manager?.isUndoRegistrationEnabled == true
        isUpdatingInk = true
        if registering { manager?.disableUndoRegistration() }
        canvas.drawing = inkPresentation.refresh(drawing, to: inkColor)
        if registering { manager?.enableUndoRegistration() }
        isUpdatingInk = false
        pageCount = after.pageCount
        pageIndex = min(pageIndex, max(0, pageCount - 1))
        showAutofillPreview(nil)
        syncPageState()
        registerAutofillUndo(from: after, to: before)
        onUndoStateChange?()
    }

    private func registerAutofillUndo(from current: AutofillDocument, to previous: AutofillDocument) {
        canvas.undoManager?.registerUndo(withTarget: self) { host in
            host.circleIntent.cancel()
            do { try host.applyAutofill(from: current, to: previous) }
            catch {
                // A failed save leaves both editor and store unchanged. Register the
                // same direction on the opposite stack so the operation is retryable.
                host.registerAutofillUndo(from: current, to: previous)
                UIAccessibility.post(notification: .announcement, argument: error.localizedDescription)
            }
        }
        canvas.undoManager?.setActionName("Autofill")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        cubeContainer.frame = bounds
        cubeHosting?.view.frame = bounds
        circleContainer.frame = bounds
        circleHosting?.view.frame = bounds
        bandHosting?.view.frame = bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        isLayingOut = true
        if surface.frame != bounds { surface.frame = bounds }
        if backdrop.frame != bounds { backdrop.frame = bounds }
        if canvas.frame != bounds { canvas.frame = bounds }
        if autofillPreview.frame != bounds { autofillPreview.frame = bounds }
        if edgeBlur.frame != bounds { edgeBlur.frame = bounds }
        if guides.frame != bounds { guides.frame = bounds }
        if lastViewportSize != bounds.size {
            stopAnimations()
            invalidateEdgeSnapshot()
            resetCamera()
            guides.hide(animated: false)
        }
        #if DEBUG
        // XCTest's built-in pinch starts at the target's corners. A test-only
        // central accessibility target keeps its fingers off the floating controls;
        // the actual touches still go through the normal PencilKit recognizers.
        if ProcessInfo.processInfo.arguments.contains("--canvasGestureTestArea") {
            if zoomTestArea == nil {
                let area = UIAccessibilityElement(accessibilityContainer: self)
                area.accessibilityLabel = "Canvas zoom test area"
                zoomTestArea = area
                accessibilityElements = [canvas, area]
            }
            zoomTestArea?.accessibilityFrameInContainerSpace = bounds.insetBy(dx: 180, dy: 180)
        }
        #endif
        lastViewportSize = bounds.size
        isLayingOut = false
        applyAppearance()
        syncCubeTool()
    }

    private func resetCamera() {
        pageFitScale = NotebookPaging.fitScale(viewport: bounds.size)
        canvas.minimumZoomScale = pageFitScale * 0.3
        canvas.zoomScale = pageFitScale
        canvas.contentSize = CGSize(width: documentSize.width * canvas.zoomScale, height: documentSize.height * canvas.zoomScale)
        updateScrollInsets()
        canvas.contentOffset = clampedOffset(center: CGPoint(x: currentPageRect.midX, y: currentPageRect.minY + min(currentPageRect.height, bounds.height / pageFitScale) / 2), scale: canvas.zoomScale)
    }

    private func updateScrollInsets() {
        let desired: UIEdgeInsets
        do {
            let rect = boundaryRect
            let scale = canvas.zoomScale
            let horizontalMargin = max(0, (bounds.width - rect.width * scale) / 2)
            let verticalMargin = max(0, (bounds.height - rect.height * scale) / 2)
            desired = UIEdgeInsets(top: verticalMargin - rect.minY * scale,
                                   left: horizontalMargin - rect.minX * scale,
                                   bottom: verticalMargin + (isOverview ? 0 : 200),
                                   right: horizontalMargin - (documentSize.width - rect.maxX) * scale)
        }
        if canvas.contentInset != desired {
            let offset = canvas.contentOffset
            canvas.contentInset = desired
            canvas.contentOffset = offset
        }
    }

    private var pullDistance: CGFloat {
        let minimum = -canvas.contentInset.top
        let maximum = max(minimum, canvas.contentSize.height - bounds.height + canvas.contentInset.bottom)
        return NotebookPaging.signedPull(offset: canvas.contentOffset.y, minimum: minimum, maximum: maximum)
    }

    private var maximumScrollOffset: CGFloat {
        max(-canvas.contentInset.top, canvas.contentSize.height - bounds.height + canvas.contentInset.bottom)
    }

    /// Only genuine scroll callbacks classify pointer bursts; layout/SwiftUI
    /// updates cannot manufacture an input session or inherit its momentum.
    func didScroll() {
        let offset = canvas.contentOffset.y
        defer { previousScrollOffset = offset; updateViewport() }
        guard previewPageCount == nil, !isUpdatingViewport, !isLayingOut, !isOverview, !isPinching, !isSnapping,
              !isPullActive, !canvas.isTracking, !canvas.isDragging, !canvas.isDecelerating else {
            lastWheelInput = CACurrentMediaTime()
            wheelCanCreate = false
            return
        }
        guard abs(offset - previousScrollOffset) > 0.1 else { return }
        cancelCircleInteraction()
        let now = CACurrentMediaTime()
        if now - lastWheelInput > 0.35 {
            wheelCanCreate = NotebookPaging.canBeginCreation(offset: previousScrollOffset, maximum: maximumScrollOffset)
            lastPull = 0
        }
        lastWheelInput = now
        guard wheelCanCreate, pullDistance > 0 else { return }
        lastPull = max(lastPull, pullDistance)
        pagePull.progress = min(1.35, lastPull / NotebookPaging.pullThreshold)
        wheelEnd?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.finishPagePull() }
        wheelEnd = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36, execute: work)
    }

    func updateViewport() {
        guard bounds.width > 0, bounds.height > 0, !isUpdatingViewport, !isLayingOut else { return }
        isUpdatingViewport = true
        defer { isUpdatingViewport = false }
        updateScrollInsets()
        let scale = canvas.zoomScale
        let offset = canvas.contentOffset
        circleIntent.updateProjection(scale: scale, offset: offset)
        if let capturedBand {
            bandHighlight.rect = CGRect(x: capturedBand.minX * scale - offset.x, y: capturedBand.minY * scale - offset.y,
                                        width: capturedBand.width * scale, height: capturedBand.height * scale)
        }
        autofillPreview.project(from: canvas, style: presentationStyle, showsGrid: backdrop.showsGrid, document: documentSize)
        if cube.visible {
            cube.updateNotebook(bounds: boundaryRect, viewportHeight: bounds.height)
            cube.updateProjection(scale: scale, offset: offset)
        }
        backdrop.update(scale: scale, offset: offset, document: documentSize)
        let pull: CGFloat
        if isPullActive && !isPinching {
            let minimum = -canvas.contentInset.top
            let maximum = max(minimum, canvas.contentSize.height - bounds.height + canvas.contentInset.bottom)
            pull = NotebookPaging.gesturePull(startOffset: dragStartOffset,
                translation: canvas.panGestureRecognizer.translation(in: self).y,
                minimum: minimum, maximum: maximum, viewportHeight: bounds.height)
        } else { pull = pullDistance }
        let pullStrength = min(1.5, abs(pull) / NotebookPaging.pullThreshold)
        // The dark Gaussian edge is a transition through the fit detent. A settled
        // overview always has crisp pages, including while panning around it.
        let transitionStrength = UIAccessibility.isReduceMotionEnabled ? 0 : bezelProgress
        let blurStrength = previewPageCount != nil ? 0 : transitionStrength > 0 ? transitionStrength
            : (isOverview || isTurningPage || isPinching ? 0 : pullStrength)
        let margin: CGFloat = 2 + blurStrength * 94
        let documentFrame = PageGeometry.screenRect(boundaryRect, scale: scale, offset: offset)
        let shelfPoint = CGPoint(x: bounds.midX, y: bounds.height - 66)
        let bottomOverBlack = !documentFrame.insetBy(dx: margin / 2, dy: margin / 2).contains(shelfPoint)
        if pagePull.bottomOverBlack != bottomOverBlack { pagePull.bottomOverBlack = bottomOverBlack }
        let topControlY = safeAreaInsets.top + WorkspaceChrome.topPadding + 26
        let topOverBlack = !documentFrame.contains(CGPoint(x: 46, y: topControlY))
            || !documentFrame.contains(CGPoint(x: bounds.width - 46, y: topControlY))
        if pagePull.topOverBlack != topOverBlack { pagePull.topOverBlack = topOverBlack }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        edgeMask.contentsScale = 96 / margin
        edgeMask.frame = documentFrame.insetBy(dx: -margin, dy: -margin)
        do {
            let path = UIBezierPath()
            let first = max(0, Int(floor(offset.y / scale / NotebookPaging.pageStride)) - 1)
            let last = min(displayedPageCount - 1, Int(ceil((offset.y + bounds.height) / scale / NotebookPaging.pageStride)) + 1)
            if first <= last {
                for index in first...last {
                    let frame = renderedPageFrame(index, scale: scale, offset: offset)
                    path.append(UIBezierPath(roundedRect: frame,
                                             cornerRadius: min(NotebookPaging.cornerRadius * scale, frame.width / 2)))
                }
            }
            pageMask.frame = bounds
            pageMask.path = path.cgPath
            pageMask.fillColor = UIColor.white.cgColor
            // Reveal the black host from the physical viewport perimeter inward,
            // including top/bottom while looking at the middle of a long notebook.
            let feather = 1 + transitionStrength * min(bounds.width, bounds.height) * 0.075
            let intrusion = transitionStrength * min(bounds.width, bounds.height) * 0.018
            bezelMask.contentsScale = 96 / feather
            bezelMask.frame = bounds.insetBy(dx: intrusion - feather, dy: intrusion - feather)
            pageMask.mask = transitionStrength > 0.01 ? bezelMask : (blurStrength > 0.01 ? edgeMask : nil)
            surface.layer.mask = pageMask
        }
        updateTransitionShade(strength: transitionStrength)
        CATransaction.commit()
        if blurStrength > 0.03 { prepareEdgeSnapshot() }
        edgeBlur.update(scale: scale, offset: offset, boundary: boundaryRect, strength: blurStrength,
                        viewportEdges: transitionStrength > 0.01)
        do {
            let anchorIndex = isTurningPage && pagePull.didCreate ? pageCount - 2 : pageCount - 1
            let lastFrame = PageGeometry.screenRect(NotebookPaging.rect(for: max(0, anchorIndex)), scale: scale, offset: offset)
            pagePull.indicatorCenter = CGPoint(x: lastFrame.midX, y: lastFrame.maxY + 42)
            pagePull.indicatorVisible = previewPageCount == nil && !isOverview && lastFrame.maxY < bounds.maxY && lastFrame.maxY > -100
            if isTurningPage && pagePull.didCreate {
                pagePull.birthFrame = renderedPageFrame(pageCount - 1, scale: scale, offset: offset)
                pagePull.creationProgress = snapProgress ?? 0
            }
            if !isSnapping && !isPinching {
                let visibleIndex = min(pageCount - 1, max(0, Int(max(0, viewportCenter().y) / NotebookPaging.pageStride)))
                if visibleIndex != pageIndex {
                    pageIndex = visibleIndex
                    syncPageState()
                    onPageChange?(pageCount, pageIndex)
                }
            }
        }
        if !guideRect.isEmpty {
            guides.update(rect: PageGeometry.screenRect(guideRect, scale: scale, offset: offset), snapProgress: snapProgress,
                          cornerRadius: NotebookPaging.cornerRadius * scale)
        }
        if !isOverview, !isSnapping, !isPinching, !pageTurnPending,
           isPullActive {
            lastPull = canCreateFromPull ? max(0, pull) : 0
            pagePull.progress = min(1.35, lastPull / NotebookPaging.pullThreshold)
            let armed = NotebookPaging.action(pull: lastPull, index: pageIndex, count: pageCount) != .none
            if armed && !wasArmed { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
            wasArmed = armed
            // Crossing the threshold only arms the interaction. UIKit's release
            // callback commits it; reversing below the threshold cancels it.
        }
        let travel = max(0, canvas.contentSize.height - bounds.height)
        pagePull.scrollProgress = travel > 0 ? min(1, max(0, canvas.contentOffset.y / travel)) : 0
        pagePull.rightOverBlack = !documentFrame.contains(CGPoint(x: bounds.width - 48, y: bounds.midY))
        updateAccessibilityValue()
        let canDraw = tool != .cube && tool != .circle && tool != .band && !isOverview && !isPinching && !isSnapping && !pageTurnPending
        if canvas.drawingGestureRecognizer.isEnabled != canDraw { canvas.drawingGestureRecognizer.isEnabled = canDraw }
    }

    private func renderedPageFrame(_ index: Int, scale: CGFloat, offset: CGPoint) -> CGRect {
        let page = NotebookPaging.rect(for: index)
        guard isTurningPage, pagePull.didCreate, index == pageCount - 1 else {
            return PageGeometry.screenRect(page, scale: scale, offset: offset)
        }
        let progress = min(1, max(0, (snapProgress ?? 0) / 0.82))
        let eased = 1 - pow(1 - progress, 3)
        let seed = CGRect(x: creationOrigin.x - 13 / scale, y: creationOrigin.y - 13 / scale,
                          width: 26 / scale, height: 26 / scale)
        let growing = CGRect(x: seed.minX + (page.minX - seed.minX) * eased,
                             y: seed.minY + (page.minY - seed.minY) * eased,
                             width: seed.width + (page.width - seed.width) * eased,
                             height: seed.height + (page.height - seed.height) * eased)
        return PageGeometry.screenRect(growing, scale: scale, offset: offset)
    }

    private func updateTransitionShade(strength: CGFloat) {
        transitionShade.frame = bounds
        transitionShade.opacity = Float(UIAccessibility.isReduceMotionEnabled ? 0 : strength)
        let width = min(bounds.width, bounds.height) * (0.012 + strength * 0.075)
        let frames = [CGRect(x: 0, y: 0, width: width, height: bounds.height),
                      CGRect(x: bounds.width - width, y: 0, width: width, height: bounds.height),
                      CGRect(x: 0, y: 0, width: bounds.width, height: width),
                      CGRect(x: 0, y: bounds.height - width, width: bounds.width, height: width)]
        let starts = [CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5), CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1)]
        let ends = [CGPoint(x: 1, y: 0.5), CGPoint(x: 0, y: 0.5), CGPoint(x: 0.5, y: 1), CGPoint(x: 0.5, y: 0)]
        for index in 0..<4 {
            transitionGradients[index].frame = frames[index]
            transitionGradients[index].startPoint = starts[index]
            transitionGradients[index].endPoint = ends[index]
        }
    }

    func invalidateEdgeSnapshot() { edgeBlur.invalidate() }

    private func prepareEdgeSnapshot() {
        let region: CGRect
        do {
            let visible = CGRect(x: canvas.contentOffset.x / canvas.zoomScale, y: canvas.contentOffset.y / canvas.zoomScale,
                                 width: bounds.width / canvas.zoomScale, height: bounds.height / canvas.zoomScale)
            region = visible.insetBy(dx: -150, dy: -150).intersection(boundaryRect)
        }
        edgeBlur.prepare(drawing: canvas.drawing, rect: region, showsGrid: backdrop.showsGrid, traits: traitCollection)
    }

    @objc private func panChanged(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began: beginPagePull()
        case .changed: updateViewport()
        case .ended: finishPagePull()
        case .cancelled, .failed:
            isPullActive = false
            if !isSnapping && !pageTurnPending { lastPull = 0; pagePull.progress = 0 }
        default: break
        }
    }

    func beginPagePull() {
        circleIntent.cancelTracing()
        guard !isSnapping, !pageTurnPending, !isPullActive else { return }
        wheelEnd?.cancel()
        isPullActive = true
        dragStartOffset = canvas.contentOffset.y
        canCreateFromPull = previewPageCount == nil && NotebookPaging.canBeginCreation(offset: dragStartOffset, maximum: maximumScrollOffset)
        wheelCanCreate = false
        lastPull = 0
        wasArmed = false
        invalidateEdgeSnapshot()
    }

    func targetOffsetForRelease(_ proposed: inout CGPoint) {
        guard !isOverview, !isPinching, !isSnapping else { return }
        if !canCreateFromPull { proposed.y = min(proposed.y, maximumScrollOffset) }
        if NotebookPaging.action(pull: lastPull, index: pageIndex, count: pageCount) != .none {
            // Do not let native momentum aim back at the old page during our turn.
            proposed = canvas.contentOffset
        }
    }

    func finishPagePull() {
        isPullActive = false
        wheelEnd?.cancel()
        guard !isOverview, !isPinching, !isSnapping, !pageTurnPending else { return }
        let action = NotebookPaging.action(pull: lastPull, index: pageIndex, count: pageCount)
        lastPull = 0
        if action == .none { pagePull.progress = 0; return }
        reserveAppend()
    }

    private func reserveAppend() {
        circleIntent.cancel()
        guard !isPullActive, !pageTurnPending, !isSnapping else { return }
        pageTurnPending = true
        // Leave UIKit's callback before cancelling its pan and growing the document.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.pageTurnPending else { return }
            self.pageTurnPending = false
            self.isPullActive = false
            self.lastPull = 0
            self.turnPage(.append)
        }
    }

    private func turnPage(_ action: NotebookPaging.Action) {
        guard action != .none, !isSnapping else { return }
        let sourceCenter = viewportCenter()
        isSnapping = true
        isTurningPage = true
        canvas.isScrollEnabled = false
        creationOrigin = PageGeometry.documentPoint(
            CGPoint(x: pagePull.indicatorCenter.x, y: pagePull.indicatorCenter.y + 63),
            scale: canvas.zoomScale, offset: canvas.contentOffset)
        if action == .append {
            pageCount += 1
            pageIndex = pageCount - 1
        } else { pageIndex += action == .previous ? -1 : 1 }
        pageIndex = min(max(0, pageIndex), pageCount - 1)
        pagePull.didCreate = action == .append
        pagePull.isTurning = true
        pagePull.progress = 1
        syncPageState()
        onPageChange?(pageCount, pageIndex)
        canvas.contentSize = CGSize(width: documentSize.width * canvas.zoomScale, height: documentSize.height * canvas.zoomScale)
        canvas.setContentOffset(canvas.contentOffset, animated: false)
        invalidateEdgeSnapshot()
        prepareEdgeSnapshot()
        let halfViewport = min(currentPageRect.height, bounds.height / pageFitScale) / 2
        focus(on: CGPoint(x: currentPageRect.midX,
                          y: action == .previous ? currentPageRect.maxY - halfViewport : currentPageRect.minY + halfViewport), from: sourceCenter)
    }

    func navigate(to index: Int) {
        guard index >= 0, index < pageCount else { return }
        stopAnimations()
        let page = NotebookPaging.rect(for: index)
        let halfViewport = min(page.height, bounds.height / pageFitScale) / 2
        focus(on: CGPoint(x: page.midX, y: page.minY + halfViewport))
    }

    @objc private func accessibleNextPage() -> Bool {
        guard !isSnapping else { return false }
        turnPage(pageIndex + 1 < pageCount ? .next : .append)
        return true
    }

    @objc private func accessiblePreviousPage() -> Bool {
        guard !isSnapping, pageIndex > 0 else { return false }
        turnPage(.previous)
        return true
    }

    private func syncPageState() {
        pagePull.pageIndex = pageIndex
        pagePull.pageCount = pageCount
        updateAccessibilityValue()
    }

    private func updateAccessibilityValue() {
        let position = "Page \(pageIndex + 1) of \(pageCount)"
        let value = position + (isOverview ? ", overview" : "")
        if canvas.accessibilityValue != value { canvas.accessibilityValue = value }
    }

    @objc private func pinchChanged(_ recognizer: UIPinchGestureRecognizer) {
        // The committed detent owns the camera until its short snap finishes.
        // Disabling UIKit's recognizer below sends a cancellation synchronously.
        guard !isEnteringOverview else { return }
        switch recognizer.state {
        case .began:
            stopAnimations()
            isPinching = true
            pinchStartScale = canvas.zoomScale
            zoomDetentLatched = abs(pinchStartScale / pageFitScale - 1) < 0.03
            if zoomDetentLatched {
                canvas.bouncesZoom = false
                canvas.minimumZoomScale = pageFitScale * 0.98
            }
            invalidateEdgeSnapshot()
            guideRect = currentPageRect
            guides.show()
            updateViewport()
        case .changed:
            if zoomDetentLatched {
                bezelProgress = PageGeometry.zoomPreparation(relativeScale: recognizer.scale / pinchStartScale)
                if bezelProgress >= 1 {
                    enterOverview()
                    return
                }
            }
            updateViewport()
        case .ended:
            releaseZoomDetent()
            isPinching = false
            DispatchQueue.main.async { [weak self] in self?.finishPinch() }
        case .cancelled, .failed:
            releaseZoomDetent()
            isPinching = false
            bezelProgress = 0
            guides.hide(animated: true)
            updateViewport()
        default: break
        }
    }

    private func enterOverview() {
        let startScale = canvas.zoomScale
        let startCenter = viewportCenter()
        let targetScale = PageGeometry.overviewScale(fitScale: pageFitScale, viewport: bounds.size,
                                                    pageHeight: NotebookPaging.pageHeight)
        let targetCenter = CGPoint(x: currentPageRect.midX, y: currentPageRect.midY)
        isEnteringOverview = true
        isSnapping = true
        isPinching = false
        releaseZoomDetent()
        canvas.pinchGestureRecognizer?.isEnabled = false
        canvas.isScrollEnabled = false
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        camera.animate(duration: 0.34) { [weak self] progress in
            guard let self else { return }
            let eased = 1 - pow(1 - progress, 3)
            self.bezelProgress = 1 - eased
            self.canvas.zoomScale = startScale + (targetScale - startScale) * eased
            let center = CGPoint(x: startCenter.x + (targetCenter.x - startCenter.x) * eased,
                                 y: startCenter.y + (targetCenter.y - startCenter.y) * eased)
            self.canvas.contentOffset = self.clampedOffset(center: center, scale: self.canvas.zoomScale)
            self.updateViewport()
        } completion: { [weak self] in
            guard let self else { return }
            self.bezelProgress = 0
            self.isEnteringOverview = false
            self.isSnapping = false
            self.canvas.isScrollEnabled = true
            self.canvas.pinchGestureRecognizer?.isEnabled = true
            self.guides.hide(animated: true)
            self.updateViewport()
        }
    }

    private func releaseZoomDetent() {
        zoomDetentLatched = false
        canvas.minimumZoomScale = pageFitScale * 0.3
        canvas.bouncesZoom = true
    }

    private func finishPinch() {
        guard !isPinching, !isEnteringOverview else { return }
        if canvas.zoomScale >= canvas.minimumZoomScale, PageGeometry.shouldSnap(scale: canvas.zoomScale, fitScale: pageFitScale) {
            focus(on: viewportCenter())
        } else { guides.hide(animated: true) }
        updateViewport()
    }

    @objc private func circleChanged(_ recognizer: CircleGestureRecognizer) {
        switch recognizer.state {
        case .ended:
            if recognizer.isBand {
                let start = PageGeometry.documentPoint(recognizer.bandRect.origin, scale: canvas.zoomScale, offset: canvas.contentOffset)
                let rect = CGRect(origin: start, size: CGSize(width: recognizer.bandRect.width / canvas.zoomScale,
                                                              height: recognizer.bandRect.height / canvas.zoomScale))
                capturedBand = rect
                onBandSelection?(canonicalDrawing, rect)
                return
            }
            let polygon = recognizer.points.map {
                PageGeometry.documentPoint($0, scale: canvas.zoomScale, offset: canvas.contentOffset)
            }
            circleIntent.analyze(drawing: canvas.drawing, polygon: polygon, screenPolygon: recognizer.points,
                                 scale: canvas.zoomScale, offset: canvas.contentOffset)
        case .cancelled, .failed: circleIntent.cancelTracing(); clearBand()
        default: break
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer === circleGesture {
            return tool != .cube && !circleIntent.hasPreview && !isOverview && !isPinching && !isSnapping && !pageTurnPending
                && touch.type == .direct && !circleContainer.point(inside: touch.location(in: circleContainer), with: nil)
        }
        return isOverview && !isPinching && !isSnapping
    }

    @objc private func focusTapped(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, isOverview else { return }
        focus(on: PageGeometry.documentPoint(recognizer.location(in: self), scale: canvas.zoomScale, offset: canvas.contentOffset))
    }

    private func viewportCenter() -> CGPoint {
        PageGeometry.documentPoint(CGPoint(x: bounds.midX, y: bounds.midY), scale: canvas.zoomScale, offset: canvas.contentOffset)
    }

    private func focus(on center: CGPoint, from sourceCenter: CGPoint? = nil) {
        camera.cancel()
        if !isTurningPage {
            pageIndex = min(pageCount - 1, max(0, Int(max(0, center.y) / NotebookPaging.pageStride)))
            syncPageState()
            onPageChange?(pageCount, pageIndex)
        }
        guideRect = NotebookPaging.focusedRect(center: center, viewport: bounds.size, index: pageIndex)
        let startScale = canvas.zoomScale
        let startBezel = bezelProgress
        let startCenter = sourceCenter ?? viewportCenter()
        let targetCenter = CGPoint(x: guideRect.midX, y: guideRect.midY)
        isSnapping = true
        canvas.isScrollEnabled = false
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
            self.bezelProgress = startBezel * (1 - progress)
            self.canvas.zoomScale = max(self.canvas.minimumZoomScale, min(self.canvas.maximumZoomScale, scale))
            self.canvas.contentOffset = self.clampedOffset(center: center, scale: self.canvas.zoomScale)
            self.updateViewport()
        } completion: { [weak self] in
            guard let self else { return }
            self.isSnapping = false
            self.bezelProgress = 0
            self.isTurningPage = false
            self.snapProgress = nil
            self.pagePull.isTurning = false
            self.pagePull.progress = 0
            self.updateScrollInsets()
            self.canvas.contentOffset = self.clampedOffset(center: targetCenter, scale: self.canvas.zoomScale)
            self.guides.hide(animated: false)
            self.canvas.isScrollEnabled = true
            self.updateViewport()
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private func clampedOffset(center: CGPoint, scale: CGFloat) -> CGPoint {
        let rect = boundaryRect
        func axis(_ center: CGFloat, min: CGFloat, max: CGFloat, viewport: CGFloat) -> CGFloat {
            if (max - min) * scale <= viewport { return (min + max) / 2 * scale - viewport / 2 }
            return Swift.min(Swift.max(center * scale - viewport / 2, min * scale), max * scale - viewport)
        }
        return CGPoint(x: axis(center.x, min: rect.minX, max: rect.maxX, viewport: bounds.width),
                       y: axis(center.y, min: rect.minY, max: rect.maxY, viewport: bounds.height))
    }

    private func cancelCircleInteraction() {
        if circleGesture.state == .began || circleGesture.state == .changed {
            circleGesture.isEnabled = false
            circleGesture.isEnabled = true
        }
        circleIntent.cancelTracing()
        clearBand()
    }

    func clearBand() { capturedBand = nil; bandHighlight.rect = nil }

    func revealBulletinSource(page index: Int, bounds: CGRect) {
        circleIntent.cancel()
        let page = NotebookPaging.rect(for: index)
        focus(on: CGPoint(x: page.minX + bounds.midX, y: page.minY + bounds.midY))
    }

    func stopAnimations() {
        cancelCircleInteraction()
        autofillPreview.settle()
        wheelEnd?.cancel()
        pageTurnPending = false
        isPullActive = false
        lastPull = 0
        canCreateFromPull = false
        wheelCanCreate = false
        lastWheelInput = CACurrentMediaTime()
        camera.cancel()
        isEnteringOverview = false
        bezelProgress = 0
        canvas.pinchGestureRecognizer?.isEnabled = true
        releaseZoomDetent()
        if !canvas.isScrollEnabled { canvas.isScrollEnabled = true }
        isSnapping = false
        isTurningPage = false
        snapProgress = nil
        if pagePull.isTurning || pagePull.progress != 0 {
            DispatchQueue.main.async { [weak self] in
                self?.pagePull.isTurning = false
                self?.pagePull.progress = 0
            }
        }
    }

}
