import Foundation
import SwiftData

struct NotebookPage: Codable, Identifiable, Equatable {
    var id = UUID()
    var title = ""
    var isTrashed = false
}

/// No cascade relationship: deletion is always an explicit, scoped store operation.
@Model
final class TrashedPage {
    var id: UUID
    var noteID: UUID
    var noteTitle: String
    var originalIndex: Int
    var deletedAt: Date
    @Attribute(.externalStorage) var drawingData: Data

    var label: String { "\(noteTitle) (page \(originalIndex + 1))" }

    init(id: UUID, note: Note, index: Int, drawing: Data) {
        self.id = id
        noteID = note.id
        noteTitle = note.title
        originalIndex = index
        deletedAt = .now
        drawingData = drawing
    }
}
