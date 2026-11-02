import Observation
import PencilKit

@Observable @MainActor
final class AutofillInsertionState {
    private(set) var layout: AutofillLayout.Result?
    private(set) var isAccepting = false
    var issue: String?
    private var sampled = HandwritingSampler.Result()
    var preparedHandwriting: ((AutofillProposal) async throws -> HandwritingSampler.Result)?
    private var proposal: AutofillProposal?
    private var document: AutofillDocument?
    private var preparation: Task<Void, Never>?
    private var acceptance: Task<Void, Never>?
    var currentDocument: (() -> AutofillDocument?)?
    var previewChanged: ((AutofillLayout.Result?, Bool) -> Void)?
    var commit: ((AutofillDocument, AutofillDocument) throws -> Void)?
    var accepted: (() -> Void)?

    var canAccept: Bool { layout?.missing.isEmpty == true && !isAccepting }
    var missing: [String] { layout?.missing ?? [] }

    var handwritingDetail: String {
        guard let layout else { return "" }
        if layout.sampledGlyphCount == 0 { return "Handwriting font · matched to the circled text’s size" }
        return layout.fallbackGlyphCount == 0 ? "Your handwriting · letter by letter" : "Your letters, with a handwriting font for missing characters"
    }

    func capture() {
        cancel()
        document = currentDocument?()
    }

    func prepare(_ proposal: AutofillProposal) {
        self.proposal = proposal
        preparation?.cancel()
        layout = nil; issue = nil
        preparation = Task { [weak self] in
            guard let self else { return }
            do {
                let ready = try await preparedHandwriting?(proposal) ?? HandwritingSampler.Result()
                try Task.checkCancellation()
                guard self.proposal?.requestID == proposal.requestID else { return }
                sampled = ready
                rebuild()
            } catch is CancellationError { }
            catch {
                guard self.proposal?.requestID == proposal.requestID else { return }
                issue = error.localizedDescription
            }
        }
    }

    func rebuild() {
        guard let proposal, let document else { return }
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
        preparation?.cancel(); preparation = nil
        acceptance?.cancel(); acceptance = nil
        sampled = HandwritingSampler.Result()
        proposal = nil; document = nil; layout = nil; issue = nil
        isAccepting = false
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
                guard let current = currentDocument?(), document.matches(current) else { throw AutofillEditError.stale }
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
