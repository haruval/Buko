import PencilKit

/// Sample individual recognized characters so every available personal letter
/// participates in new words, independent of the eventual completion text.
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
        let rows = AutofillTypography.rows(complete)
        var inspectedStrokeSets = Set<Set<UUID>>()
        for query in characters where result.samples[query] == nil {
            if ProcessInfo.processInfo.systemUptime - started > 12 { break }
            try Task.checkCancellation()
            let matches = await recognizer.search(query, fullWordsOnly: query.count > 1, caseMatchingOnly: true)
            for match in matches.prefix(8) {
                try Task.checkCancellation()
                let strokes = complete.filter { match.strokes.contains($0.id) }
                guard Self.isIsolated(strokes: strokes, bounds: match.bounds, all: complete),
                      rows.contains(where: { $0.bounds.contains(CGPoint(x: match.bounds.midX, y: match.bounds.midY)) }) else { continue }
                guard inspectedStrokeSets.insert(match.strokes).inserted else { continue }
                let text = (await recognizer.recognizedText(strokeIDs: match.strokes) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // PencilKit can return a whole word's stroke IDs for a character
                // search. Never label that entire word as one letter. Separate
                // disjoint print glyphs only when their count matches the exact
                // recognized text; connected or ambiguous ink remains unsampled.
                let letters = Self.letterDrawings(text: text, strokes: strokes)
                for (key, ink) in letters where result.samples[key] == nil {
                    if let sample = try? HandwritingSample.normalized(drawing: ink, text: key) {
                        result.samples[key] = sample
                    }
                }
                if result.samples[query] != nil { break }
            }
        }
        try Task.checkCancellation()
        return result
    }

    nonisolated static func letterDrawings(text: String, strokes: [PKStroke]) -> [(String, PKDrawing)] {
        let characters = text.filter { !$0.isWhitespace }.map(String.init)
        guard !characters.isEmpty, characters.count <= 128, !strokes.isEmpty,
              !text.contains(where: \.isNewline),
              strokes.allSatisfy({ $0.mask == nil }) else { return [] }
        if characters.count == 1 { return [(characters[0], PKDrawing(strokes: strokes))] }
        // Brush antialiasing can make neighboring printed letters' renderBounds
        // overlap. Group the centerline paths; dots/crossbars still share x spans.
        let paths = strokes.compactMap { stroke -> (stroke: PKStroke, bounds: CGRect)? in
            let points = stroke.path.map { $0.location.applying(stroke.transform) }
            guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
                  let minY = points.map(\.y).min(), let maxY = points.map(\.y).max(),
                  [minX, maxX, minY, maxY].allSatisfy(\.isFinite) else { return nil }
            return (stroke, CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
        }
        guard paths.count == strokes.count else { return [] }
        var groups: [(bounds: CGRect, strokes: [PKStroke])] = []
        for (stroke, bounds) in paths.sorted(by: { $0.bounds.minX < $1.bounds.minX }) {
            if let last = groups.last, bounds.minX <= last.bounds.maxX {
                groups[groups.count - 1].bounds = last.bounds.union(bounds)
                groups[groups.count - 1].strokes.append(stroke)
            } else { groups.append((bounds, [stroke])) }
        }
        guard groups.count == characters.count else { return [] }
        return zip(characters, groups).map { ($0.0, PKDrawing(strokes: $0.1.strokes)) }
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
