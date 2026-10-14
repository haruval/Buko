import Foundation

/// Stable provenance stays with each page-bounded passage, never with a model-invented filename.
nonisolated struct LecturePassage: Codable, Sendable, Identifiable {
    var id: String
    var documentID: String
    var title: String
    var page: Int
    var text: String
    var usedOCR: Bool
    var vector: [Double]?
    var sentenceVectors: [[Double]]? = nil
}

nonisolated struct LectureDocument: Codable, Sendable, Identifiable {
    var id: String // SHA-256 of the original PDF
    var title: String
    var pageCount: Int
    var importedAt: Date
    var skippedPages: [Int]
    var embeddingRevision: Int?
    var passages: [LecturePassage]
    var indexVersion = 1
}

nonisolated struct LectureHit: Sendable, Identifiable {
    var passage: LecturePassage
    var lexicalScore: Double
    var semanticScore: Double
    var score: Double
    var id: String { passage.id }
}

nonisolated struct LectureSearch: Sendable {
    var hits: [LectureHit]
    var documentCount: Int
    var revision: String
    var semanticAvailable: Bool
    var seconds: Double
}

nonisolated enum LectureRetrieval {
    enum Method { case lexical, semantic, hybrid }
    // These are retrieval heuristics, not calibrated probabilities of correctness.
    static let minimumSemanticSimilarity = 0.45
    static let maxEvidenceCharacters = 4800
    static let stopWords = Set("a an the and or of to in on for is are was be by as at it its this that with from what why how does do can should user wants fill complete define definition explain add beneath concise bullet bullets notes note topic action missing selected handwriting".split(separator: " ").map(String.init))

    static func tokens(_ text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !stopWords.contains($0) }
            .map(stem)
    }

    /// Conservative English suffix normalization keeps inflected lecture terms searchable
    /// even when Apple's sentence embedding assets are unavailable.
    private static func stem(_ word: String) -> String {
        if word.count > 6 && word.hasSuffix("ing") { return String(word.dropLast(3)) }
        if word.count > 5 && word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if word.count > 5 && word.hasSuffix("ed") { return String(word.dropLast(2)) }
        if word.count > 4 && word.hasSuffix("s") && !word.hasSuffix("ss") && !word.hasSuffix("us") && !word.hasSuffix("is") {
            return String(word.dropLast())
        }
        return word
    }

    /// Windows stay within one physical PDF page; overlap protects sentence boundaries.
    static func chunks(_ text: String, limit: Int = 140, overlap: Int = 28) -> [String] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        let size = max(1, limit), stride = max(1, size - max(0, overlap))
        var result: [String] = []
        var start = 0
        while start < words.count {
            let end = min(words.count, start + size)
            result.append(words[start..<end].joined(separator: " "))
            if end == words.count { break }
            start += stride
        }
        return result
    }

    static func cosine(_ a: [Double]?, _ b: [Double]?) -> Double {
        guard let a, let b, !a.isEmpty, a.count == b.count else { return 0 }
        var dot = 0.0, aa = 0.0, bb = 0.0
        for (x, y) in zip(a, b) { dot += x * y; aa += x * x; bb += y * y }
        guard aa > 0, bb > 0 else { return 0 }
        let value = dot / sqrt(aa * bb)
        return value.isFinite ? value : 0
    }

    /// BM25 + reciprocal-rank fusion. Selection has priority over model query expansion.
    /// Nearby handwritten context is deliberately excluded from the retrieval query:
    /// it is already written and can otherwise displace the circled target.
    static func search(passages: [LecturePassage], selected: String, intent: String,
                       queryVector: [Double]?, method: Method = .hybrid, limit: Int = 4) -> [LectureHit] {
        guard !passages.isEmpty else { return [] }
        let primary = Set(tokens(selected)), expanded = Set(tokens(intent)).subtracting(primary)
        guard !primary.isEmpty else { return [] }
        let terms = primary.union(expanded)
        let documents = passages.map { tokens($0.text) }
        let average = max(1, Double(documents.reduce(0) { $0 + $1.count }) / Double(documents.count))
        var frequencies: [String: Int] = [:]
        for document in documents { for term in Set(document).intersection(terms) { frequencies[term, default: 0] += 1 } }
        var hits: [LectureHit] = []
        for (index, passage) in passages.enumerated() {
            let counts = Dictionary(documents[index].map { ($0, 1) }, uniquingKeysWith: +)
            var bm25 = 0.0
            for term in terms {
                let frequency = Double(counts[term, default: 0])
                guard frequency > 0 else { continue }
                let df = Double(frequencies[term, default: 0]), n = Double(passages.count)
                let idf = log(1 + (n - df + 0.5) / (df + 0.5))
                let normalized = frequency * 2.2 / (frequency + 1.2 * (0.25 + 0.75 * Double(documents[index].count) / average))
                bm25 += idf * normalized * (primary.contains(term) ? 2 : 0.5)
            }
            let semantic = (passage.sentenceVectors ?? []).map { cosine(queryVector, $0) }.max() ?? cosine(queryVector, passage.vector)
            let overlap = primary.intersection(counts.keys).count
            // Never route solely on generic expansion terms invented by the planner.
            let lexicalEligible = overlap >= min(2, primary.count)
            // Very short headings need a lexical anchor: their sentence vectors are
            // otherwise easily confused with unrelated senses (e.g. "static scope").
            let semanticEligible = queryVector != nil && semantic >= minimumSemanticSimilarity
                && (method == .semantic || primary.count >= 3 || lexicalEligible)
            let eligible: Bool
            switch method {
            case .lexical: eligible = lexicalEligible
            case .semantic: eligible = semanticEligible
            case .hybrid: eligible = lexicalEligible || semanticEligible
            }
            if eligible { hits.append(LectureHit(passage: passage, lexicalScore: bm25, semanticScore: semantic, score: 0)) }
        }
        let lexical = hits.sorted { $0.lexicalScore == $1.lexicalScore ? $0.id < $1.id : $0.lexicalScore > $1.lexicalScore }
        let semantic = hits.sorted { $0.semanticScore == $1.semanticScore ? $0.id < $1.id : $0.semanticScore > $1.semanticScore }
        let lexicalRanks = Dictionary(uniqueKeysWithValues: lexical.enumerated().map { ($0.element.id, $0.offset + 1) })
        let semanticRanks = Dictionary(uniqueKeysWithValues: semantic.enumerated().map { ($0.element.id, $0.offset + 1) })
        for index in hits.indices {
            let hit = hits[index]
            let l = hit.lexicalScore > 0 ? 1 / Double(60 + lexicalRanks[hit.id]!) : 0
            let s = queryVector != nil && hit.semanticScore > 0 ? 1 / Double(60 + semanticRanks[hit.id]!) : 0
            switch method {
            case .lexical: hits[index].score = l
            case .semantic: hits[index].score = s
            case .hybrid: hits[index].score = l + s
            }
        }
        let ranked = hits.sorted { $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score }
        var result: [LectureHit] = [], budget = maxEvidenceCharacters
        for hit in ranked {
            // Avoid flooding the context with near-identical overlapping windows.
            let words = Set(tokens(hit.passage.text))
            let duplicate = result.contains {
                let previous = Set(tokens($0.passage.text))
                return $0.passage.documentID == hit.passage.documentID && $0.passage.page == hit.passage.page
                    && Double(words.intersection(previous).count) / Double(max(1, words.union(previous).count)) > 0.72
            }
            guard !duplicate, hit.passage.text.count <= budget else { continue }
            result.append(hit); budget -= hit.passage.text.count
            if result.count >= max(1, limit) { break }
        }
        return result
    }
}

nonisolated struct LectureCitation: Identifiable, Sendable {
    var passage: LecturePassage
    var quote: String
    var id: String { passage.id + quote }
}

nonisolated enum CitationValidation {
    static func normalized(_ value: String) -> String { value.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
    /// Validates provenance, not semantic entailment. Never accepts a fabricated source ID or quote.
    static func citation(sourceID: String, quote: String, hits: [LectureHit]) -> LectureCitation? {
        let quote = normalized(quote)
        guard quote.count >= 20, let source = hits.first(where: { $0.id == sourceID }),
              normalized(source.passage.text).contains(quote) else { return nil }
        return LectureCitation(passage: source.passage, quote: quote)
    }
}
