import PencilKit
import UIKit

/// Stable ink coordinates shared by a page notebook and an optional freeform camera.
final class CanvasHostView: UIView, UIGestureRecognizerDelegate {
    let canvas = PKCanvasView()
    var onPageChange: ((Int, Int) -> Void)?
    #if DEBUG
    private var zoomTestArea: UIAccessibilityElement?
    #endif
    private let pagePull: PagePullState
    private let surface = UIView()
    private let backdrop = CanvasBackdrop()
    private let edgeBlur = CanvasEdgeBlurView()
    private let guides = CanvasGuidesView()
    private let edgeMask = CanvasEdgeMask.makeLayer()
    private let pageMask = CAShapeLayer()
    private let transitionShade = CALayer()
    private var transitionGradients: [CAGradientLayer] = []
    private let camera = CanvasCameraAnimator()
    private var guideRect = CGRect.zero
    private var lastViewportSize = CGSize.zero
    private var infiniteHeight: CGFloat = 6_000
    private var pageCount = 1
    private var pageIndex = 0
    private var infiniteCanvasEnabled = false
    private var pageFitScale: CGFloat = 1
    private var isPinching = false
    private var isSnapping = false
    private var isTurningPage = false
    private var creationOrigin = CGPoint.zero
    private var zoomDetentLatched = false
    private var pinchStartScale: CGFloat = 1
    private var snapProgress: CGFloat?
    private var tool: CanvasSession.Tool = .pen
    private var isUpdatingViewport = false
    private var isLayingOut = false
    private var lastPull: CGFloat = 0
    private var wasArmed = false
    private var isPullActive = false
    private var dragStartOffset: CGFloat = 0
    private var pageTurnPending = false
    private var wheelEnd: DispatchWorkItem?
    private(set) var isUpdatingInk = false

    private var documentSize: CGSize {
        CGSize(width: PageGeometry.workspaceWidth,
               height: infiniteCanvasEnabled ? infiniteHeight : NotebookPaging.documentHeight(count: pageCount))
    }
    private var currentPageRect: CGRect { NotebookPaging.rect(for: pageIndex) }
    private var boundaryRect: CGRect {
        if infiniteCanvasEnabled { return CGRect(origin: .zero, size: documentSize) }
        return CGRect(x: PageGeometry.pageOriginX, y: 0, width: PageGeometry.pageWidth,
                      height: documentSize.height)
    }
    private var isOverview: Bool { PageGeometry.isOverview(scale: canvas.zoomScale, fitScale: pageFitScale) }
    private var inkColor: UIColor { traitCollection.userInterfaceStyle == .dark ? .white : .black }

