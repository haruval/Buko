import PencilKit

/// Request-local sampling: no training pass, alphabet exercise, profile file, or
/// network. Complete recognized words can retain joined cursive; ambiguous letter
/// matches fall back instead of slicing a stroke into invented glyphs.
actor HandwritingSampler {
    struct Result: Sendable {
        var samples: [String: HandwritingSample] = [:]
        var targetBounds: CGRect?
    }

    nonisolated static func words(in text: String) -> [String] {
        let expression = try! NSRegularExpression(pattern: #"[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)*"#)
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    @available(iOS 27, macOS 27, *)
    func sample(documents: [AutofillDocument], proposal: AutofillProposal) async throws -> Result {
        var result = Result()
        let started = ProcessInfo.processInfo.systemUptime
        var seen = Set<String>()
        let words = Self.words(in: proposal.text).filter { $0.count > 1 && seen.insert($0).inserted }.prefix(40)
        let characters = proposal.text.filter { !$0.isWhitespace }.map(String.init)
            .filter { seen.insert($0).inserted }.prefix(80)
        let queries = Array(words) + Array(characters)
        let selectedBounds = CircleGeometry.path(proposal.selectionPolygon).boundingBoxOfPath
        for (index, document) in documents.prefix(4).enumerated() {
            try Task.checkCancellation()
            guard document.ink.count <= 20_000_000,
                  let drawing = try? AutofillDocument.drawing(document.ink) else { continue }
            // A damaged attribution history cannot identify generated ink safely.
            guard let history = try? (document.history.isEmpty ? [] : JSONDecoder().decode([AutofillRecord].self, from: document.history)) else { continue }
            let generated = Set(history.flatMap(\.strokeIDs))
            let candidates = drawing.strokes.filter { !generated.contains($0.id) }
            let ordered = AutofillTypography.rows(candidates).sorted { a, b in
                if index == 0 { return abs(a.bounds.midY - selectedBounds.midY) < abs(b.bounds.midY - selectedBounds.midY) }
                return a.bounds.minY > b.bounds.minY
            }
            var complete: [PKStroke] = []
            for row in ordered where row.strokes.count <= 1_200 {
                if complete.count + row.strokes.count > 1_200 { break }
                complete += row.strokes
            }
            let recognizer = PKStrokeRecognizer(preferredLanguages: [Locale.Language(identifier: "en")])
            await recognizer.updateDrawing(PKDrawing(strokes: complete))
            try Task.checkCancellation()
            let recognized = await recognizer.recognizedText() ?? ""
            guard !recognized.isEmpty else { continue }
            if index == 0, let target = proposal.insertionTarget, target.hasSuffix(":") {
                let matches = await recognizer.search(target, fullWordsOnly: false, caseMatchingOnly: false)
                let inside = matches.filter { selectedBounds.contains($0.bounds) }
                if inside.count == 1, let match = inside.first {
                    let text = await recognizer.recognizedText(strokeIDs: match.strokes) ?? ""
                    if AutofillTypography.normalized(text) == AutofillTypography.normalized(target) {
                        result.targetBounds = match.bounds
                    }
                }
            }
            let rows = AutofillTypography.rows(complete)
            for query in queries where result.samples[query] == nil && recognized.contains(query) {
                if ProcessInfo.processInfo.systemUptime - started > 6 { return result }
                try Task.checkCancellation()
                let matches = await recognizer.search(query, fullWordsOnly: query.count > 1, caseMatchingOnly: true)
                for match in matches.prefix(3) {
                    try Task.checkCancellation()
                    let strokes = complete.filter { match.strokes.contains($0.id) }
                    guard Self.isIsolated(strokes: strokes, bounds: match.bounds, all: complete),
                          let row = rows.first(where: { $0.bounds.contains(CGPoint(x: match.bounds.midX, y: match.bounds.midY)) }) else { continue }
                    // Substring searches may return the entire connected word's
                    // stroke IDs. A second reading must identify exactly this token.
                    let isolated = await recognizer.recognizedText(strokeIDs: match.strokes) ?? ""
                    guard isolated.trimmingCharacters(in: .whitespacesAndNewlines) == query else { continue }
                    let style = AutofillTypography.style(row, neighbors: rows)
                    guard let sample = try? HandwritingSample(drawing: PKDrawing(strokes: strokes),
                        referenceTop: style.top, referenceHeight: style.height) else { continue }
                    result.samples[query] = sample
                    break
                }
            }
            if queries.allSatisfy({ result.samples[$0] != nil }) { break }
        }
        return result
    }

    @available(iOS 27, macOS 27, *)
    nonisolated static func isIsolated(strokes: [PKStroke], bounds: CGRect, all: [PKStroke]) -> Bool {
        guard !strokes.isEmpty, !bounds.isEmpty, bounds.width.isFinite, bounds.height.isFinite else { return false }
        let tolerance = min(3, max(1, bounds.height * 0.08))
        let allowed = bounds.insetBy(dx: -tolerance, dy: -tolerance)
        guard strokes.allSatisfy({ allowed.contains($0.renderBounds) }) else { return false }
        let ids = Set(strokes.map(\.id))
        // Don't steal a dot/accent from a neighboring glyph or omit one from this
        // sample. Every stroke whose center lies in the box must be accounted for.
        return all.allSatisfy { ids.contains($0.id) || !bounds.contains(CGPoint(x: $0.renderBounds.midX, y: $0.renderBounds.midY)) }
    }
}
