import Foundation
import PencilKit
import SwiftData

/// Page edits decode and stage complete stroke values before changing any model.
/// Callers flush pending drawing saves first, then commit through `commit`.
@MainActor
enum NotebookEdits {
    enum EditError: LocalizedError {
        case invalidPage, missingNote, invalidLayout, unsavedWork
        var errorDescription: String? {
            switch self {
            case .unsavedWork: "Save the current changes before editing pages or emptying Trash."
            case .invalidPage: "That page is no longer available. No saved content was removed."
            case .missingNote: "The original note could not be found. The page remains in Trash."
            case .invalidLayout: "This notebook’s page information could not be read. Its saved data has been preserved."
            }
        }
    }

    static func drawing(_ data: Data) throws -> PKDrawing {
        data.isEmpty ? PKDrawing() : try PKDrawing(data: data)
    }

    static func shifted(_ stroke: PKStroke, by distance: CGFloat) -> PKStroke {
        var result = stroke
        result.transform = stroke.transform.concatenating(CGAffineTransform(translationX: 0, y: distance))
        return result
    }

    /// A stroke belongs to the page where it began. Keep the entire stroke,
    /// including paths/masks crossing a page boundary; never crop or discard points.
    static func owner(of stroke: PKStroke, stride: CGFloat? = nil, count: Int) -> Int {
        let y = stroke.path.count > 0 ? stroke.path[0].location.applying(stroke.transform).y : stroke.renderBounds.midY
        guard y.isFinite else { return 0 }
        return min(max(0, count - 1), max(0, Int(floor((max(0, y) + 0.000001) / (stride ?? NotebookPaging.pageStride)))))
    }

    static func prepare(_ note: Note) throws {
        var ink = try drawing(note.drawingData)
        guard note.pageLayoutVersion <= 1 else { throw EditError.invalidLayout }
        var pages = try note.pages()
        if note.pageLayoutVersion == 0 {
            let bottom = ink.bounds.isNull ? 0 : ink.bounds.maxY
            guard bottom.isFinite else { throw EditError.invalidLayout }
            let count = max(1, note.pageCount, Int(ceil(max(0, bottom) / NotebookPaging.pageHeight)))
            ink = PKDrawing(strokes: ink.strokes.map { stroke in
                shifted(stroke, by: CGFloat(owner(of: stroke, stride: NotebookPaging.pageHeight, count: count)) * NotebookPaging.pageGap)
            })
            if pages.isEmpty { pages = (0..<count).map { _ in NotebookPage() } }
            let bytes = ink.dataRepresentation()
            let metadata = try JSONEncoder().encode(pages)
            note.drawingData = bytes
            note.pageMetadata = metadata
            note.pageLayoutVersion = 1
            note.pageCount = pages.filter { !$0.isTrashed }.count
        }
        guard Set(pages.map(\.id)).count == pages.count,
              pages.filter({ !$0.isTrashed }).count == note.pageCount else { throw EditError.invalidLayout }
    }

    static func appendMetadata(to note: Note, count: Int) throws {
        var pages = try note.pages()
        let activeCount = pages.filter { !$0.isTrashed }.count
        guard count >= activeCount else { throw EditError.invalidLayout }
        pages.append(contentsOf: (activeCount..<count).map { _ in NotebookPage() })
        try note.setPages(pages)
    }

    static func rename(_ id: UUID, in note: Note, to title: String) throws {
        var pages = try note.pages()
        guard let slot = pages.firstIndex(where: { $0.id == id && !$0.isTrashed }) else { throw EditError.invalidPage }
        pages[slot].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        try note.setPages(pages)
        note.updatedAt = .now
    }

    static func trash(_ id: UUID, in note: Note, context: ModelContext) throws {
        guard note.deletedAt == nil else { throw EditError.invalidPage }
        var pages = try note.pages()
        let active = pages.filter { !$0.isTrashed }
        guard let index = active.firstIndex(where: { $0.id == id }),
              let slot = pages.firstIndex(where: { $0.id == id }) else { throw EditError.invalidPage }
        let ink = try drawing(note.drawingData)
        var retained: [PKStroke] = []
        var archived: [PKStroke] = []
        for stroke in ink.strokes {
            let page = owner(of: stroke, count: active.count)
            if page == index { archived.append(shifted(stroke, by: -CGFloat(index) * NotebookPaging.pageStride)) }
            else { retained.append(shifted(stroke, by: page > index ? -NotebookPaging.pageStride : 0)) }
        }
        let archive = TrashedPage(id: id, note: note, index: index,
                                  drawing: PKDrawing(strokes: archived).dataRepresentation())
        let retainedData = PKDrawing(strokes: retained).dataRepresentation()
        pages[slot].isTrashed = true
        try note.setPages(pages)
        note.drawingData = retainedData
        note.currentPageIndex = min(index, max(0, note.pageCount - 1))
        note.updatedAt = .now
        context.insert(archive)
    }

