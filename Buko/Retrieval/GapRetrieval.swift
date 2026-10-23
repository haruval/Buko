import Foundation

nonisolated struct GapRetrievalTrace: Codable, Sendable {
    struct Candidate: Codable, Sendable {
        let id: String
        let originalRank: Int?
        let targetRank: Int?
        let componentRanks: [Int?]
        let fusedScore: Double
        let retained: Bool
        let selectionReason: String?
        let exclusion: String?
    }
    let targetQuery: String
    let informationNeeds: String
    let targetSemanticAvailable: Bool
    let componentQueries: [String]
    let componentSemanticAvailable: [Bool]
    let candidates: [Candidate]
}

/// Each branch retains baseline eligibility/ranking. Comparison components add
/// at most three branches (20 candidates total). Final context remains bounded
/// to four hits / 4,800 characters. Branch coverage is not semantic completeness.
nonisolated enum GapRetrieval {
    static let version = 4
    static let targetWeight = 2.0
    static let originalWeight = 1.0
    static let componentWeight = 2.0

    static func search(passages: [LecturePassage], selected: String, intent: String,
                       originalVector: [Double]?, targetVector: [Double]?, gap: ValidatedGapPlan,
                       componentVectors: [[Double]?] = [],
                       method: LectureRetrieval.Method = .hybrid) -> (hits: [LectureHit], trace: GapRetrievalTrace) {
        let original = LectureRetrieval.search(passages: passages, selected: selected, intent: intent,
                                               queryVector: originalVector, method: method)
        let targeted = LectureRetrieval.search(passages: passages, selected: gap.retrievalText, intent: gap.expansion,
                                               queryVector: targetVector, method: method)
        let queries = gap.componentQueries
        let vectors = queries.indices.map { componentVectors.indices.contains($0) ? componentVectors[$0] : nil }
        let components = queries.enumerated().map { index, query in
            LectureRetrieval.search(passages: passages, selected: query, intent: gap.expansion,
                                    queryVector: vectors[index], method: method)
        }
        func ranks(_ hits: [LectureHit]) -> [String: Int] {
            Dictionary(uniqueKeysWithValues: hits.enumerated().map { ($0.element.id, $0.offset + 1) })
        }
        let originalRanks = ranks(original), targetRanks = ranks(targeted), componentRanks = components.map(ranks)
        // Keep distinct corrections/qualifications, even with almost identical
        // vocabulary. Components contribute their BEST rank, not their sum:
        // mentioning more sides must not multiply a passage's fusion weight.
        var candidates: [String: LectureHit] = [:]
        for hit in original + targeted + components.flatMap({ $0 }) { candidates[hit.id] = hit }
        var ranked = candidates.values.map { candidate in
            var hit = candidate
            hit.score = originalRanks[hit.id].map { originalWeight / Double(60 + $0) } ?? 0
            hit.score += targetRanks[hit.id].map { targetWeight / Double(60 + $0) } ?? 0
            if let rank = componentRanks.compactMap({ $0[hit.id] }).min() {
                hit.score += componentWeight / Double(60 + rank)
            }
            return hit
        }
        ranked.sort { $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score }
        let fused = Dictionary(uniqueKeysWithValues: ranked.map { ($0.id, $0) })
        var retained: [LectureHit] = [], reasons: [String: String] = [:]
        var budget = LectureRetrieval.maxEvidenceCharacters
        func duplicate(_ hit: LectureHit) -> Bool {
            retained.contains { $0.passage.documentID == hit.passage.documentID
                && $0.passage.page == hit.passage.page && $0.passage.text == hit.passage.text }
        }
        func retain(_ hit: LectureHit, reason: String) {
            guard retained.count < 4, hit.passage.text.count <= budget, !duplicate(hit) else { return }
            retained.append(hit); budget -= hit.passage.text.count; reasons[hit.id] = reason
        }
        // Reserve each component's first hit before filling by fusion. A passage
        // ranked first for multiple components uses one slot. This balances the
        // context without weakening a branch's lexical/semantic gates.
        for (index, hits) in components.enumerated() {
            if let first = hits.first, let hit = fused[first.id] { retain(hit, reason: "component:\(index)") }
        }
        for hit in ranked { retain(hit, reason: "fusion") }
        let trace = ranked.map { hit in
            let included = reasons[hit.id] != nil
            let exclusion: String? = included ? nil : duplicate(hit) ? "exactDuplicate"
                : retained.count >= 4 ? "hitLimit" : "characterBudget"
            return GapRetrievalTrace.Candidate(id: hit.id, originalRank: originalRanks[hit.id], targetRank: targetRanks[hit.id],
                componentRanks: componentRanks.map { $0[hit.id] }, fusedScore: hit.score, retained: included,
                selectionReason: reasons[hit.id], exclusion: exclusion)
        }
        return (retained, GapRetrievalTrace(targetQuery: gap.retrievalText, informationNeeds: gap.expansion,
            targetSemanticAvailable: targetVector != nil, componentQueries: queries,
            componentSemanticAvailable: vectors.map { $0 != nil }, candidates: trace))
    }
}
