import Foundation
import PDFKit
import NaturalLanguage
import CryptoKit

/// PDF decoding, OCR, embeddings and disk access never run on the PencilKit input actor.
/// One actor serializes the non-thread-safe NLEmbedding instance.
actor LectureLibrary {
    static let shared = LectureLibrary()
    private let root: URL
    private var embedding: NLEmbedding?
    private var attemptedEmbedding = false
    private var cache: [UUID: [LectureDocument]] = [:]
    private var cacheRecency: [UUID] = []
    // Keep the two workspace panes hot without retaining every visited note's
    // text and embedding arrays for the entire app session. Eviction is RAM-only.
    private static let maxCachedNotes = 2
    static let maxBytes = 40 * 1024 * 1024
    static let maxPages = 150
    static let maxDocuments = 12

    init(root: URL = URL.applicationSupportDirectory.appendingPathComponent("BukoLectureLibrary", isDirectory: true)) {
        self.root = root
    }

    private func sentenceEmbedding() -> NLEmbedding? {
        if !attemptedEmbedding { embedding = NLEmbedding.sentenceEmbedding(for: .english); attemptedEmbedding = true }
        return embedding
    }

    private func sentenceVectors(_ text: String, embedding: NLEmbedding?) -> [[Double]]? {
        guard let embedding else { return nil }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).prefix(16)
            .compactMap { embedding.vector(for: String(text[$0])) }
    }

    private func directory(_ noteID: UUID) -> URL { root.appendingPathComponent(noteID.uuidString, isDirectory: true) }
    private func validID(_ id: String) -> Bool { id.count == 64 && id.allSatisfy { $0.isHexDigit && !$0.isUppercase } }

    private func cacheDocuments(_ documents: [LectureDocument], noteID: UUID) {
        cacheRecency.removeAll { $0 == noteID }
        cache[noteID] = documents.isEmpty ? nil : documents
        if !documents.isEmpty { cacheRecency.append(noteID) }
        while cacheRecency.count > Self.maxCachedNotes {
            cache[cacheRecency.removeFirst()] = nil
        }
    }

    func documents(noteID: UUID) throws -> [LectureDocument] {
        try Task.checkCancellation()
        if let cached = cache[noteID] {
            cacheDocuments(cached, noteID: noteID)
            return cached
        }
        let folder = directory(noteID)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        var documents: [LectureDocument] = []
        for file in files where validID(file.lastPathComponent) {
            try Task.checkCancellation()
            let data = try Data(contentsOf: file.appendingPathComponent("index.json"))
            var document = try JSONDecoder().decode(LectureDocument.self, from: data)
            guard document.indexVersion == 1, document.id == file.lastPathComponent,
                  (document.extractionVersion ?? 1) <= LecturePageExtractor.version,
                  document.passages.allSatisfy({ $0.documentID == document.id && $0.page > 0 && $0.page <= document.pageCount }),
                  FileManager.default.fileExists(atPath: file.appendingPathComponent("source.pdf").path) else {
                throw LibraryError.invalidIndex
            }
            if document.extractionVersion != LecturePageExtractor.version {
                // Repair derived data only. Keep the original bytes, identity, title
                // and import date; publish a complete replacement index atomically.
                let source = try Data(contentsOf: file.appendingPathComponent("source.pdf"), options: .mappedIfSafe)
                guard source.count <= Self.maxBytes,
                      SHA256.hash(data: source).map({ String(format: "%02x", $0) }).joined() == document.id,
                      let pdf = PDFDocument(data: source), !pdf.isLocked, pdf.pageCount == document.pageCount else {
                    throw LibraryError.invalidIndex
                }
                document = try index(pdf, id: document.id, title: document.title, importedAt: document.importedAt)
                let replacement = try JSONEncoder().encode(document)
                try Task.checkCancellation()
                try replacement.write(to: file.appendingPathComponent("index.json"), options: .atomic)
            }
            documents.append(document)
        }
        documents.sort { $0.importedAt < $1.importedAt }
        cacheDocuments(documents, noteID: noteID)
        return documents
    }

    func pdfURL(noteID: UUID, documentID: String) throws -> URL {
        guard validID(documentID), try documents(noteID: noteID).contains(where: { $0.id == documentID }) else {
            throw LibraryError.missingDocument
        }
        return directory(noteID).appendingPathComponent(documentID).appendingPathComponent("source.pdf")
    }

    func revision(noteID: UUID) throws -> String {
        try documents(noteID: noteID).map { "\($0.id):extraction-\($0.extractionVersion ?? 1)" }.sorted().joined(separator: ":")
    }

    func search(noteID: UUID, selected: String, intent: String, method: LectureRetrieval.Method = .hybrid,
                gap: ValidatedGapPlan? = nil) throws -> LectureSearch {
        let start = ProcessInfo.processInfo.systemUptime
        let documents = try documents(noteID: noteID)
        // A discarded page could contain a correction/conflict. Do not answer from
        // an apparently complete subset while any attached page is quarantined.
        if documents.contains(where: { !($0.textDisagreementPages ?? []).isEmpty }) {
            return LectureSearch(hits: [], documentCount: documents.count, revision: try revision(noteID: noteID),
                                 semanticAvailable: false, seconds: ProcessInfo.processInfo.systemUptime - start,
                                 hasUnverifiedText: true)
        }
        let embedding = sentenceEmbedding()
        let vector = embedding?.vector(for: String(selected.prefix(1000)))
        var passages = documents.flatMap(\.passages)
        // An OS embedding revision must never be compared with older cached vectors.
        for index in passages.indices {
            if let document = documents.first(where: { $0.id == passages[index].documentID }),
               document.embeddingRevision != embedding?.revision || passages[index].sentenceVectors == nil {
                passages[index].vector = embedding?.vector(for: passages[index].text)
                passages[index].sentenceVectors = sentenceVectors(passages[index].text, embedding: embedding)
            }
        }
        var trace: GapRetrievalTrace?
        let hits: [LectureHit]
        if let gap {
            let result = GapRetrieval.search(passages: passages, selected: selected, intent: intent,
                originalVector: vector, targetVector: embedding?.vector(for: String(gap.retrievalText.prefix(1000))),
                gap: gap, componentVectors: gap.componentQueries.map { embedding?.vector(for: String($0.prefix(1000))) },
                method: method)
            hits = result.hits; trace = result.trace
        } else {
            hits = LectureRetrieval.search(passages: passages, selected: selected, intent: intent, queryVector: vector, method: method)
        }
        try Task.checkCancellation()
        return LectureSearch(hits: hits, documentCount: documents.count, revision: try revision(noteID: noteID),
                             semanticAvailable: vector != nil, seconds: ProcessInfo.processInfo.systemUptime - start,
                             gapTrace: trace, gapPlan: gap)
    }

    /// Stages the PDF and complete index together, then atomically renames the directory.
    /// Cancellation or failed extraction leaves both the notebook and prior library intact.
    @discardableResult
    func importPDF(from url: URL, noteID: UUID) throws -> LectureDocument {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= Self.maxBytes else { throw LibraryError.fileSize }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= Self.maxBytes else { throw LibraryError.fileSize }
        try Task.checkCancellation()
        let id = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        var documents = try documents(noteID: noteID)
        if let duplicate = documents.first(where: { $0.id == id }) { return duplicate }
        guard documents.count < Self.maxDocuments else { throw LibraryError.tooManyDocuments }
        guard let pdf = PDFDocument(data: data), !pdf.isLocked else { throw LibraryError.unreadablePDF }
        guard (1...Self.maxPages).contains(pdf.pageCount) else { throw LibraryError.pageLimit }
        let metadataTitle = (pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = String((metadataTitle?.isEmpty == false ? metadataTitle! : url.deletingPathExtension().lastPathComponent).prefix(150))
        let document = try index(pdf, id: id, title: title, importedAt: .now)
        let folder = directory(noteID)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let staging = folder.appendingPathComponent(".import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: staging) }
        try data.write(to: staging.appendingPathComponent("source.pdf"), options: .atomic)
        try JSONEncoder().encode(document).write(to: staging.appendingPathComponent("index.json"), options: .atomic)
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: staging, to: folder.appendingPathComponent(id, isDirectory: true))
        documents.append(document); cacheDocuments(documents, noteID: noteID)
        return document
    }

    private func index(_ pdf: PDFDocument, id: String, title: String, importedAt: Date) throws -> LectureDocument {
        guard (1...Self.maxPages).contains(pdf.pageCount) else { throw LibraryError.pageLimit }
        let embedding = sentenceEmbedding()
        var passages: [LecturePassage] = [], skipped: [Int] = [], disagreements: [Int] = []
        for number in 0..<pdf.pageCount {
            try Task.checkCancellation()
            guard let page = pdf.page(at: number) else { skipped.append(number + 1); continue }
            let extracted = try autoreleasepool { try LecturePageExtractor.extract(page) }
            if extracted.hasTextDisagreement { disagreements.append(number + 1); continue }
            guard !extracted.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { skipped.append(number + 1); continue }
            // Bound pathological PDFs as well as ordinary lecture decks.
            guard extracted.text.count <= 80_000 else { throw LibraryError.pageTextLimit }
            for (index, text) in LectureRetrieval.chunks(extracted.text).enumerated() {
                try Task.checkCancellation()
                passages.append(LecturePassage(id: "\(id):\(number + 1):\(index)", documentID: id,
                                               title: title, page: number + 1, text: text,
                                               usedOCR: extracted.usedOCR, vector: embedding?.vector(for: text),
                                               sentenceVectors: sentenceVectors(text, embedding: embedding)))
            }
            guard passages.count <= 2400 else { throw LibraryError.pageTextLimit }
        }
        guard !passages.isEmpty || !disagreements.isEmpty else { throw LibraryError.noText }
        return LectureDocument(id: id, title: title, pageCount: pdf.pageCount, importedAt: importedAt,
                               skippedPages: skipped, embeddingRevision: embedding?.revision, passages: passages,
                               extractionVersion: LecturePageExtractor.version, textDisagreementPages: disagreements)
    }

    func remove(documentID: String, noteID: UUID) throws {
        guard validID(documentID) else { throw LibraryError.missingDocument }
        var documents = try documents(noteID: noteID)
        guard documents.contains(where: { $0.id == documentID }) else { return }
        try FileManager.default.removeItem(at: directory(noteID).appendingPathComponent(documentID))
        documents.removeAll { $0.id == documentID }; cacheDocuments(documents, noteID: noteID)
    }

    /// Discover existing app-owned directories before asking the store which
    /// owners still exist. Never enumerate or delete picker-provided originals.
    func storedNoteIDs() throws -> Set<UUID> {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return Set(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]).compactMap { url in
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true,
                  let id = UUID(uuidString: url.lastPathComponent), id.uuidString == url.lastPathComponent else { return nil }
            return id
        })
    }

    /// Call only for IDs confirmed absent from the saved note/page store.
    /// Idempotent and independent of index decoding, so corrupt orphan indexes
    /// can be removed too. A failed delete leaves the directory for a later retry.
    func removeNotes(_ ids: Set<UUID>) throws {
        for id in ids {
            let url = directory(id)
            if FileManager.default.fileExists(atPath: url.path) {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else { throw LibraryError.invalidIndex }
                try FileManager.default.removeItem(at: url)
            }
            cacheDocuments([], noteID: id)
        }
    }

    enum LibraryError: LocalizedError {
        case fileSize, tooManyDocuments, unreadablePDF, pageLimit, noText, pageTextLimit, invalidIndex, missingDocument
        var errorDescription: String? {
            switch self {
            case .fileSize: "Choose a PDF smaller than 40 MB."
            case .tooManyDocuments: "This notebook already has 12 PDFs. Remove one before adding another."
            case .unreadablePDF: "This PDF is damaged or password-protected. Export an unlocked copy and try again."
            case .pageLimit: "Choose a PDF with 1–150 pages. Split larger lecture packs first."
            case .noText: "No readable text was found, including after on-device OCR."
            case .pageTextLimit: "This PDF contains too much text to index. Split it into smaller lectures."
            case .invalidIndex: "A lecture index could not be read. Original PDF copies and handwritten notes are unchanged."
            case .missingDocument: "This lecture PDF is no longer attached to this notebook."
            }
        }
    }
}
