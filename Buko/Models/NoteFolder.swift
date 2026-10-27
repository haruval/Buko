import Foundation
import SwiftData

@Model
final class NoteFolder {
    var id: UUID
    var title: String
    var createdAt: Date

    init(title: String = "New folder") {
        id = UUID()
        self.title = title
        createdAt = .now
    }
}

/// Membership never owns ink. Ungrouping preserves active and trashed notes.
@MainActor
enum LibraryOrganization {
    static func group(_ source: Note, with target: Note, in context: ModelContext) throws {
        guard source.id != target.id, source.deletedAt == nil, target.deletedAt == nil else { return }
        let folders = try context.fetch(FetchDescriptor<NoteFolder>())
        try NotebookEdits.commit(in: context, notes: [source, target]) {
            if let id = target.folderID, folders.contains(where: { $0.id == id }) {
                source.folderID = id
            } else {
                let folder = NoteFolder(title: Note.uniqueTitle("New folder", occupied: Set(folders.map(\.title))))
                context.insert(folder)
                source.folderID = folder.id
                target.folderID = folder.id
            }
        }
    }

    static func move(_ note: Note, to folder: NoteFolder?, in context: ModelContext) throws {
        guard note.deletedAt == nil else { return }
        try NotebookEdits.commit(in: context, notes: [note]) { note.folderID = folder?.id }
    }

    static func rename(_ folder: NoteFolder, to title: String, in context: ModelContext) throws {
        let oldTitle = folder.title
        let trimmed = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        guard !trimmed.isEmpty, trimmed != oldTitle else { return }
        do { try NotebookEdits.commit(in: context) { folder.title = trimmed } }
        catch { folder.title = oldTitle; throw error }
    }

    static func ungroup(_ folder: NoteFolder, in context: ModelContext) throws {
        let id = folder.id
        let notes = try context.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.folderID == id }))
        try NotebookEdits.commit(in: context, notes: notes) {
            for note in notes { note.folderID = nil }
            context.delete(folder)
        }
    }
}
