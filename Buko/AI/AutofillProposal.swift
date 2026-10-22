import Foundation

/// Preview content, kept separate from the verbatim evidence and from canvas edits.
/// Citation markers are metadata; `text` is the plain text for a future insertion.
nonisolated struct AutofillContent: Sendable {
    enum Origin: Sendable { case lectureDraft, localArithmetic }
    struct Line: Sendable {
        let text: String
        let citationIndices: [Int]
    }

    let lines: [Line]
    let origin: Origin
    var text: String { lines.map(\.text).joined(separator: "\n") }
}

/// Request-scoped handoff for the later spatial-edit stage. This is not an accepted
/// edit: insertion must revalidate the document and source revisions and support undo.
nonisolated struct AutofillProposal: Sendable {
    let requestID: UUID
    let noteID: UUID
    let capturedAt: Date
    let selectionPolygon: [CGPoint]
    let selectedText: String
    let sourceRevision: String
    let content: AutofillContent
    let citations: [LectureCitation]

    var text: String { content.text }
}
