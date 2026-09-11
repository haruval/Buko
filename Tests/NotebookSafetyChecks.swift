import Foundation
import PencilKit
import SwiftData

@main struct NotebookSafetyChecks {
    enum Injected: Error { case failure }

    @MainActor static func main() throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let storage = try ModelContainer(for: Note.self, TrashedPage.self, configurations: ModelConfiguration(url: url))
        let context = storage.mainContext
        let note = try context.fetch(FetchDescriptor<Note>()).first!
        try check(note.title == "Legacy" && note.pageCount == 3 && note.pageLayoutVersion == 0)
        let original = try NotebookEdits.drawing(note.drawingData)
        let oldDate = note.updatedAt
        try NotebookEdits.commit(in: context, notes: [note]) { try NotebookEdits.prepare(note) }
        try check(note.pageLayoutVersion == 1 && note.activePages.count == 3 && note.updatedAt == oldDate)
        let migrated = try NotebookEdits.drawing(note.drawingData)
        for index in 0..<3 {
            try check(migrated.strokes[index].path[0].location == original.strokes[index].path[0].location)
            try check(migrated.strokes[index].randomSeed == original.strokes[index].randomSeed)
            try check(abs(migrated.strokes[index].transform.ty - original.strokes[index].transform.ty
                             - CGFloat(index) * NotebookPaging.pageGap) < 0.001)
        }
        let migratedBytes = note.drawingData
        try NotebookEdits.commit(in: context, notes: [note]) { try NotebookEdits.prepare(note) }
        try check(note.drawingData == migratedBytes)
        let ids = note.activePages.map(\.id)
        try NotebookEdits.commit(in: context, notes: [note]) { try NotebookEdits.rename(ids[1], in: note, to: "Lecture") }
        try NotebookEdits.commit(in: context, notes: [note]) { try NotebookEdits.trash(ids[1], in: note, context: context) }
        try check(note.activePages.map(\.id) == [ids[0], ids[2]])
        var archives = try context.fetch(FetchDescriptor<TrashedPage>())
        try check(archives.count == 1 && archives[0].label == "Legacy (page 2)")
        let middle = archives[0]
        let afterDelete = try NotebookEdits.drawing(note.drawingData)
        try check(afterDelete.strokes.count == 2)
        try check(abs(afterDelete.strokes[1].transform.ty - migrated.strokes[2].transform.ty + NotebookPaging.pageStride) < 0.001)
        try NotebookEdits.commit(in: context, notes: [note]) { try NotebookEdits.trash(ids[0], in: note, context: context) }
        try NotebookEdits.commit(in: context, notes: [note]) { try NotebookEdits.appendMetadata(to: note, count: 2) }
        let appendedID = note.activePages.last!.id
        try NotebookEdits.commit(in: context, notes: [note]) { try NotebookEdits.restore(middle, context: context) }
        let first = try context.fetch(FetchDescriptor<TrashedPage>()).first { $0.id == ids[0] }!
        try NotebookEdits.commit(in: context, notes: [note]) { try NotebookEdits.restore(first, context: context) }
        try check(note.activePages.map(\.id) == ids + [appendedID])
        try check(note.activePages[1].title == "Lecture")
        try assertInkEqual(note.drawingData, migrated)

        // Failure after staging a destructive edit must roll back the entire operation.
        let safeBytes = note.drawingData
        let safeMetadata = note.pageMetadata
        do {
            try NotebookEdits.commit(in: context, notes: [note]) {
                try NotebookEdits.trash(ids[0], in: note, context: context)
                throw Injected.failure
            }
            preconditionFailure("Expected rollback")
        } catch Injected.failure { }
        try check(note.drawingData == safeBytes && note.pageMetadata == safeMetadata)
        try check(try context.fetch(FetchDescriptor<TrashedPage>()).isEmpty)

        // Delete every page, preserving a genuinely empty notebook, then restore in a different order.
        for id in ids + [appendedID] {
            try NotebookEdits.commit(in: context, notes: [note]) { try NotebookEdits.trash(id, in: note, context: context) }
        }
        try check(note.pageCount == 0 && (try NotebookEdits.drawing(note.drawingData)).strokes.isEmpty)
        for id in [ids[2], ids[0], appendedID, ids[1]] {
            let archive = try context.fetch(FetchDescriptor<TrashedPage>()).first { $0.id == id }!
            try NotebookEdits.commit(in: context, notes: [note]) { try NotebookEdits.restore(archive, context: context) }
        }
        try check(note.activePages.map(\.id) == ids + [appendedID])
        try assertInkEqual(note.drawingData, migrated)

