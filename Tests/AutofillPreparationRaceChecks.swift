import Foundation
import PencilKit

@MainActor enum AutofillPreparationRaceChecks {
    private enum Failure: Error { case preparation }

    /// Deliberately ignores cancellation until released, as a slow recognition
    /// operation may do. Late successes and errors must not alter a newer preview.
    @MainActor private final class Preparation {
        var calls = 0
        var finished = Set<Int>()
        var pending: [Int: CheckedContinuation<HandwritingSampler.Result, Error>] = [:]

        func run() async throws -> HandwritingSampler.Result {
            calls += 1
            let call = calls
            defer { finished.insert(call) }
            return try await withCheckedThrowingContinuation { pending[call] = $0 }
        }

        func finish(_ call: Int, with result: Result<HandwritingSampler.Result, Error>) async throws {
            guard let continuation = pending.removeValue(forKey: call) else {
                preconditionFailure("Preparation must have started before completing it")
            }
            continuation.resume(with: result)
            try await wait { self.finished.contains(call) }
        }
    }

    private static func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition() {
            precondition(ContinuousClock.now < deadline, "Timed out waiting for preparation")
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    static func run() async throws {
        func stroke(_ y: CGFloat) -> PKStroke {
            let path = PKStrokePath(controlPoints: [CGPoint(x: 1100, y: y), CGPoint(x: 1130, y: y + 20), CGPoint(x: 1160, y: y)]
                .enumerated().map { i, p in
                    PKStrokePoint(location: p, timeOffset: Double(i) * 0.1, size: CGSize(width: 2, height: 2),
                                  opacity: 1, force: 0.7, azimuth: 0.2, altitude: 1.1)
                }, creationDate: Date(timeIntervalSince1970: 1))
            return PKStroke(ink: PKInk(.pen, color: .black), path: path, randomSeed: 42)
        }
        let note = Note(title: "Disposable preparation race")
        note.pageLayoutVersion = 2
        try note.setPages([NotebookPage()])
        let original = PKDrawing(strokes: [stroke(110)])
        note.drawingData = original.dataRepresentation()
        let polygon = [CGPoint(x: 1050, y: 90), CGPoint(x: 1250, y: 90),
                       CGPoint(x: 1250, y: 155), CGPoint(x: 1050, y: 155)]
        func proposal() -> AutofillProposal {
            AutofillProposal(requestID: UUID(), noteID: note.id, capturedAt: .now,
                selectionPolygon: polygon, selectedText: "A:", sourceRevision: "unused while disabled",
                content: .init(lines: [.init(text: "aaa", citationIndices: [])], origin: .lectureDraft), citations: [])
        }
        let sample = try HandwritingSample(drawing: PKDrawing(strokes: [stroke(60)]))
        var personal = HandwritingSampler.Result()
        personal.samples = ["a": sample]
        let preparation = Preparation()
        let state = AutofillInsertionState()
        state.currentDocument = { AutofillDocument(note) }
        state.preparedHandwriting = { _ in try await preparation.run() }
        var visiblePreview: AutofillLayout.Result?
        state.previewChanged = { result, _ in visiblePreview = result }
        func assertBlocked(_ message: String) {
            precondition(!state.canAccept && state.layout == nil && visiblePreview == nil, message)
            state.accept()
            precondition(!state.isAccepting, "A blocked Accept must not start a source lookup or commit")
        }

        state.capture(selection: polygon)
        state.prepare(proposal())
        try await wait { preparation.calls == 1 }
        assertBlocked("Preparation must finish before a preview can be accepted")
        state.writingBegan()
        note.drawingData = PKDrawing(strokes: original.strokes + [stroke(800)]).dataRepresentation()
        precondition(state.rebase(), "Outside handwriting must preserve the request")
        state.writingEnded()
        assertBlocked("Ending an outside stroke must not bypass pending preparation")
        try await wait { preparation.calls == 2 }
        try await preparation.finish(1, with: .success(.init()))
        assertBlocked("A cancelled preparation must not publish fallback letters")
        try await preparation.finish(2, with: .success(personal))
        precondition(state.canAccept && state.layout?.sampledGlyphCount == 3 && state.layout?.fallbackGlyphCount == 0)
        precondition(state.layout?.existing.strokes.count == 2, "Preview must retain the appended handwriting")

        // A ready preview keeps its stable personal letters while rebasing ink.
        state.writingBegan()
        note.drawingData = PKDrawing(strokes: original.strokes + [stroke(800), stroke(900)]).dataRepresentation()
        state.writingEnded()
        precondition(state.canAccept && state.layout?.existing.strokes.count == 3 && preparation.calls == 2)
        precondition(state.layout?.sampledGlyphCount == 3)

        // A failed preparation stays blocked even if another rebase is requested.
        state.prepare(proposal())
        try await wait { preparation.calls == 3 }
        assertBlocked("A new proposal must clear the old prepared preview")
        try await preparation.finish(3, with: .failure(Failure.preparation))
        precondition(state.issue != nil)
        precondition(state.rebase())
        assertBlocked("Preparation failure must not leave or recreate an acceptable layout")
        precondition(preparation.calls == 3, "Unchanged failed preparation must not retry implicitly")

        // A proposal arriving with the Pencil down waits for the final document.
        state.writingBegan()
        state.prepare(proposal())
        assertBlocked("A proposal arriving during writing must wait for the stroke")
        state.writingEnded()
        try await wait { preparation.calls == 4 }
        state.writingBegan()
        note.drawingData = PKDrawing(strokes: original.strokes + [stroke(800), stroke(900), stroke(1000)]).dataRepresentation()
        state.writingEnded()
        try await wait { preparation.calls == 5 }
        try await preparation.finish(5, with: .success(personal))
        try await preparation.finish(4, with: .failure(AutofillEditError.stale))
        precondition(state.canAccept && state.issue == nil && state.layout?.sampledGlyphCount == 3,
                     "A late failure must not overwrite the newer prepared preview")

        state.prepare(proposal())
        try await wait { preparation.calls == 6 }
        state.cancel()
        try await preparation.finish(6, with: .success(personal))
        assertBlocked("Cancelling a request must discard late preparation results")

        // A safe page append can rebase without Pencil delegate callbacks.
        state.capture(selection: polygon)
        state.prepare(proposal())
        try await wait { preparation.calls == 7 }
        try note.setPages(note.pages() + [NotebookPage()])
        precondition(state.rebase())
        try await wait { preparation.calls == 8 }
        try await preparation.finish(7, with: .failure(AutofillEditError.stale))
        assertBlocked("Page rebasing must wait for current preparation")
        try await preparation.finish(8, with: .success(personal))
        precondition(state.canAccept)

        // Changes inside the capture still invalidate acceptance immediately.
        state.writingBegan()
        note.drawingData = PKDrawing(strokes: original.strokes + [stroke(115)]).dataRepresentation()
        state.writingEnded()
        assertBlocked("An unsafe edit must discard the prepared layout")
        state.cancel()
        print("Autofill preparation races passed: pending/outside ink, fresh personal samples, late success/error, failure, cancellation, page append and unsafe edit")
    }
}
