import Observation
import PencilKit

@Observable @MainActor
final class AutofillInsertionState {
    private(set) var layout: AutofillLayout.Result?
    private(set) var isAccepting = false
    var issue: String?
    private var sampled: HandwritingSampler.Result?
    var preparedHandwriting: ((AutofillProposal) async throws -> HandwritingSampler.Result)?
    private var proposal: AutofillProposal?
    private var document: AutofillDocument?
    private var capturedDocument: AutofillDocument?
    private var selection: [CGPoint] = []
    private(set) var isWriting = false
    private var preparation: Task<Void, Never>?
    private var preparationDocument: AutofillDocument?
    private var acceptance: Task<Void, Never>?
    var currentDocument: (() -> AutofillDocument?)?
    var previewChanged: ((AutofillLayout.Result?, Bool) -> Void)?
    var commit: ((AutofillDocument, AutofillDocument) throws -> Void)?
    var accepted: (() -> Void)?

    var canAccept: Bool { sampled != nil && layout?.missing.isEmpty == true && !isAccepting && !isWriting }
    var missing: [String] { layout?.missing ?? [] }

    var handwritingDetail: String {
        guard let layout else { return "" }
        if layout.sampledGlyphCount == 0 { return "Handwriting font · matched to the circled text’s size" }
        return layout.fallbackGlyphCount == 0 ? "Your handwriting · letter by letter" : "Your letters, with a handwriting font for missing characters"
    }

    func capture(selection: [CGPoint]) {
        cancel()
        self.selection = selection
        document = currentDocument?()
        capturedDocument = document
    }

    func writingBegan() {
        acceptance?.cancel(); acceptance = nil; isAccepting = false
        isWriting = true
        // Pending recognition belongs to the pre-stroke document. Wait for the
        // completed stroke before preparing again; ready samples stay stable.
        if sampled == nil { cancelPreparation() }
        // Let the real ink remain visible while the Pencil is down. The staged
        // reflow is rebuilt from all current ink after the stroke completes.
        previewChanged?(nil, false)
    }

    func writingEnded() {
        isWriting = false
        _ = rebase()
    }

    @discardableResult func rebase() -> Bool {
        guard let capturedDocument else { return true }
        guard let current = currentDocument?(),
              capturedDocument.matches(current) || capturedDocument.permitsAppending(current, outside: selection) else {
            cancel()
            return false
        }
        document = current
        if sampled == nil {
            if preparationDocument?.matches(current) != true {
                cancelPreparation()
                if !isWriting { prepareHandwriting() }
            }
        } else if !isWriting { rebuild() }
        return true
    }

    func prepare(_ proposal: AutofillProposal) {
        self.proposal = proposal
        cancelPreparation()
        sampled = nil
        layout = nil; issue = nil
        previewChanged?(nil, false)
        if !isWriting { prepareHandwriting() }
    }

    private func cancelPreparation() {
        preparation?.cancel(); preparation = nil
        preparationDocument = nil
    }

    private func prepareHandwriting() {
        guard let proposal, let document else { return }
        preparationDocument = document
        issue = nil
        preparation = Task { [weak self] in
            guard let self else { return }
            do {
                let ready = try await preparedHandwriting?(proposal) ?? HandwritingSampler.Result()
                try Task.checkCancellation()
                guard self.proposal?.requestID == proposal.requestID else { return }
                guard let current = currentDocument?(), document.matches(current) else { throw AutofillEditError.stale }
                sampled = ready
                rebuild()
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled, self.proposal?.requestID == proposal.requestID else { return }
                sampled = nil; layout = nil
                previewChanged?(nil, false)
                issue = error.localizedDescription
            }
        }
    }

    func rebuild() {
        guard !isWriting, let sampled, let proposal, let document else { return }
        do {
            guard let current = currentDocument?(), document.matches(current) else { throw AutofillEditError.stale }
            let result = try AutofillLayout.stage(text: proposal.text, drawing: AutofillDocument.drawing(document.ink),
                selection: proposal.selectionPolygon, pageCount: document.pageCount, samples: sampled.samples,
                selectedText: proposal.selectedText, target: proposal.insertionTarget, targetBounds: sampled.targetBounds)
            layout = result
            issue = result.missing.isEmpty ? nil : "Some symbols couldn’t be rendered as ink. Try a shorter fill."
            previewChanged?(result, false)
        } catch { issue = error.localizedDescription; layout = nil; previewChanged?(nil, false) }
    }

    func cancel(animatedReturn: Bool = false) {
        cancelPreparation()
        acceptance?.cancel(); acceptance = nil
        sampled = nil
        proposal = nil; document = nil; capturedDocument = nil; selection = []; layout = nil; issue = nil
        isAccepting = false; isWriting = false
        previewChanged?(nil, animatedReturn)
    }

    func accept() {
        guard canAccept, let proposal, let document, let layout else { return }
        isAccepting = true
        acceptance = Task { [weak self] in
            guard let self else { return }
            do {
                let revision = try await LectureLibrary.shared.revision(noteID: proposal.noteID)
                try Task.checkCancellation()
                guard self.proposal?.requestID == proposal.requestID else { return }
                guard revision == proposal.sourceRevision else { throw AutofillEditError.sourcesChanged }
                guard !isWriting, let current = currentDocument?(), document.matches(current) else { throw AutofillEditError.stale }
                guard #available(iOS 27, *), let commit else { throw AutofillEditError.unavailable }
                let after = try document.inserting(layout, proposal: proposal)
                try commit(document, after)
                // Commit saves first. Only a successful save replaces the live ink.
                accepted?()
            } catch is CancellationError { return }
            catch {
                guard self.proposal?.requestID == proposal.requestID, !Task.isCancelled else { return }
                issue = error.localizedDescription; isAccepting = false
                if let edit = error as? AutofillEditError, edit == .stale || edit == .sourcesChanged {
                    self.layout = nil; previewChanged?(nil, false)
                }
            }
        }
    }
}