    @discardableResult
    static func restore(_ archive: TrashedPage, context: ModelContext) throws -> Note {
        let ownerID = archive.noteID
        guard let note = try context.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.id == ownerID })).first else {
            throw EditError.missingNote
        }
        var pages = try note.pages()
        guard let slot = pages.firstIndex(where: { $0.id == archive.id && $0.isTrashed }) else { throw EditError.invalidPage }
        // Tombstones retain original order even when pages are restored out of order.
        let index = pages[..<slot].filter { !$0.isTrashed }.count
        let existing = try drawing(note.drawingData)
        let returning = try drawing(archive.drawingData)
        var strokes = existing.strokes.map { stroke in
            shifted(stroke, by: owner(of: stroke, count: note.pageCount) >= index ? NotebookPaging.pageStride : 0)
        }
        strokes.append(contentsOf: returning.strokes.map { shifted($0, by: CGFloat(index) * NotebookPaging.pageStride) })
        let bytes = PKDrawing(strokes: strokes).dataRepresentation()
        pages[slot].isTrashed = false
        try note.setPages(pages)
        note.drawingData = bytes
        note.deletedAt = nil
        note.currentPageIndex = index
        note.updatedAt = .now
        context.delete(archive)
        return note
    }

    /// Deletes only the explicitly captured trash IDs, rechecking note trash status.
    /// No URLs, paths, file deletion, store reset, or cascade relationship is involved.
    static func emptyTrash(noteIDs: Set<UUID>, pageIDs: Set<UUID>, context: ModelContext) throws {
        let notes = try context.fetch(FetchDescriptor<Note>())
        let allArchives = try context.fetch(FetchDescriptor<TrashedPage>())
        let deletedNotes = notes.filter { note in
            note.deletedAt != nil && noteIDs.contains(note.id)
                && !allArchives.contains { $0.noteID == note.id && !pageIDs.contains($0.id) }
        }
        let deletedIDs = Set(deletedNotes.map(\.id))
        let pages = allArchives.filter { pageIDs.contains($0.id) }
        for archive in pages {
            if !deletedIDs.contains(archive.noteID), let owner = notes.first(where: { $0.id == archive.noteID }) {
                var manifest = try owner.pages()
                guard manifest.filter({ !$0.isTrashed }).count == owner.pageCount else { throw EditError.invalidLayout }
                manifest.removeAll { $0.id == archive.id && $0.isTrashed }
                try owner.setPages(manifest)
            }
        }
        for note in deletedNotes { context.delete(note) }
        for archive in pages { context.delete(archive) }
    }

    private struct NoteSnapshot {
        let note: Note
        let title: String
        let updatedAt: Date
        let deletedAt: Date?
        let count: Int
        let index: Int
        let version: Int
        let metadata: Data
        let ink: Data

        init(_ note: Note) {
            self.note = note; title = note.title; updatedAt = note.updatedAt; deletedAt = note.deletedAt
            count = note.pageCount; index = note.currentPageIndex; version = note.pageLayoutVersion
            metadata = note.pageMetadata; ink = note.drawingData
        }

        func restore() {
            note.title = title; note.updatedAt = updatedAt; note.deletedAt = deletedAt
            note.pageCount = count; note.currentPageIndex = index; note.pageLayoutVersion = version
            note.pageMetadata = metadata; note.drawingData = ink
        }
    }

    static func commit(in context: ModelContext, notes: [Note] = [], _ edit: () throws -> Void) throws {
        // Scope snapshots to affected notes, never all drawings in the library.
        guard !context.hasChanges else { throw EditError.unsavedWork }
        let snapshots = notes.map(NoteSnapshot.init)
        let wasAutosaving = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = wasAutosaving }
        do { try edit(); try context.save() }
        catch {
            context.rollback()
            // SwiftData rollback can leave @Model's observed property cache stale.
            // Restore the editor values too; the previously committed store is intact.
            snapshots.forEach { $0.restore() }
            // If storage is still unavailable, retain the original values for Retry.
            if context.hasChanges { try? context.save() }
            throw error
        }
    }
}