        let unrelated = Note(title: "Active sentinel")
        unrelated.drawingData = Data([91, 92, 93]) // Empty Trash must not decode or touch this.
        let restoredAfterSnapshot = Note(title: "Restored after confirmation snapshot")
        restoredAfterSnapshot.deletedAt = .now
        let wholeTrash = Note(title: "Whole note in Trash")
        wholeTrash.deletedAt = .now
        context.insert(unrelated); context.insert(restoredAfterSnapshot); context.insert(wholeTrash)
        try context.save()
        let restoredID = restoredAfterSnapshot.id
        let wholeID = wholeTrash.id
        try NotebookEdits.commit(in: context, notes: [note]) { try NotebookEdits.trash(ids[1], in: note, context: context) }
        let activeBytes = note.drawingData
        let activePageIDs = note.activePages.map(\.id)
        let sentinelURL = url.deletingLastPathComponent().appendingPathComponent("unrelated-sentinel.txt")
        try Data("Keep this unrelated file".utf8).write(to: sentinelURL)
        restoredAfterSnapshot.deletedAt = nil
        try context.save()
        do {
            try NotebookEdits.commit(in: context, notes: [note]) {
                try NotebookEdits.emptyTrash(noteIDs: [wholeID], pageIDs: [ids[1]], context: context)
                throw Injected.failure
            }
            preconditionFailure("Expected permanent-deletion rollback")
        } catch Injected.failure { }
        try check(try context.fetch(FetchDescriptor<Note>()).contains { $0.id == wholeID })
        try check(try context.fetch(FetchDescriptor<TrashedPage>()).count == 1)
        try check(note.drawingData == activeBytes && note.activePages.map(\.id) == activePageIDs)
        try NotebookEdits.commit(in: context, notes: [note]) {
            // Deliberately include an active note ID: status recheck must protect it.
            try NotebookEdits.emptyTrash(noteIDs: [wholeID, restoredID, unrelated.id], pageIDs: [ids[1]], context: context)
        }
        let survivors = try context.fetch(FetchDescriptor<Note>())
        try check(!survivors.contains { $0.id == wholeID })
        try check(survivors.contains { $0.id == unrelated.id } && survivors.contains { $0.id == restoredID })
        try check(unrelated.drawingData == Data([91, 92, 93]))
        try check(note.drawingData == activeBytes && note.activePages.map(\.id) == activePageIDs)
        try check(try Data(contentsOf: sentinelURL) == Data("Keep this unrelated file".utf8))
        try check(try context.fetch(FetchDescriptor<TrashedPage>()).isEmpty)

        // A stale confirmation cannot remove a page restored after it was shown.
        try NotebookEdits.commit(in: context, notes: [note]) { try NotebookEdits.trash(ids[0], in: note, context: context) }
        let restoring = try context.fetch(FetchDescriptor<TrashedPage>()).first!
        try NotebookEdits.commit(in: context, notes: [note]) { try NotebookEdits.restore(restoring, context: context) }
        let restoredBytes = note.drawingData
        try NotebookEdits.commit(in: context, notes: [note]) { try NotebookEdits.emptyTrash(noteIDs: [], pageIDs: [ids[0]], context: context) }
        try check(note.drawingData == restoredBytes && note.activePages.contains { $0.id == ids[0] })

        // Failed decoding leaves both original and archived records intact.
        try NotebookEdits.commit(in: context, notes: [note]) { try NotebookEdits.trash(ids[0], in: note, context: context) }
        archives = try context.fetch(FetchDescriptor<TrashedPage>())
        let broken = archives.first!
        broken.drawingData = Data([0xFF, 0x01, 0x03])
        try context.save()
        let beforeCorruptRestore = note.drawingData
        do {
            try NotebookEdits.commit(in: context, notes: [note]) { try NotebookEdits.restore(broken, context: context) }
            preconditionFailure("Invalid drawing must not restore")
        } catch { }
        try check(note.drawingData == beforeCorruptRestore)
        try check(try context.fetch(FetchDescriptor<TrashedPage>()).count == 1)
        print("Notebook safety checks passed: real legacy migration, ink preservation, stable restore ordering, last-page deletion, rollback, scoped permanent deletion, stale confirmations, and corrupt archive protection.")
    }

    static func check(_ expression: @autoclosure () throws -> Bool, file: StaticString = #file, line: UInt = #line) throws {
        let passed = try expression()
        precondition(passed, "Safety invariant failed", file: file, line: line)
    }

    @MainActor static func assertInkEqual(_ data: Data, _ expected: PKDrawing) throws {
        let actual = try NotebookEdits.drawing(data)
        try check(actual.strokes.count == expected.strokes.count)
        for reference in expected.strokes {
            let stroke = actual.strokes.first { $0.randomSeed == reference.randomSeed }!
            try check(stroke.path.count == reference.path.count)
            try check(stroke.path[0].location == reference.path[0].location)
            try check(abs(stroke.path[0].force - reference.path[0].force) < 0.0001)
            try check(abs(stroke.transform.ty - reference.transform.ty) < 0.001)
            try check(stroke.transform.tx == reference.transform.tx)
        }
    }
}
