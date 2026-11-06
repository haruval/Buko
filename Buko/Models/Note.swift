import Foundation
import SwiftData

@Model
final class Note {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date? = nil
    var folderID: UUID? = nil
    var pageCount: Int = 1
    var currentPageIndex: Int = 0
    var pageLayoutVersion: Int = 0
    var pageMetadata: Data = Data()
    @Attribute(.externalStorage) var drawingData: Data
    // Historical field name retained for store compatibility. Contains only generated stroke IDs.
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

/// Only these IDs are needed to exclude generated ink from handwriting sampling.
/// Decoding old records deliberately ignores their text, quotations and metadata.
nonisolated struct AutofillRecord: Codable {
    let strokeIDs: [UUID]

    static func minimized(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return data }
        return try JSONEncoder().encode(JSONDecoder().decode([Self].self, from: data))
    }
}
