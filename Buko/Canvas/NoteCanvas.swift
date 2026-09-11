import PencilKit
import SwiftUI

struct NoteCanvas: UIViewRepresentable {
    let note: Note
    let session: CanvasSession
    let showsGrid: Bool
    let onDrawingChange: (Data) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, onDrawingChange: onDrawingChange)
    }

    func makeUIView(context: Context) -> CanvasHostView {
        let host = CanvasHostView()
        do {
            let drawing = note.drawingData.isEmpty ? PKDrawing() : try PKDrawing(data: note.drawingData)
            host.load(drawing)
        } catch {
            host.canvas.isUserInteractionEnabled = false
            Task { @MainActor in
                session.loadError = "This drawing couldn’t be opened. Its saved data has been preserved."
            }
        }
        host.canvas.delegate = context.coordinator
        context.coordinator.host = host
        session.canvas = host.canvas
        host.configure(tool: session.tool, allowsFingerDrawing: session.allowsFingerDrawing, showsGrid: showsGrid)
        return host
    }

    func updateUIView(_ host: CanvasHostView, context: Context) {
        context.coordinator.onDrawingChange = onDrawingChange
        host.configure(tool: session.tool, allowsFingerDrawing: session.allowsFingerDrawing, showsGrid: showsGrid)
    }

    static func dismantleUIView(_ host: CanvasHostView, coordinator: Coordinator) {
        host.stopAnimations()
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
            guard let host, !host.isUpdatingInk else { return }
            // Undo may restore strokes created under another appearance.
            host.normalizeDisplayedInk()
            onDrawingChange(MonochromeInk.canonical(canvasView.drawing).dataRepresentation())
            session.refreshUndoState()
            host.extendIfNeeded()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            host?.updateViewport()
            host?.extendIfNeeded()
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            host?.updateViewport()
        }
    }
}
