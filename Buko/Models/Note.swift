import Foundation
import SwiftData

@Model
final class Note {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date? = nil
    @Attribute(.externalStorage) var drawingData: Data

    init(title: String = "Untitled") {
        id = UUID()
        self.title = title
        createdAt = .now
        updatedAt = .now
        drawingData = Data()
    }
}
