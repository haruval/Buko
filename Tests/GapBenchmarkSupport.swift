import Foundation

/// Gold annotations stay in the test target. None are passed to a planner,
/// retriever or selector. PDF paths are relative to the manifest directory.
struct GapBenchmarkFixture: Codable {
    struct Source: Codable {
        let id: String
        let title: String
        let textPages: [String]?
        let pdfPath: String?
    }
    struct Span: Codable {
        let source: String
        let page: Int
        let quote: String
    }
    struct Case: Codable {
        let id: String
        let selected: String
        let context: String
        let expectedBehavior: String // answer, abstain, clarify
        let expectedTargetQuotes: [String]
        let sufficientEvidenceSets: [[Span]]
        let tags: [String]
    }
    let schemaVersion: Int
    let split: String
    let provenance: String
    let frozenAt: String?
    let sources: [Source]
    let cases: [Case]

    func validate() throws {
        func require(_ value: Bool, _ message: String) throws {
            if !value { throw BenchmarkError.invalidFixture(message) }
        }
        try require(schemaVersion == 1 && ["development", "heldOut"].contains(split), "Unsupported schema or split")
        try require(!provenance.isEmpty, "Describe annotation and handwriting provenance")
        if split == "heldOut" {
            try require(frozenAt.flatMap { ISO8601DateFormatter().date(from: $0) } != nil, "Held-out data needs an ISO-8601 frozenAt date")
        }
        try require(!sources.isEmpty && sources.count <= LectureLibrary.maxDocuments, "Provide 1–12 sources")
        try require(!cases.isEmpty, "No benchmark cases: collect and annotate cases before running")
        try require(Set(sources.map(\.id)).count == sources.count && Set(cases.map(\.id)).count == cases.count,
                    "Source and case IDs must be unique")
        for source in sources {
            try require(!source.id.isEmpty && !source.title.isEmpty, "Empty source metadata")
            try require((source.textPages != nil) != (source.pdfPath != nil), "Supply either textPages or pdfPath")
            if let pages = source.textPages {
                try require(!pages.isEmpty && pages.count <= 150 && pages.allSatisfy { !$0.isEmpty && $0.count <= 3000 },
                            "Synthetic pages must contain 1–3000 characters; use pdfPath for real lectures")
            }
        }
        for item in cases {
            try require(!item.id.isEmpty && !item.selected.isEmpty, "Empty case ID or selection")
            try require(["answer", "abstain", "clarify"].contains(item.expectedBehavior), "Unknown expectedBehavior")
            try require(item.selected.count <= IntentPrompts.selectedCharacterLimit
                        && item.context.count <= IntentPrompts.contextCharacterLimit,
                        "Benchmark annotations must describe the text actually supplied after the planner caps")
            try require(item.expectedTargetQuotes.allSatisfy { !$0.isEmpty && item.selected.contains($0) },
                        "Expected targets must quote selected text")
            try require(item.expectedBehavior != "answer" || !item.sufficientEvidenceSets.isEmpty,
                        "An answer needs a minimal sufficient evidence set")
            for set in item.sufficientEvidenceSets {
                try require(!set.isEmpty, "Empty evidence set would trivially pass")
                for span in set {
                    try require(sources.contains { $0.id == span.source } && span.page > 0 && !span.quote.isEmpty,
                                "Invalid evidence source/page/quote")
                }
            }
        }
    }
}

enum BenchmarkError: LocalizedError {
    case invalidFixture(String), timeout
    var errorDescription: String? {
        switch self {
        case .invalidFixture(let message): message
        case .timeout: "Request exceeded the 90-second benchmark watchdog"
        }
    }
}

enum GapBenchmarkMetrics {
    static func covers(_ spans: [GapBenchmarkFixture.Span], hits: [LectureHit], documentIDs: [String: String]) -> Bool {
        spans.allSatisfy { span in hits.contains { hit in
            hit.passage.documentID == documentIDs[span.source] && hit.passage.page == span.page
                && CitationValidation.normalized(hit.passage.text).contains(CitationValidation.normalized(span.quote))
        } }
    }

    static func complete(_ item: GapBenchmarkFixture.Case, hits: [LectureHit], documentIDs: [String: String]) -> Bool {
        item.sufficientEvidenceSets.contains { covers($0, hits: hits, documentIDs: documentIDs) }
    }

    static func recall(_ item: GapBenchmarkFixture.Case, hits: [LectureHit], documentIDs: [String: String]) -> Double? {
        item.sufficientEvidenceSets.map { set in
            Double(set.filter { covers([$0], hits: hits, documentIDs: documentIDs) }.count) / Double(set.count)
        }.max()
    }
}
