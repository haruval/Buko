import Foundation
import CoreGraphics
import SwiftData
import PencilKit

@main
struct LibraryOrganizationChecks {
    @MainActor static func main() throws {
        if CommandLine.arguments.count > 2 {
            let url = URL(fileURLWithPath: CommandLine.arguments[2])
            let schema = Schema([Note.self, TrashedPage.self, NoteFolder.self])
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let context = container.mainContext
            let legacy = try context.fetch(FetchDescriptor<Note>()).first!
            precondition(legacy.title == "Legacy" && legacy.pageCount == 3 && legacy.folderID == nil)
            let drawing = try PKDrawing(data: legacy.drawingData)
            precondition(drawing.strokes.count == 3)
            try NotebookEdits.commit(in: context, notes: [legacy]) { try NotebookEdits.prepare(legacy) }
            precondition(legacy.activePages.count == 3)
            print("PASS: real on-disk legacy migration with current schema; existing ink and pages retained")
        }
        try retiredStore()
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let schema = Schema([Note.self, TrashedPage.self, NoteFolder.self])
        let configuration = ModelConfiguration(schema: schema, url: root.appendingPathComponent("library.store"))
        let aID: UUID, bID: UUID
        do {
            let container = try ModelContainer(for: schema, configurations: configuration)
            let context = ModelContext(container); context.autosaveEnabled = false
            let a = Note(title: "Algorithms"), b = Note(title: "Networks"), c = Note(title: "Review")
            a.drawingData = Data([1, 2, 3]); b.drawingData = Data([4, 5]); aID = a.id; bID = b.id
            [a, b, c].forEach { context.insert($0) }; try context.save()
            try LibraryOrganization.group(a, with: b, in: context)
            let folder = try context.fetch(FetchDescriptor<NoteFolder>()).first!
            precondition(a.folderID == folder.id && b.folderID == folder.id)
            try LibraryOrganization.group(a, with: a, in: context)
            let folderCount = try context.fetchCount(FetchDescriptor<NoteFolder>())
            precondition(folderCount == 1)
            try LibraryOrganization.move(c, to: folder, in: context)
            try LibraryOrganization.rename(folder, to: "  Semester  ", in: context)
            precondition(folder.title == "Semester")
            b.deletedAt = .now; try context.save()
            try LibraryOrganization.ungroup(folder, in: context)
            precondition([a, b, c].allSatisfy { $0.folderID == nil })
            precondition(a.drawingData == Data([1, 2, 3]) && b.drawingData == Data([4, 5]))
            precondition(b.deletedAt != nil)
            enum Expected: Error { case stop }
            do {
                try NotebookEdits.commit(in: context, notes: [a]) {
                    a.folderID = UUID(); throw Expected.stop
                }
            } catch Expected.stop { }
            precondition(a.folderID == nil && a.drawingData == Data([1, 2, 3]))
            try LibraryOrganization.group(c, with: a, in: context)
        }
        do {
            let container = try ModelContainer(for: schema, configurations: configuration)
            let context = ModelContext(container)
            let notes = try context.fetch(FetchDescriptor<Note>())
            precondition(notes.first { $0.id == aID }!.folderID != nil)
            precondition(notes.first { $0.id == bID }!.deletedAt != nil)
            precondition(notes.first { $0.id == aID }!.drawingData == Data([1, 2, 3]))
            precondition(notes.first { $0.id == bID }!.drawingData == Data([4, 5]))
        }
        print("PASS: folders create/move/rename/ungroup, rollback, ink preservation, and membership persistence")
    }

    @MainActor static func retiredStore() throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[3])
        let schema = Schema([Note.self, TrashedPage.self, NoteFolder.self])
        for _ in 0..<2 {
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let context = container.mainContext
            let note = try context.fetch(FetchDescriptor<Note>()).first!
            let folder = try context.fetch(FetchDescriptor<NoteFolder>()).first!
            precondition(note.title == "Existing lecture" && note.folderID == folder.id && folder.title == "Existing semester")
            precondition(note.drawingData == Data([9, 8, 7, 6]) && note.autofillHistory == Data([3, 2, 1]))
            precondition(note.activePages.count == 2)
            note.updatedAt = .now
            try context.save()
        }
        print("PASS: pre-removal store opens/saves/reopens with notes, folders, pages, ink and attribution intact")
    }
}
