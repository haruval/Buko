// Frozen pre-removal schema. Compile separately from the production compatibility record.
import Foundation
import CoreGraphics
import SwiftData

@Model
final class BulletinItem {
    var id: UUID
    var title: String
    var kind: String
    var dueDate: Date?
    var dateHasTime: Bool
    var completedAt: Date?
    var capturedAt: Date
    var timeZoneID: String
    var noteID: UUID
    var noteTitle: String
    var pageID: UUID
    var pageIndex: Int
    var sourceText: String
    var sourceX: Double
    var sourceY: Double
    var sourceWidth: Double
    var sourceHeight: Double
    var sourceStrokeIDs: Data
    var captureID: UUID

    init(draft: BulletinDraft, source: BulletinSource) {
        id = UUID(); title = draft.title; kind = draft.kind.rawValue
        dueDate = draft.date; dateHasTime = draft.dateHasTime; completedAt = nil
        capturedAt = source.capturedAt; timeZoneID = source.timeZoneID
        noteID = source.noteID; noteTitle = source.noteTitle; pageID = source.pageID; pageIndex = source.pageIndex
        sourceText = draft.quote
        sourceX = source.bounds.minX; sourceY = source.bounds.minY
        sourceWidth = source.bounds.width; sourceHeight = source.bounds.height
        sourceStrokeIDs = (try? JSONEncoder().encode(source.strokeIDs)) ?? Data()
        captureID = source.id
    }
}

nonisolated enum BulletinKind: String, Codable, CaseIterable, Sendable {
    case action, event, information
    var label: String { switch self { case .action: "Action"; case .event: "Event"; case .information: "Information" } }
    var symbol: String { switch self { case .action: "checkmark.circle"; case .event: "calendar"; case .information: "pin" } }
}

nonisolated struct BulletinDraft: Identifiable, Sendable {
    var id = UUID()
    var title: String
    var kind: BulletinKind
    var quote: String
    var date: Date?
    var dateHasTime: Bool
}

nonisolated struct BulletinSource: Identifiable, Sendable {
    var id = UUID()
    var noteID: UUID
    var noteTitle: String
    var pageID: UUID
    var pageIndex: Int
    /// Page-relative document coordinates; stable across page reordering.
    var bounds: CGRect
    var strokeIDs: [String]
    var capturedAt: Date
    var timeZoneID: String
}


@main struct RetiredBulletinStoreFixture {
    @MainActor static func main() throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let schema = Schema([Note.self, TrashedPage.self, NoteFolder.self, BulletinItem.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        let context = container.mainContext
        let folder = NoteFolder(title: "Existing semester")
        let note = Note(title: "Existing lecture")
        note.folderID = folder.id
        // Byte-for-byte sentinels also catch accidental decode/rewrite during store opening.
        note.drawingData = Data([9, 8, 7, 6]); note.autofillHistory = Data([3, 2, 1])
        try note.setPages([NotebookPage(), NotebookPage()])
        let source = BulletinSource(noteID: note.id, noteTitle: note.title, pageID: note.activePages[1].id,
            pageIndex: 1, bounds: CGRect(x: 50, y: 80, width: 500, height: 100), strokeIDs: ["original-stroke"],
            capturedAt: Date(timeIntervalSince1970: 1792798200), timeZoneID: "America/Denver")
        let item = BulletinItem(draft: BulletinDraft(title: "Previously saved exam", kind: .event,
            quote: "Exam in 12 days", date: Date(timeIntervalSince1970: 1793833200), dateHasTime: false), source: source)
        item.completedAt = Date(timeIntervalSince1970: 1792884600)
        context.insert(folder); context.insert(note); context.insert(item)
        try context.save()
    }
}
