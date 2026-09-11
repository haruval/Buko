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
            canvas.tool = PKInkingTool(.pen, color: UIColor.label, width: 2.5)
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
            host?.updatePaperFrame()
            host?.extendIfNeeded()
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            host?.updatePaperFrame()
        }
    }
}

/// A fixed-width writing page inside a wider workspace. The page is only a visual
/// guide: PencilKit can draw on either side, and the document grows down on demand.
final class CanvasHostView: UIView {
    let canvas = PKCanvasView()
    private let paper = UIView()
    private let pageWidth: CGFloat = 1_000
    private let pageOriginX: CGFloat = 1_000
    private let workspaceWidth: CGFloat = 3_000
    var documentHeight: CGFloat = 6_000
    private var hasPositionedPage = false
    private(set) var pageFitScale: CGFloat = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        paper.backgroundColor = .systemBackground
        paper.layer.shadowColor = UIColor.black.cgColor
        paper.layer.shadowOpacity = 0.08
        paper.layer.shadowRadius = 16
        paper.isUserInteractionEnabled = false
        addSubview(paper)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.alwaysBounceVertical = true
        canvas.showsHorizontalScrollIndicator = false
        canvas.showsVerticalScrollIndicator = false
        canvas.maximumZoomScale = 4
        canvas.accessibilityLabel = "Note canvas"
        canvas.accessibilityHint = "Write with Apple Pencil. Drag with a finger to move, or pinch to zoom."
        addSubview(canvas)
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        canvas.frame = bounds
        if !hasPositionedPage {
            hasPositionedPage = true
            pageFitScale = bounds.width / pageWidth
            canvas.minimumZoomScale = pageFitScale * 0.3
            canvas.contentSize = CGSize(width: workspaceWidth, height: documentHeight)
            canvas.zoomScale = pageFitScale
            canvas.contentOffset = CGPoint(x: pageOriginX * pageFitScale, y: 0)
        }
        updatePaperFrame()
    }

    func updatePaperFrame() {
        let scale = canvas.zoomScale
        paper.frame = CGRect(
            x: pageOriginX * scale - canvas.contentOffset.x,
            y: -canvas.contentOffset.y,
            width: pageWidth * scale,
            height: documentHeight * scale
        )
    }

    func extendIfNeeded() {
        guard hasPositionedPage, !canvas.isZooming, canvas.zoomScale > 0 else { return }
        let visibleBottom = (canvas.contentOffset.y + canvas.bounds.height) / canvas.zoomScale
        let drawingBottom = canvas.drawing.bounds.isNull ? 0 : canvas.drawing.bounds.maxY
        let neededHeight = max(visibleBottom, drawingBottom) + 1_500
        guard neededHeight > documentHeight else { return }
        documentHeight = (neededHeight / 2_000).rounded(.up) * 2_000
        canvas.contentSize = CGSize(width: workspaceWidth * canvas.zoomScale, height: documentHeight * canvas.zoomScale)
        updatePaperFrame()
    }
}
