import PencilKit

@MainActor enum RoundTwoHandwritingChecks {
    static func run() async -> String {
        guard #available(iOS 27, *) else { return "Requires iOS 27" }
        do {
            let source = LectureHandwriting.drawing(pages: [["authentication vs authorization:"]])
            let note = Note(title: "Actual recognition fixture"); note.drawingData = source.dataRepresentation()
            let profile = try await HandwritingSampler().prepare(document: AutofillDocument(note))
            guard profile.samples.count >= 8, profile.samples.keys.allSatisfy({ $0.count == 1 }) else {
                return "Insufficient personal samples: \(profile.samples.keys.sorted())"
            }
            for sample in profile.samples.values {
                let bounds = try PKDrawing(data: sample.drawingData).bounds
                guard bounds.width < 150 else { return "A cached letter contains word-sized ink" }
            }
            note.autofillHistory = try JSONEncoder().encode([AutofillRecord(strokeIDs: source.strokes.map(\.id))])
            let generated = try await HandwritingSampler().prepare(document: AutofillDocument(note))
            guard generated.samples.isEmpty else { return "Generated ink must never become personal samples" }
            return "Letter checks passed: \(profile.samples.keys.sorted().joined()) · generated ink excluded"
        } catch { return error.localizedDescription }
    }
}
