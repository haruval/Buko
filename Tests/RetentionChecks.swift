import Foundation
import SwiftData

@main struct RetentionChecks {
    enum Injected: Error { case failure }
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let source = URL(fileURLWithPath: CommandLine.arguments[2])
        let original = try Data(contentsOf: source)
        let url = root.appendingPathComponent("notes.store")
        let container = try ModelContainer(for: Note.self, TrashedPage.self, configurations: ModelConfiguration(url: url))
        let context = container.mainContext
        context.autosaveEnabled = false
        let active = Note(title: "Keep active"), trashed = Note(title: "Keep restorable"), deleted = Note(title: "Delete")
        trashed.deletedAt = .now; deleted.deletedAt = .now
        for note in [active, trashed, deleted] {
            try NotebookEdits.prepare(note)
            context.insert(note)
        }
        let ids = [UUID(), UUID()]
        let legacy = try JSONSerialization.data(withJSONObject: [[
            "strokeIDs": ids.map(\.uuidString), "text": "PRIVATE GENERATED ANSWER",
            "selectedText": "PRIVATE SELECTED NOTES", "sources": [["quote": "PRIVATE PDF EXCERPT"]],
            "documentRevision": "old-revision", "title": "PRIVATE TITLE"
        ]])
        active.autofillHistory = legacy; trashed.autofillHistory = legacy
        try context.save()
        let ink = active.drawingData, pages = active.pageMetadata
        try NotebookEdits.minimizeAutofillHistory(in: context)
        for note in [active, trashed] {
            let objects = try JSONSerialization.jsonObject(with: note.autofillHistory!) as! [[String: Any]]
            precondition(objects.count == 1 && Set(objects[0].keys) == ["strokeIDs"])
            let records = try JSONDecoder().decode([AutofillRecord].self, from: note.autofillHistory!)
            precondition(records[0].strokeIDs == ids, "Preserve exclusions for Undo and restored pages")
            precondition(!String(decoding: note.autofillHistory!, as: UTF8.self).contains("PRIVATE"))
        }
        precondition(active.drawingData == ink && active.pageMetadata == pages && deleted.autofillHistory == nil)
        let minimized = active.autofillHistory
        try NotebookEdits.minimizeAutofillHistory(in: context)
        precondition(active.autofillHistory == minimized && !context.hasChanges)
        let reopened = try ModelContainer(for: Note.self, TrashedPage.self, configurations: ModelConfiguration(url: url))
        let reopenedNotes = try reopened.mainContext.fetch(FetchDescriptor<Note>())
        precondition(reopenedNotes.first { $0.id == active.id }?.autofillHistory == minimized)

        // Decode all old data before touching any note; report corruption, never reset.
        active.autofillHistory = legacy; trashed.autofillHistory = Data("corrupt".utf8)
        try context.save()
        do { try NotebookEdits.minimizeAutofillHistory(in: context); preconditionFailure("Corruption must surface") }
        catch is DecodingError { }
        precondition(active.autofillHistory == legacy && trashed.autofillHistory == Data("corrupt".utf8))
        trashed.autofillHistory = legacy; try context.save()
        do {
            try NotebookEdits.commit(in: context, notes: [active]) {
                active.autofillHistory = minimized
                throw Injected.failure
            }
            preconditionFailure("Injected failure must roll back")
        } catch Injected.failure { }
        precondition(active.autofillHistory == legacy)
        try NotebookEdits.minimizeAutofillHistory(in: context)

        let libraryRoot = root.appendingPathComponent("owned-pdfs")
        let library = LectureLibrary(root: libraryRoot)
        let orphan = UUID(), corruptOrphan = UUID()
        for id in [active.id, trashed.id, deleted.id, orphan] {
            _ = try await library.importPDF(from: source, noteID: id)
        }
        let corruptDirectory = libraryRoot.appendingPathComponent(corruptOrphan.uuidString)
        try FileManager.default.createDirectory(at: corruptDirectory, withIntermediateDirectories: true)
        try Data("broken index".utf8).write(to: corruptDirectory.appendingPathComponent("index.json"))
        let unrelated = libraryRoot.appendingPathComponent("do-not-delete")
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        let external = root.appendingPathComponent("external-originals")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let sentinel = external.appendingPathComponent("keep.txt")
        try original.write(to: sentinel)
        let linkID = UUID(), link = libraryRoot.appendingPathComponent(linkID.uuidString)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)

        // A failed database transaction cannot authorize deleting any live/trashed owner.
        let deletedID = deleted.id
        do {
            try NotebookEdits.commit(in: context, notes: [deleted]) {
                try NotebookEdits.emptyTrash(noteIDs: [deletedID], pageIDs: [], context: context)
                throw Injected.failure
            }
            preconditionFailure("Injected deletion must fail")
        } catch Injected.failure { }
        let failedOwners = try NotebookEdits.retainedNoteIDs(in: context)
        precondition(failedOwners.contains(deletedID))
        active.title = "Pending save"
        do { _ = try NotebookEdits.retainedNoteIDs(in: context); preconditionFailure("Unsaved store must block cleanup") }
        catch NotebookEdits.EditError.unsavedWork { }
        try context.save()
        let firstCandidates = try await library.storedNoteIDs()
        precondition(!firstCandidates.contains(linkID))
        try await library.removeNotes(firstCandidates.subtracting(NotebookEdits.retainedNoteIDs(in: context)))
        precondition(!FileManager.default.fileExists(atPath: corruptDirectory.path))
        let liveBeforeDeletion = try await library.documents(noteID: deletedID)
        precondition(liveBeforeDeletion.count == 1)
        let orphanAfter = try await library.documents(noteID: orphan)
        precondition(orphanAfter.isEmpty, "Orphan cleanup must invalidate cached excerpts")

        // Only a successful permanent deletion removes the app-owned PDFs/index.
        try NotebookEdits.commit(in: context, notes: [deleted]) {
            try NotebookEdits.emptyTrash(noteIDs: [deletedID, active.id], pageIDs: [], context: context)
        }
        let candidates = try await library.storedNoteIDs()
        let removed = candidates.subtracting(try NotebookEdits.retainedNoteIDs(in: context))
        precondition(removed == [deletedID])
        try await library.removeNotes(removed)
        try await library.removeNotes(removed) // Retry is idempotent.
        let after = try await library.documents(noteID: deletedID)
        precondition(after.isEmpty && !FileManager.default.fileExists(atPath: libraryRoot.appendingPathComponent(deletedID.uuidString).path))
        for id in [active.id, trashed.id] {
            let retained = try await library.documents(noteID: id)
            precondition(retained.count == 1, "Active and restorable sources must survive")
        }
        do { try await library.removeNotes([linkID]); preconditionFailure("Never follow a directory symlink") }
        catch LectureLibrary.LibraryError.invalidIndex { }
        let originalAfter = try Data(contentsOf: source), sentinelAfter = try Data(contentsOf: sentinel)
        precondition(originalAfter == original && sentinelAfter == original)
        precondition(FileManager.default.fileExists(atPath: unrelated.path))
        print("Retention checks passed: legacy minimization/reopen/idempotence, stroke IDs, corrupt/transaction-failure preservation, committed deletion, startup orphans, corrupt indexes, cache invalidation, active/trash/source/sibling/symlink isolation")
    }
}
