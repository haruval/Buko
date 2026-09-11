import Foundation
import SwiftData

@Model
final class Note {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date? = nil
    var pageCount: Int = 1
    var currentPageIndex: Int = 0
    @Attribute(.externalStorage) var drawingData: Data

    static func uniqueTitle(_ requested: String, occupied: Set<String>) -> String {
        guard occupied.contains(requested) else { return requested }
        var number = 1
        while occupied.contains("\(requested) (\(number))") { number += 1 }
        return "\(requested) (\(number))"
    }

    init(title: String = "Untitled") {
        id = UUID()
        self.title = title
        createdAt = .now
        updatedAt = .now
        drawingData = Data()
    }
}
