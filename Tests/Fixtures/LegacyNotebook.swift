import Foundation
import PencilKit
import SwiftData

// Frozen pre-page-library schema for an actual on-disk lightweight migration check.
@Model final class Note {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date? = nil
    var pageCount: Int = 1
    var currentPageIndex: Int = 0
    @Attribute(.externalStorage) var drawingData: Data
    init() {
        id = UUID(); title = "Legacy"; createdAt = .now; updatedAt = .now; drawingData = Data()
    }
}

@main struct LegacyNotebookFixture {
    @MainActor static func main() throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let storage = try ModelContainer(for: Note.self, configurations: ModelConfiguration(url: url))
        let note = Note()
        note.pageCount = 3
        let strokes = (0..<3).map { index in
            let points = [
                PKStrokePoint(location: CGPoint(x: 1100, y: 100 + CGFloat(index) * 4000 / 3), timeOffset: 0,
                              size: CGSize(width: 3, height: 3), opacity: 1, force: 0.7, azimuth: 0.4, altitude: 1),
                PKStrokePoint(location: CGPoint(x: 1250, y: 260 + CGFloat(index) * 4000 / 3), timeOffset: 0.2,
                              size: CGSize(width: 4, height: 4), opacity: 0.9, force: 0.8, azimuth: 0.5, altitude: 1)
            ]
            return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: .distantPast),
                            transform: CGAffineTransform(translationX: 5, y: 7), randomSeed: UInt32(index + 10))
        }
        note.drawingData = PKDrawing(strokes: strokes).dataRepresentation()
        storage.mainContext.insert(note)
        try storage.mainContext.save()
    }
}
