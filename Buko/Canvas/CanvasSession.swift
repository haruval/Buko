import Observation
import PencilKit

/// Ephemeral editor controls. PencilKit owns the live strokes; Note owns their saved data.
@Observable
final class CanvasSession {
    enum Tool: String, CaseIterable {
        case pen, eraser, circle, band, cube
    }

    let pagePull = PagePullState()
    var tool: Tool = .pen
    var allowsFingerDrawing = false
    var canUndo = false
    var canRedo = false
    var loadError: String?
    var isDrawing = false
    weak var canvas: PKCanvasView?
    weak var host: CanvasHostView?

    func navigate(to index: Int) { host?.navigate(to: index) }

    func undo() {
        canvas?.undoManager?.undo()
        refreshUndoState()
    }

    func redo() {
        canvas?.undoManager?.redo()
        refreshUndoState()
    }

    func refreshUndoState() {
        canUndo = canvas?.undoManager?.canUndo ?? false
        canRedo = canvas?.undoManager?.canRedo ?? false
    }
}
