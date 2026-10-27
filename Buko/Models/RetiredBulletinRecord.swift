import Foundation
import SwiftData

/// Retired Bulletin entity, retained solely to open existing SwiftData stores
/// without deleting their saved records. No app UI, queries or writers use it.
/// Keep the entity name, attributes and optionality unchanged.
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

    private init() {
        id = UUID(); title = ""; kind = ""
        dueDate = nil; dateHasTime = false; completedAt = nil
        capturedAt = .distantPast; timeZoneID = ""
        noteID = UUID(); noteTitle = ""; pageID = UUID(); pageIndex = 0
        sourceText = ""; sourceX = 0; sourceY = 0; sourceWidth = 0; sourceHeight = 0
        sourceStrokeIDs = Data(); captureID = UUID()
    }
}
