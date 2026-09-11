import Foundation
import SwiftData

@main
struct NoteStorageChecks {
    @MainActor static func main() throws {
        precondition(Note.uniqueTitle("Untitled", occupied: []) == "Untitled")
        precondition(Note.uniqueTitle("Untitled", occupied: ["Untitled"]) == "Untitled (1)")
        precondition(Note.uniqueTitle("Untitled", occupied: ["Untitled", "Untitled (1)"]) == "Untitled (2)")
        precondition(Note.uniqueTitle("Lecture", occupied: ["Lecture", "Lecture (2)"]) == "Lecture (1)")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BukoStorageCheck-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.store")
        let expectedDrawing = Data([1, 2, 3, 4])
        let noteID = try createNotes(at: url, drawing: expectedDrawing)
        try trashNote(at: url, id: noteID)
        try restoreNote(at: url, id: noteID, drawing: expectedDrawing)
        try verifyRestored(at: url, id: noteID, drawing: expectedDrawing)
        print("Note storage checks passed: soft deletion, active/trash filtering, reopen, restore, and drawing preservation.")
    }

    @MainActor static func container(at url: URL) throws -> ModelContainer {
        try ModelContainer(for: Note.self, configurations: ModelConfiguration(url: url))
    }

    @MainActor static func createNotes(at url: URL, drawing: Data) throws -> UUID {
        let storage = try container(at: url)
        let note = Note(title: "Preserve this drawing")
        precondition(note.pageCount == 1 && note.currentPageIndex == 0)
        note.pageCount = 3
        note.currentPageIndex = 2
        note.drawingData = drawing
        storage.mainContext.insert(note)
        storage.mainContext.insert(Note(title: "Other note"))
        try storage.mainContext.save()
        return note.id
    }

    @MainActor static func trashNote(at url: URL, id: UUID) throws {
        let storage = try container(at: url)
        let notes = try storage.mainContext.fetch(FetchDescriptor<Note>())
        precondition(notes.count == 2)
        let note = notes.first { $0.id == id }!
        note.deletedAt = .now
        try storage.mainContext.save()
        let active = try storage.mainContext.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.deletedAt == nil }))
        precondition(active.count == 1 && active[0].id != id)
    }

    @MainActor static func restoreNote(at url: URL, id: UUID, drawing: Data) throws {
        let storage = try container(at: url)
        let trash = try storage.mainContext.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.deletedAt != nil }))
        precondition(trash.count == 1 && trash[0].id == id)
        precondition(trash[0].drawingData == drawing)
        precondition(trash[0].pageCount == 3 && trash[0].currentPageIndex == 2)
        trash[0].deletedAt = nil
        try storage.mainContext.save()
    }

    @MainActor static func verifyRestored(at url: URL, id: UUID, drawing: Data) throws {
        let storage = try container(at: url)
        let active = try storage.mainContext.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.deletedAt == nil }))
        precondition(active.count == 2)
        precondition(active.first { $0.id == id }?.drawingData == drawing)
        precondition(active.first { $0.id == id }?.pageCount == 3)
        precondition(active.first { $0.id == id }?.currentPageIndex == 2)
        let trash = try storage.mainContext.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.deletedAt != nil }))
        precondition(trash.isEmpty)
    }
}
