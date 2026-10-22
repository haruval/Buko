import PencilKit
import SwiftUI

struct NoteCanvas: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    let note: Note
    let session: CanvasSession
    let showsGrid: Bool
    let onPageChange: (Int, Int) -> Void
    let onDrawingChange: (Data) -> Void
    let handwritingDocuments: () -> [AutofillDocument]
    let onAutofillCommit: (AutofillDocument, AutofillDocument) throws -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, onDrawingChange: onDrawingChange)
    }

    func makeUIView(context: Context) -> CanvasHostView {
        let host = CanvasHostView(pagePull: session.pagePull)
        host.circleIntent.noteID = note.id
        do {
            let drawing = note.drawingData.isEmpty ? PKDrawing() : try PKDrawing(data: note.drawingData)
            context.coordinator.hasLoadedDrawing = true
            host.onPageChange = onPageChange
            host.load(drawing, savedPageCount: note.pageCount, pageIndex: note.currentPageIndex)
        } catch {
            host.canvas.isUserInteractionEnabled = false
            Task { @MainActor in
                session.loadError = "This drawing couldn’t be opened. Its saved data has been preserved."
            }
        }
        context.coordinator.host = host
        // A failed decode must never attach a writer to the empty fallback canvas.
        // Blocking touches alone does not block programmatic delegate callbacks.
        if context.coordinator.hasLoadedDrawing {
            host.canvas.delegate = context.coordinator
            session.canvas = host.canvas
            session.host = host
            host.captureAutofillDocument = { [weak note] in
                guard let note, note.deletedAt == nil else { return nil }
                return AutofillDocument(note)
            }
            host.captureHandwritingDocuments = handwritingDocuments
            host.persistAutofill = onAutofillCommit
            host.onUndoStateChange = { [weak session] in session?.refreshUndoState() }
        }
        host.configure(tool: session.tool, allowsFingerDrawing: session.allowsFingerDrawing, showsGrid: showsGrid,
                       colorScheme: colorScheme)
        return host
    }

    func updateUIView(_ host: CanvasHostView, context: Context) {
        context.coordinator.onDrawingChange = onDrawingChange
        host.onPageChange = context.coordinator.hasLoadedDrawing ? onPageChange : nil
        host.captureHandwritingDocuments = context.coordinator.hasLoadedDrawing ? handwritingDocuments : nil
        host.persistAutofill = context.coordinator.hasLoadedDrawing ? onAutofillCommit : nil
        host.configure(tool: session.tool, allowsFingerDrawing: session.allowsFingerDrawing, showsGrid: showsGrid,
                       colorScheme: colorScheme)
    }

    static func dismantleUIView(_ host: CanvasHostView, coordinator: Coordinator) {
        host.cube.shutdown()
        host.circleIntent.cancel()
        host.stopAnimations()
        host.canvas.delegate = nil
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let session: CanvasSession
        var onDrawingChange: (Data) -> Void
        weak var host: CanvasHostView?
        var hasLoadedDrawing = false

        init(session: CanvasSession, onDrawingChange: @escaping (Data) -> Void) {
            self.session = session
            self.onDrawingChange = onDrawingChange
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) { host?.circleIntent.cancel(); session.isDrawing = true }
        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) { session.isDrawing = false }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard hasLoadedDrawing, let host, !host.isUpdatingInk else { return }
            host.circleIntent.drawingDidChange()
            // Undo may restore strokes created under another appearance.
            host.normalizeDisplayedInk()
            onDrawingChange(host.canonicalDrawing.dataRepresentation())
            session.refreshUndoState()
            host.invalidateEdgeSnapshot()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            host?.didScroll()
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            host?.beginPagePull()
        }

        func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                      targetContentOffset: UnsafeMutablePointer<CGPoint>) {
            host?.targetOffsetForRelease(&targetContentOffset.pointee)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            host?.finishPagePull()
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            host?.updateViewport()
        }
    }
}
