import PencilKit

/// Idle-time preparation independent of the text an autofill may later generate. Complete recognized words can retain joined cursive; ambiguous letter
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
    func prepare(document: AutofillDocument) async throws -> PreparedHandwriting {
        var result = PreparedHandwriting()
        let started = ProcessInfo.processInfo.systemUptime
        try Task.checkCancellation()
        guard document.ink.count <= 20_000_000,
              let drawing = try? AutofillDocument.drawing(document.ink),
              let history = try? (document.history.isEmpty ? [] : JSONDecoder().decode([AutofillRecord].self, from: document.history)) else { return result }
        let generated = Set(history.flatMap(\.strokeIDs))
        let candidates = drawing.strokes.filter { !generated.contains($0.id) }
        let ordered = AutofillTypography.rows(candidates).sorted { $0.bounds.minY > $1.bounds.minY }
        var complete: [PKStroke] = []
        for row in ordered where row.strokes.count <= 1_200 {
            if complete.count + row.strokes.count > 1_200 { break }
            complete += row.strokes
        }
        guard !complete.isEmpty else { return result }
        let recognizer = PKStrokeRecognizer(preferredLanguages: [Locale.Language(identifier: "en")])
        await recognizer.updateDrawing(PKDrawing(strokes: complete))
        try Task.checkCancellation()
        let recognized = await recognizer.recognizedText() ?? ""
        guard !recognized.isEmpty else { return result }
        // Index possible unfinished headings now so placement never needs a
        // second recognizer after the model has written its answer.
        for heading in Self.headings(in: recognized) {
            if ProcessInfo.processInfo.systemUptime - started > 4 { break }
            try Task.checkCancellation()
            let matches = await recognizer.search(heading, fullWordsOnly: false, caseMatchingOnly: false)
            for match in matches.prefix(4) {
                let text = await recognizer.recognizedText(strokeIDs: match.strokes) ?? ""
                if AutofillTypography.normalized(text) == AutofillTypography.normalized(heading) {
                    result.headings.append(.init(text: heading, bounds: match.bounds))
                }
            }
        }
        var seen = Set<String>()
        // Letters first: they remain useful even when future completions contain
        // words that have never appeared in the source notes.
        let characters = recognized.filter { !$0.isWhitespace }.map(String.init)
            .filter { seen.insert($0).inserted }.prefix(96)
        let words = Self.words(in: recognized).filter { $0.count > 1 && $0.count <= 128 && seen.insert($0).inserted }.prefix(128)
        let rows = AutofillTypography.rows(complete)
        for query in Array(characters) + Array(words) {
            if ProcessInfo.processInfo.systemUptime - started > 12 { break }
            try Task.checkCancellation()
            let matches = await recognizer.search(query, fullWordsOnly: query.count > 1, caseMatchingOnly: true)
            for match in matches.prefix(3) {
                try Task.checkCancellation()
                let strokes = complete.filter { match.strokes.contains($0.id) }
                guard Self.isIsolated(strokes: strokes, bounds: match.bounds, all: complete),
                      let row = rows.first(where: { $0.bounds.contains(CGPoint(x: match.bounds.midX, y: match.bounds.midY)) }) else { continue }
                let isolated = await recognizer.recognizedText(strokeIDs: match.strokes) ?? ""
                guard isolated.trimmingCharacters(in: .whitespacesAndNewlines) == query else { continue }
                let style = AutofillTypography.style(row, neighbors: rows)
                guard let sample = try? HandwritingSample(drawing: PKDrawing(strokes: strokes),
                    referenceTop: style.top, referenceHeight: style.height) else { continue }
                result.samples[query] = sample
                break
            }
        }
        try Task.checkCancellation()
        return result
    }

    nonisolated static func headings(in text: String) -> [String] {
        // Include short suffixes before each colon (e.g. “static scope:”) even
        // when recognition flattened neighboring lines into one paragraph.
        var result: [String] = [], seen = Set<String>()
        let sections = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
        for section in sections {
            for prefix in section.components(separatedBy: ":").dropLast() {
                let words = prefix.split(whereSeparator: \.isWhitespace)
                for count in 1...max(1, min(6, words.count)) where !words.isEmpty {
                    let heading = words.suffix(count).joined(separator: " ") + ":"
                    if heading.count <= 100, seen.insert(heading).inserted { result.append(heading) }
                    if result.count == 32 { return result }
                }
            }
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