    init(pagePull: PagePullState) {
        self.pagePull = pagePull
        super.init(frame: .zero)
        backgroundColor = .black
        clipsToBounds = true
        addSubview(surface)
        surface.addSubview(backdrop)
        surface.addSubview(canvas)
        surface.addSubview(edgeBlur)
        layer.addSublayer(transitionShade)
        for _ in 0..<4 {
            let gradient = CAGradientLayer()
            gradient.colors = [UIColor.black.withAlphaComponent(0.8).cgColor,
                               UIColor.black.withAlphaComponent(0.32).cgColor, UIColor.clear.cgColor]
            gradient.locations = [0, 0.35, 1]
            transitionShade.addSublayer(gradient)
            transitionGradients.append(gradient)
        }
        addSubview(guides)
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
        canvas.accessibilityHint = "Scroll freely through pages. Scroll past the final page to add a new page. Pinch out to look around, then tap to return to writing."
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
            view.invalidateEdgeSnapshot()
            view.applyAppearance()
        }
    }

    required init?(coder: NSCoder) { fatalError("Use init(pagePull:)") }

    func load(_ drawing: PKDrawing, savedPageCount: Int, pageIndex: Int) {
        canvas.drawing = MonochromeInk.recolor(drawing, to: inkColor)
        let bottom = drawing.bounds.isNull ? 0 : drawing.bounds.maxY
        pageCount = max(1, savedPageCount)
        self.pageIndex = min(max(0, pageIndex), pageCount - 1)
        infiniteHeight = max(6_000, bottom + 2_000, NotebookPaging.documentHeight(count: pageCount))
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.syncPageState()
            if self.pageCount != savedPageCount { self.onPageChange?(self.pageCount, self.pageIndex) }
        }
    }

    func configure(tool: CanvasSession.Tool, allowsFingerDrawing: Bool, showsGrid: Bool, infiniteCanvasEnabled: Bool) {
        self.tool = tool
        let policy: PKCanvasViewDrawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly
        if canvas.drawingPolicy != policy { canvas.drawingPolicy = policy }
        if backdrop.showsGrid != showsGrid { invalidateEdgeSnapshot() }
        backdrop.showsGrid = showsGrid
        if self.infiniteCanvasEnabled != infiniteCanvasEnabled {
            self.infiniteCanvasEnabled = infiniteCanvasEnabled
            stopAnimations()
            invalidateEdgeSnapshot()
            if lastViewportSize != .zero {
                let center = viewportCenter()
                let bottom = canvas.drawing.bounds.isNull ? 0 : canvas.drawing.bounds.maxY
                pageCount = NotebookPaging.inferredPageCount(drawingMaxY: bottom, savedCount: pageCount)
                infiniteHeight = max(infiniteHeight, bottom + 1_500, NotebookPaging.documentHeight(count: pageCount))
                pageIndex = min(max(0, Int(center.y / NotebookPaging.pageStride)), pageCount - 1)
                resetCamera()
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.syncPageState()
                    self.onPageChange?(self.pageCount, self.pageIndex)
                }
            }
        }
        applyTool()
        updateViewport()
    }

    private func applyTool() {
        // Reassigning a PencilKit tool cancels its active gestures. SwiftUI updates
        // pull feedback during scrolling, so unchanged tools must be left alone.
        if tool == .pen {
            if let current = canvas.tool as? PKInkingTool, current.inkType == .pen,
               current.width == 2.5, MonochromeInk.matches(current.color, inkColor) { return }
            canvas.tool = PKInkingTool(.pen, color: inkColor, width: 2.5)
        } else if !(canvas.tool is PKEraserTool) {
            canvas.tool = PKEraserTool(.vector)
        }
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
        isLayingOut = true
        if surface.frame != bounds { surface.frame = bounds }
        if backdrop.frame != bounds { backdrop.frame = bounds }
        if canvas.frame != bounds { canvas.frame = bounds }
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
    }

    private func resetCamera() {
        pageFitScale = infiniteCanvasEnabled ? PageGeometry.fitScale(for: bounds.size) : NotebookPaging.fitScale(viewport: bounds.size)
        canvas.minimumZoomScale = infiniteCanvasEnabled
            ? PageGeometry.minimumScale(viewport: bounds.size, document: documentSize) : pageFitScale * 0.3
        canvas.zoomScale = pageFitScale
        canvas.contentSize = CGSize(width: documentSize.width * canvas.zoomScale, height: documentSize.height * canvas.zoomScale)
        updateScrollInsets()
        canvas.contentOffset = clampedOffset(center: CGPoint(x: currentPageRect.midX, y: currentPageRect.minY + min(currentPageRect.height, bounds.height / pageFitScale) / 2), scale: canvas.zoomScale)
    }

    private func updateScrollInsets() {
        let desired: UIEdgeInsets
        if infiniteCanvasEnabled {
            desired = .zero
        } else {
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

    func updateViewport() {
        guard bounds.width > 0, bounds.height > 0, !isUpdatingViewport, !isLayingOut else { return }
        isUpdatingViewport = true
        defer { isUpdatingViewport = false }
        updateScrollInsets()
        let scale = canvas.zoomScale
        let offset = canvas.contentOffset
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
        let departure = min(1, max(0, (1 - scale / pageFitScale) / 0.28))
        let transitionStrength = (isPinching || isSnapping) ? sin(departure * .pi) : 0
        let blurStrength = isOverview ? transitionStrength : (isTurningPage ? 0 : pullStrength)
        let margin: CGFloat = 2 + blurStrength * 94
        let documentFrame = PageGeometry.screenRect(boundaryRect, scale: scale, offset: offset)
        let shelfPoint = CGPoint(x: bounds.midX, y: bounds.height - 66)
        let bottomOverBlack = !documentFrame.insetBy(dx: margin / 2, dy: margin / 2).contains(shelfPoint)
        if pagePull.bottomOverBlack != bottomOverBlack { pagePull.bottomOverBlack = bottomOverBlack }
        let topOverBlack = !documentFrame.contains(CGPoint(x: 46, y: 64))
            || !documentFrame.contains(CGPoint(x: bounds.width - 46, y: 64))
        if pagePull.topOverBlack != topOverBlack { pagePull.topOverBlack = topOverBlack }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        edgeMask.contentsScale = 96 / margin
        edgeMask.frame = documentFrame.insetBy(dx: -margin, dy: -margin)
        if infiniteCanvasEnabled {
            surface.layer.mask = blurStrength > 0 ? edgeMask : nil
        } else {
            let path = UIBezierPath()
            let first = max(0, Int(floor(offset.y / scale / NotebookPaging.pageStride)) - 1)
            let last = min(pageCount - 1, Int(ceil((offset.y + bounds.height) / scale / NotebookPaging.pageStride)) + 1)
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
            pageMask.mask = blurStrength > 0.01 ? edgeMask : nil
            surface.layer.mask = pageMask
        }
        updateTransitionShade(strength: transitionStrength)
        CATransaction.commit()
        if blurStrength > 0.03 { prepareEdgeSnapshot() }
        edgeBlur.update(scale: scale, offset: offset, boundary: boundaryRect, strength: blurStrength)
        if !infiniteCanvasEnabled {
            let anchorIndex = isTurningPage && pagePull.didCreate ? pageCount - 2 : pageCount - 1
            let lastFrame = PageGeometry.screenRect(NotebookPaging.rect(for: max(0, anchorIndex)), scale: scale, offset: offset)
            pagePull.indicatorCenter = CGPoint(x: lastFrame.midX, y: lastFrame.maxY + 42)
            pagePull.indicatorVisible = !isOverview && lastFrame.maxY < bounds.maxY && lastFrame.maxY > -100
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
                          cornerRadius: infiniteCanvasEnabled ? 0 : NotebookPaging.cornerRadius * scale)
        }
        if !infiniteCanvasEnabled, !isOverview, !isSnapping, !isPinching, !pageTurnPending,
           isPullActive || canvas.isDragging {
            lastPull = pull
            pagePull.progress = min(1.35, max(0, pull) / NotebookPaging.pullThreshold)
            let armed = NotebookPaging.action(pull: pull, index: pageIndex, count: pageCount) != .none
            if armed && !wasArmed { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
            wasArmed = armed
            if armed { reserveAppend() }
        }
        // Simulator scroll-wheel forwarding can omit UIKit's drag lifecycle.
        // Debounce those bursts separately; native touch momentum never arms a page.
        if !infiniteCanvasEnabled, !isOverview, !isSnapping, !isPinching, !pageTurnPending,
           !isPullActive, !canvas.isDragging, !canvas.isTracking, !canvas.isDecelerating, pull > 1 {
            if abs(pull) > abs(lastPull) { lastPull = pull }
            pagePull.progress = min(1.35, max(0, lastPull) / NotebookPaging.pullThreshold)
            wheelEnd?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.finishPagePull() }
            wheelEnd = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
        }
        let travel = max(0, canvas.contentSize.height - bounds.height)
        pagePull.scrollProgress = travel > 0 ? min(1, max(0, canvas.contentOffset.y / travel)) : 0
        pagePull.rightOverBlack = !documentFrame.contains(CGPoint(x: bounds.width - 48, y: bounds.midY))
        updateAccessibilityValue()
        let canDraw = !isOverview && !isPinching && !isSnapping && !pageTurnPending
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
        let width = min(bounds.width, bounds.height) * 0.22
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
        guard !isSnapping, !pageTurnPending, !isPullActive else { return }
        wheelEnd?.cancel()
        isPullActive = true
        dragStartOffset = canvas.contentOffset.y
        lastPull = 0
        wasArmed = false
        invalidateEdgeSnapshot()
    }

    func targetOffsetForRelease(_ proposed: inout CGPoint) {
        guard !infiniteCanvasEnabled, !isOverview, !isPinching, !isSnapping else { return }
        if NotebookPaging.action(pull: lastPull, index: pageIndex, count: pageCount) != .none {
            // Do not let native momentum aim back at the old page during our turn.
            proposed = canvas.contentOffset
        }
    }

    func finishPagePull() {
        isPullActive = false
        wheelEnd?.cancel()
        guard !infiniteCanvasEnabled, !isOverview, !isPinching, !isSnapping, !pageTurnPending else { return }
        let action = NotebookPaging.action(pull: lastPull, index: pageIndex, count: pageCount)
        lastPull = 0
        if action == .none { pagePull.progress = 0; return }
        reserveAppend()
    }

    private func reserveAppend() {
        guard !pageTurnPending, !isSnapping else { return }
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
        guard !infiniteCanvasEnabled, index >= 0, index < pageCount else { return }
        stopAnimations()
        let page = NotebookPaging.rect(for: index)
        let halfViewport = min(page.height, bounds.height / pageFitScale) / 2
        focus(on: CGPoint(x: page.midX, y: page.minY + halfViewport))
    }

    @objc private func accessibleNextPage() -> Bool {
        guard !infiniteCanvasEnabled, !isSnapping else { return false }
        turnPage(pageIndex + 1 < pageCount ? .next : .append)
        return true
    }

    @objc private func accessiblePreviousPage() -> Bool {
        guard !infiniteCanvasEnabled, !isSnapping, pageIndex > 0 else { return false }
        turnPage(.previous)
        return true
    }

    private func syncPageState() {
        pagePull.pageIndex = pageIndex
        pagePull.pageCount = pageCount
        updateAccessibilityValue()
    }

    private func updateAccessibilityValue() {
        let position = infiniteCanvasEnabled ? "Infinite canvas" : "Page \(pageIndex + 1) of \(pageCount)"
        let value = position + (isOverview ? ", overview" : "")
        if canvas.accessibilityValue != value { canvas.accessibilityValue = value }
    }

    @objc private func pinchChanged(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            stopAnimations()
            isPinching = true
            pinchStartScale = canvas.zoomScale
            zoomDetentLatched = abs(pinchStartScale / pageFitScale - 1) < 0.03
            if zoomDetentLatched {
                canvas.bouncesZoom = false
                canvas.minimumZoomScale = pageFitScale * 0.96
            }
            invalidateEdgeSnapshot()
            guideRect = infiniteCanvasEnabled
                ? PageGeometry.pageRect(viewport: bounds.size, scale: canvas.zoomScale, offset: canvas.contentOffset) : currentPageRect
            guides.show()
            updateViewport()
        case .changed:
            if zoomDetentLatched && recognizer.scale < pinchStartScale * 0.82 {
                releaseZoomDetent()
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
            updateViewport()
        case .ended:
            releaseZoomDetent()
            isPinching = false
            DispatchQueue.main.async { [weak self] in self?.finishPinch() }
        case .cancelled, .failed:
            releaseZoomDetent()
            isPinching = false
            guides.hide(animated: true)
            updateViewport()
        default: break
        }
    }

    private func releaseZoomDetent() {
        zoomDetentLatched = false
        canvas.minimumZoomScale = infiniteCanvasEnabled
            ? PageGeometry.minimumScale(viewport: bounds.size, document: documentSize) : pageFitScale * 0.3
        canvas.bouncesZoom = true
    }

    private func finishPinch() {
        guard !isPinching else { return }
        if canvas.zoomScale >= canvas.minimumZoomScale, PageGeometry.shouldSnap(scale: canvas.zoomScale, fitScale: pageFitScale) {
            focus(on: viewportCenter())
        } else { guides.hide(animated: true) }
        updateViewport()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        isOverview && !isPinching && !isSnapping
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
        if !infiniteCanvasEnabled && !isTurningPage {
            pageIndex = min(pageCount - 1, max(0, Int(max(0, center.y) / NotebookPaging.pageStride)))
            syncPageState()
            onPageChange?(pageCount, pageIndex)
        }
        guideRect = infiniteCanvasEnabled
            ? PageGeometry.focusedRect(center: center, viewport: bounds.size, document: documentSize)
            : NotebookPaging.focusedRect(center: center, viewport: bounds.size, index: pageIndex)
        let startScale = canvas.zoomScale
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
            self.canvas.zoomScale = max(self.canvas.minimumZoomScale, min(self.canvas.maximumZoomScale, scale))
            self.canvas.contentOffset = self.clampedOffset(center: center, scale: self.canvas.zoomScale)
            self.updateViewport()
        } completion: { [weak self] in
            guard let self else { return }
            self.isSnapping = false
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

    func stopAnimations() {
        wheelEnd?.cancel()
        pageTurnPending = false
        isPullActive = false
        lastPull = 0
        camera.cancel()
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

    func extendIfNeeded() {
        guard infiniteCanvasEnabled, lastViewportSize != .zero, !isUpdatingViewport, !isLayingOut,
              !isOverview, !isPinching, !isSnapping, canvas.zoomScale > 0 else { return }
        let visibleBottom = (canvas.contentOffset.y + canvas.bounds.height) / canvas.zoomScale
        let drawingBottom = canvas.drawing.bounds.isNull ? 0 : canvas.drawing.bounds.maxY
        let neededHeight = max(visibleBottom, drawingBottom) + 1_500
        guard neededHeight > infiniteHeight else { return }
        infiniteHeight = (neededHeight / 2_000).rounded(.up) * 2_000
        canvas.contentSize = CGSize(width: documentSize.width * canvas.zoomScale, height: infiniteHeight * canvas.zoomScale)
        canvas.minimumZoomScale = PageGeometry.minimumScale(viewport: bounds.size, document: documentSize)
        updateViewport()
    }
}
