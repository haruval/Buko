import Observation
import PencilKit

@Observable @MainActor
final class AutofillInsertionState {
    private(set) var layout: AutofillLayout.Result?
    private(set) var isAccepting = false
    var issue: String?
    private(set) var isPreparing = false
    private var sampling: Task<Void, Never>?
    private var samplingDeadline: Task<Void, Never>?
    private var sampled = HandwritingSampler.Result()
    private var sampleDocuments: [AutofillDocument] = []
    var handwritingDocuments: (() -> [AutofillDocument])?
    private var proposal: AutofillProposal?
    private var document: AutofillDocument?
    private var acceptance: Task<Void, Never>?
    var currentDocument: (() -> AutofillDocument?)?
    var previewChanged: ((AutofillLayout.Result?) -> Void)?
    var commit: ((AutofillDocument, AutofillDocument) throws -> Void)?
    var accepted: (() -> Void)?

    var canAccept: Bool { layout?.missing.isEmpty == true && !isAccepting && !isPreparing }
    var missing: [String] { layout?.missing ?? [] }

    var handwritingDetail: String {
        if isPreparing { return "Matching handwriting from your notes…" }
        guard let layout else { return "" }
        if layout.sampledGlyphCount == 0 { return "Handwriting font · matched to the circled text’s size" }
        return layout.fallbackGlyphCount == 0 ? "Sampled from your notes" : "Your note samples, with a handwriting font for missing letters"
    }

    func capture() {
        cancel()
        document = currentDocument?()
        sampleDocuments = document.map { [$0] } ?? []
        sampleDocuments += (handwritingDocuments?() ?? []).filter { $0.noteID != document?.noteID }.prefix(3)
    }

    func prepare(_ proposal: AutofillProposal) {
        self.proposal = proposal
        sampled = HandwritingSampler.Result()
        rebuild()
        guard layout != nil, #available(iOS 27, *) else { return }
        isPreparing = true
        sampling = Task { [weak self, documents = sampleDocuments] in
            do {
                let result = try await HandwritingSampler().sample(documents: documents, proposal: proposal)
                try Task.checkCancellation()
                guard let self, self.proposal?.requestID == proposal.requestID, self.isPreparing else { return }
                self.sampled = result; self.isPreparing = false
                self.samplingDeadline?.cancel(); self.rebuild()
            } catch {
                guard let self, !Task.isCancelled, self.proposal?.requestID == proposal.requestID else { return }
                self.isPreparing = false; self.samplingDeadline?.cancel()
            }
        }
        // Recognition is optional. A slow or unavailable recognizer must never
        // hold acceptance hostage or replace a preview after the user accepts it.
        samplingDeadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            guard let self, self.proposal?.requestID == proposal.requestID else { return }
            self.sampling?.cancel(); self.isPreparing = false
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
            previewChanged?(result)
        } catch { issue = error.localizedDescription; layout = nil; previewChanged?(nil) }
    }

    func cancel() {
        acceptance?.cancel(); acceptance = nil
        sampling?.cancel(); sampling = nil; samplingDeadline?.cancel(); samplingDeadline = nil
        sampled = HandwritingSampler.Result(); sampleDocuments = []; isPreparing = false
        proposal = nil; document = nil; layout = nil; issue = nil
        isAccepting = false
        previewChanged?(nil)
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
                    self.layout = nil; previewChanged?(nil)
                }
            }
        }
    }
}
