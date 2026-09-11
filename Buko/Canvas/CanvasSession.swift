import Observation
import PencilKit

/// Ephemeral editor controls. PencilKit owns the live strokes; Note owns their saved data.
@Observable
final class CanvasSession {
    enum Tool: String, CaseIterable {
        case pen, eraser
    }

    let pagePull = PagePullState()
    var tool: Tool = .pen
    var allowsFingerDrawing = false
    var canUndo = false
    var canRedo = false
    var loadError: String?
    weak var canvas: PKCanvasView?

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
