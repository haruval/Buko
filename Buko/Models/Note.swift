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
    var pageLayoutVersion: Int = 0
    var pageMetadata: Data = Data()
    @Attribute(.externalStorage) var drawingData: Data
    @Attribute(.externalStorage) var autofillHistory: Data? = nil

    var activePages: [NotebookPage] { (try? pages().filter { !$0.isTrashed }) ?? [] }

    func pages() throws -> [NotebookPage] {
        guard !pageMetadata.isEmpty else { return [] }
        return try JSONDecoder().decode([NotebookPage].self, from: pageMetadata)
    }

    func setPages(_ pages: [NotebookPage]) throws {
        pageMetadata = try JSONEncoder().encode(pages)
        pageCount = pages.filter { !$0.isTrashed }.count
    }

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
