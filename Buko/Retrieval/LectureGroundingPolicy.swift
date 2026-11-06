import Foundation

nonisolated struct LectureCompletion: Sendable {
    struct RequestedContent: Sendable {
        let selectedText: String
        let passageID: String
        let excerpt: String
    }
    var lines: [String]
    var citations: [LectureCitation]
    var extractive: Bool
    var explanation: String
    var evidenceCount: Int
    // Request-local evidence handoff, not proof of semantic accuracy or storage.
    var requestedContent: RequestedContent? = nil
    var comparisonSupport: [RequestedContent] = []
}

/// The model may select source IDs, but cannot supply displayed answer prose or quotes.
/// This enforces extraction, not source truth, relevance, or complete semantic support.
nonisolated enum LectureGroundingPolicy {
    enum Refusal {
        case noDocuments, noMatch, instructionRisk, insufficient, conflicting
        case invalidSelection, contextLimit, modelFailure, unverifiedText

        var explanation: String {
            switch self {
            case .noDocuments:
                return "Attach a lecture PDF to this notebook before requesting a source-backed completion."
            case .noMatch:
                return "No matching lecture passage was retrieved. Try a more specific selection or attach another source. A retrieval miss does not establish that the answer is absent from your PDFs."
            case .unverifiedText:
                return "An attached PDF's searchable text disagrees with its visible OCR text. Lecture answers are paused for this notebook. Open Lecture sources to inspect the flagged pages, then replace or remove the affected source. OCR can also be mistaken; neither reading was accepted as evidence."
            case .instructionRisk:
                return "The handwriting or retrieved sources contain possible instructions to override the evidence rules. No completion was produced. Review the selection and lecture PDFs."
            case .insufficient:
                return "The retrieved passages did not establish an answer to this selection. Try a more specific selection or inspect the lecture PDFs."
            case .conflicting:
                return "The retrieved passages appear to disagree. Check the lecture PDFs and identify the applicable source before completing these notes."
            case .invalidSelection:
                return "The model did not return a valid selection of supporting passages. No completion was produced."
            case .contextLimit:
                return "The complete retrieved evidence did not fit the model context. Narrow the selection and try again."
            case .modelFailure:
                return "The on-device model could not assess the lecture evidence. No completion was produced. Try again."
            }
        }
    }

    static func abstain(_ reason: Refusal, evidenceCount: Int) -> LectureCompletion {
        LectureCompletion(lines: [], citations: [], extractive: false,
                          explanation: reason.explanation, evidenceCount: evidenceCount)
    }

    /// A conservative tripwire for recognizable instruction overrides, not a general
    /// injection detector. It can reject legitimate lectures discussing these attacks.
    /// The primary boundary is that only app-resolved source text can become output.
    static func containsInstructionOverride(_ text: String) -> Bool {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                                  locale: Locale(identifier: "en_US"))
            .unicodeScalars.filter { $0.properties.generalCategory != .format }
            .map(String.init).joined()
        let normalized = folded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let patterns = [
            #"\b(system|developer|assistant)\s*(override|message|instruction|prompt)\b"#,
            #"\b(ignore|disregard|override|bypass|forget)\b.{0,100}\b(instructions?|rules?|prompts?|evidence|sources?|previous|prior)\b"#,
            #"\b(do not|don't|never)\s+(follow|obey|use|cite)\b.{0,60}\b(instructions?|rules?|evidence|sources?)\b"#,
            #"\b(invent|fabricate|forge)\b.{0,60}\b(citations?|quotes?|quotations?|evidence|sources?)\b"#,
            #"<\s*/?\s*(system|developer|assistant)\b|\[\s*inst\s*\]|<\|(?:im_start|im_end|system|assistant)\|>"#
        ]
        return patterns.contains { normalized.range(of: $0, options: .regularExpression) != nil }
    }

    static func preflight(selected: String, context: String, intent: String, action: String,
                          search: LectureSearch) -> LectureCompletion? {
        if search.hasUnverifiedText { return abstain(.unverifiedText, evidenceCount: search.hits.count) }
        let inputs = [selected, context, intent, action] + search.hits.flatMap { [$0.passage.title, $0.passage.text] }
        if inputs.contains(where: containsInstructionOverride) {
            return abstain(.instructionRisk, evidenceCount: search.hits.count)
        }
        if search.hits.isEmpty {
            return abstain(search.documentCount == 0 ? .noDocuments : .noMatch, evidenceCount: 0)
        }
        return nil
    }

    static func resolve(status: String, sourceIDs: [String], selected: String, context: String,
                        intent: String, action: String, search: LectureSearch) -> LectureCompletion {
        if let refusal = preflight(selected: selected, context: context, intent: intent, action: action, search: search) {
            return refusal
        }
        switch status {
        case "insufficient": return abstain(.insufficient, evidenceCount: search.hits.count)
        case "conflicting": return abstain(.conflicting, evidenceCount: search.hits.count)
        case "supported": break
        default: return abstain(.invalidSelection, evidenceCount: search.hits.count)
        }
        guard !sourceIDs.isEmpty, sourceIDs.count <= 4, Set(sourceIDs).count == sourceIDs.count else {
            return abstain(.invalidSelection, evidenceCount: search.hits.count)
        }
        var citations: [LectureCitation] = []
        for id in sourceIDs {
            // Accept only the request-local IDs actually supplied to this model call.
            guard let hit = search.hits.enumerated().first(where: { "P\($0.offset + 1)" == id })?.element,
                  !hit.passage.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return abstain(.invalidSelection, evidenceCount: search.hits.count)
            }
            citations.append(LectureCitation(passage: hit.passage, quote: hit.passage.text))
        }
        return LectureCompletion(lines: citations.map(\.quote), citations: citations, extractive: true,
            explanation: "Original lecture passages, selected by the model and copied verbatim. Relevance is not independently verified; inspect the linked pages for surrounding context.",
            evidenceCount: search.hits.count)
    }
}
