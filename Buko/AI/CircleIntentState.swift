import FoundationModels
import Observation
import PencilKit
import SwiftUI

@Observable @MainActor
final class CircleIntentState {
    let insertion = AutofillInsertionState()
    enum Phase { case idle, tracing, recognizing, inferring, retrieving, proposing, drafting, finished }
    var phase = Phase.idle
    var noteID: UUID?
    var sourceLabel = "Determining source…"
    var sourceDetail = ""
    var citations: [LectureCitation] = []
    var retrievalSeconds: Double = 0
    var retrievedPassageCount = 0
    var retrievalMethod = ""
    var droplet: CircleDropletDynamics?
    var tailAnchor: CGPoint?
    var paintedPath = CGMutablePath() as CGPath
    var release: CircleJellyGeometry.Release?
    private var tracedPoints: [CGPoint] = []
    var projection = CGAffineTransform.identity
    private var captureScale: CGFloat = 1
    private var captureOffset = CGPoint.zero
    var closedBoundary: CircleJellyGeometry.Boundary?
    var fittedRectangle: CircleJellyGeometry.Boundary?
    var closedAt: TimeInterval?
    var morphBegan: TimeInterval?
    var motionActive = false
    private var motionTask: Task<Void, Never>?

    var textBounds: [CGRect] = []
    var selectionBounds = CGRect.zero
    var recognizedText = ""
    var nearbyContext = ""
    var missingInformation: MissingInformationPlan?
    var intent = ""
    var action = ""
    private(set) var proposal: AutofillProposal? {
        didSet { if let proposal { insertion.prepare(proposal) } }
    }
    var draftDetail = ""
    var draftingSeconds: Double = 0
    var arithmeticChecked = false
    var intentSeconds: Double = 0
    var proposalSeconds: Double = 0
    var recognitionSeconds: Double = 0
    private var modelStartedAt: Double?
    var evidence = ""
    var clarification = ""
    var issue: String?
    var elapsed: Double = 0
    var recognitionMethod = ""
    private var popupAnchor: CGPoint?
    var popupBounds = CGRect.zero
    private var requestID = UUID()
    private var task: Task<Void, Never>?
    private var timeout: Task<Void, Never>?

    var processing: Bool { phase == .recognizing || phase == .inferring || phase == .retrieving || phase == .proposing || phase == .drafting }

    var progressLabel: String {
        switch phase {
        case .recognizing: "Reading handwriting…"
        case .retrieving: "Searching lecture PDFs…"
        case .proposing: "Checking completion evidence…"
        case .drafting: "Writing the proposed fill…"
        default: "Inferring intent and action…"
        }
    }

    var hasPreview: Bool { processing || phase == .finished }

    /// Camera movement abandons only an unfinished drawn gesture. Once a request
    /// owns a snapshot, it continues independently of the current viewport.
    func cancelTracing() {
        guard phase == .tracing else { return }
        cancel()
    }

    /// Editing, tool changes and backgrounding may invalidate pending work.
    func cancelPending() {
        guard phase != .finished else { return }
        cancel()
    }

    /// A completed proposal is tied to the captured ink too, not just a running task.
    func drawingDidChange() {
        guard phase != .idle else { return }
        cancel()
    }

    func updateProjection(scale: CGFloat, offset: CGPoint) {
        guard closedAt != nil else { return }
        let ratio = scale / captureScale
        let next = CGAffineTransform(a: ratio, b: 0, c: 0, d: ratio,
            tx: captureOffset.x * ratio - offset.x, ty: captureOffset.y * ratio - offset.y)
        if next != projection {
            projection = next
            if let popupAnchor {
                popupBounds = CirclePopupPlacement.projected(anchor: popupAnchor, size: popupBounds.size, projection: next)
            }
        }
    }

    func positionPopup(size: CGSize, viewport: CGSize) {
        if popupAnchor == nil {
            var occupied = selectionBounds
            if let preview = insertion.layout {
                occupied = occupied.union(PageGeometry.screenRect(preview.bounds, scale: captureScale, offset: captureOffset))
            }
            let initial = CirclePopupPlacement.place(size: size, viewport: viewport,
                region: occupied.applying(projection))
            popupAnchor = initial.origin.applying(projection.inverted())
        }
        if let popupAnchor {
            popupBounds = CirclePopupPlacement.projected(anchor: popupAnchor, size: size, projection: projection)
        }
    }

    func resetPopupAnchor() { popupAnchor = nil }

    func cancel() {
        insertion.cancel()
        requestID = UUID()
        task?.cancel(); task = nil
        timeout?.cancel(); timeout = nil
        arithmeticChecked = false
        citations = []; sourceLabel = "Determining source…"; sourceDetail = ""
        retrievalSeconds = 0; retrievedPassageCount = 0; retrievalMethod = ""
        nearbyContext = ""
        missingInformation = nil
        modelStartedAt = nil
        action = ""; proposal = nil; draftDetail = ""; draftingSeconds = 0
        intentSeconds = 0; proposalSeconds = 0; recognitionSeconds = 0; elapsed = 0
        phase = .idle; textBounds = []; popupBounds = .zero; popupAnchor = nil
        droplet = nil; tailAnchor = nil; paintedPath = CGMutablePath(); closedBoundary = nil; fittedRectangle = nil
        release = nil; tracedPoints = []; projection = .identity
        closedAt = nil; morphBegan = nil; motionActive = false
        motionTask?.cancel(); motionTask = nil
    }

    func trace(_ points: [CGPoint]) {
        guard !hasPreview else { return }
        if phase != .tracing { cancel(); phase = .tracing; issue = nil; recognizedText = "" }
        tracedPoints = points
        let now = Date.timeIntervalSinceReferenceDate
        guard let touch = points.last else { return }
        if droplet == nil { droplet = CircleDropletDynamics(at: touch, time: now) }
        else { droplet?.follow(touch, at: now) }
        tailAnchor = points.dropLast().last
        paintedPath = CircleJellyGeometry.paint(Array(points.dropLast()))
        motionActive = true
        selectionBounds = CircleGeometry.path(points).boundingBoxOfPath
    }

    func analyze(drawing: PKDrawing, polygon: [CGPoint], screenPolygon: [CGPoint], scale: CGFloat, offset: CGPoint) {
        guard !hasPreview else { return }
        insertion.capture()
        captureScale = scale; captureOffset = offset; projection = .identity
        selectionBounds = CircleGeometry.path(screenPolygon).boundingBoxOfPath
        closedAt = Date.timeIntervalSinceReferenceDate
        if let droplet, let closedAt {
            release = CircleJellyGeometry.Release(traced: tracedPoints, completed: screenPolygon,
                droplet: droplet, time: closedAt)
        }
        closedBoundary = CircleJellyGeometry.boundary(screenPolygon)
        // An unusually concave circle can put its centroid outside the region.
        // Keep the user's completed selection visible even in that case.
        if closedBoundary == nil {
            let bounds = CircleGeometry.path(screenPolygon).boundingBoxOfPath
            closedBoundary = CircleJellyGeometry.roundedRectangle(bounds)
        }
        settleMotion(after: CircleJellyGeometry.closeDuration + CircleJellyGeometry.fillDuration)
        guard #available(iOS 27, *) else {
            issue = "Handwriting intent requires iPadOS 27."; phase = .finished; return
        }
        task?.cancel(); timeout?.cancel()
        let id = UUID(); requestID = id
        let capturedNoteID = noteID
        let capturedAt = Date()
        phase = .recognizing; issue = nil; intent = ""; evidence = ""; clarification = ""
        let started = ProcessInfo.processInfo.systemUptime
        task = Task { [weak self] in
            guard let self else { return }
            let reading: CircleInkReader.Result
            do {
                reading = try await CircleInkReader().read(drawing: drawing, polygon: polygon)
            } catch {
                guard requestID == id, !Task.isCancelled else { return }
                finishIssue(error.localizedDescription, id: id); return
            }
            guard requestID == id, !Task.isCancelled else { return }
            recognitionSeconds = ProcessInfo.processInfo.systemUptime - started
            if !UIAccessibility.isReduceMotionEnabled {
                let remaining = max(0, (closedAt ?? Date.timeIntervalSinceReferenceDate)
                    + CircleJellyGeometry.closeDuration + CircleJellyGeometry.fillDuration - Date.timeIntervalSinceReferenceDate)
                do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
                guard requestID == id, !Task.isCancelled else { return }
            }
            recognizedText = reading.text
            recognitionMethod = reading.method
            var placement = Transaction(animation: nil)
            placement.disablesAnimations = true
            withTransaction(placement) {
                self.textBounds = reading.boxes.map {
                    PageGeometry.screenRect($0, scale: scale, offset: offset).insetBy(dx: -14, dy: -12)
                }
                if let first = self.textBounds.first {
                    let fitted = self.textBounds.dropFirst().reduce(first) { $0.union($1) }
                    self.fittedRectangle = CircleJellyGeometry.roundedRectangle(fitted)
                    self.morphBegan = Date.timeIntervalSinceReferenceDate
                    self.settleMotion(after: CircleJellyGeometry.morphDuration)
                }
                self.phase = .inferring
            }
            // Retain exactly the capped text supplied to both model stages.
            let context = String(reading.context.prefix(IntentPrompts.contextCharacterLimit))
            nearbyContext = context
            if [recognizedText, context].contains(where: LectureGroundingPolicy.containsInstructionOverride) {
                sourceLabel = "Completion withheld"
                sourceDetail = LectureGroundingPolicy.Refusal.instructionRisk.explanation
                phase = .finished; timeout?.cancel()
                return
            }
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                finishIssue(Self.unavailableMessage(model), id: id); return
            }
            let modelStarted = ProcessInfo.processInfo.systemUptime
            modelStartedAt = modelStarted
            var proposalStarted: Double?
            do {
                let plan = try await CirclePlanner.infer(selected: recognizedText, context: context, model: model)
                guard requestID == id, !Task.isCancelled else { return }
                intent = plan.intent
                action = plan.action
                missingInformation = plan.gap?.value
                intentSeconds = ProcessInfo.processInfo.systemUptime - modelStarted
                elapsed = intentSeconds
                evidence = plan.evidence
                clarification = plan.clarification
                if clarification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Every app request must identify its missing information.
                    // Never silently retrieve with the benchmark's baseline path.
                    guard let gap = plan.gap else { throw GapPlanError.invalidReferences("missingPlan") }
                    phase = .retrieving
                    guard let noteID = capturedNoteID else { throw LectureLibrary.LibraryError.missingDocument }
                    let search = try await LectureLibrary.shared.search(noteID: noteID, selected: recognizedText, intent: intent, gap: gap)
                    guard requestID == id, !Task.isCancelled else { return }
                    retrievalSeconds = search.seconds
                    retrievedPassageCount = search.hits.count
                    retrievalMethod = search.hasUnverifiedText ? "Paused · source text needs review"
                        : search.semanticAvailable ? "BM25 + semantic rank fusion" : "BM25 · sentence embedding unavailable"
                    phase = .proposing
                    proposalStarted = ProcessInfo.processInfo.systemUptime
                    switch CircleCompletionRoute.select(for: recognizedText, hasLectureEvidence: !search.hits.isEmpty) {
                    case .arithmetic(let checked):
                        guard try await sourcesUnchanged(search, noteID: noteID, request: id) else { return }
                        if checked.clarification.isEmpty, !checked.lines.isEmpty {
                            proposal = AutofillProposal(requestID: id, noteID: noteID, capturedAt: capturedAt,
                                selectionPolygon: polygon, selectedText: recognizedText, sourceRevision: search.revision,
                                content: AutofillContent(lines: checked.lines.map { .init(text: $0, citationIndices: []) },
                                                         origin: .localArithmetic), citations: [])
                            draftDetail = "Calculated on this device from the recognized operands."
                        }
                        clarification = checked.clarification
                        arithmeticChecked = checked.clarification.isEmpty
                        citations = []
                        sourceLabel = "Local arithmetic"
                        sourceDetail = checked.clarification.isEmpty
                            ? "Computed from the recognized matrix operands on this device."
                            : "Confirm the recognized matrices before calculating."
                    case .lecture:
                        sourceLabel = "Assessing lecture evidence…"
                        let completion = try await LectureComposer.complete(selected: recognizedText, context: context,
                            intent: intent, action: action, search: search, model: model)
                        guard requestID == id, !Task.isCancelled else { return }
                        guard try await sourcesUnchanged(search, noteID: noteID, request: id) else { return }
                        citations = completion.citations
                        retrievedPassageCount = completion.evidenceCount
                        sourceLabel = completion.extractive ? "Lecture PDFs · original excerpts" : "Lecture PDFs · no completion"
                        sourceDetail = completion.explanation
                        if completion.extractive {
                            phase = .drafting
                            let draftingStarted = ProcessInfo.processInfo.systemUptime
                            let draft = try await AutofillWriter.draft(selected: recognizedText, context: context,
                                intent: intent, action: action, gap: gap.value, evidence: completion,
                                search: search, model: model)
                            guard requestID == id, !Task.isCancelled else { return }
                            guard try await sourcesUnchanged(search, noteID: noteID, request: id) else { return }
                            draftingSeconds = ProcessInfo.processInfo.systemUptime - draftingStarted
                            draftDetail = draft.explanation
                            if let content = draft.content {
                                proposal = AutofillProposal(requestID: id, noteID: noteID, capturedAt: capturedAt,
                                    selectionPolygon: polygon, selectedText: recognizedText, sourceRevision: search.revision,
                                    content: content, citations: completion.citations,
                                    insertionTarget: gap.value.targets.count == 1 ? gap.value.targets[0].quote : nil)
                            }
                        } else {
                            draftDetail = completion.explanation
                        }
                    case .noEvidence:
                        guard try await sourcesUnchanged(search, noteID: noteID, request: id) else { return }
                        sourceLabel = search.hasUnverifiedText ? "Lecture PDFs · check source text"
                            : search.documentCount == 0 ? "Lecture PDFs · none attached" : "Lecture PDFs · no match"
                        sourceDetail = LectureGroundingPolicy.abstain(
                            search.hasUnverifiedText ? .unverifiedText : search.documentCount == 0 ? .noDocuments : .noMatch,
                            evidenceCount: 0).explanation
                        proposal = nil; citations = []
                        draftDetail = sourceDetail
                    }
                    proposalSeconds = ProcessInfo.processInfo.systemUptime - (proposalStarted ?? modelStarted)
                } else {
                    sourceLabel = "Clarification needed"
                    sourceDetail = "Confirm the circled request before retrieving a completion."
                }
                elapsed = intentSeconds + proposalSeconds
                phase = .finished; timeout?.cancel()
            } catch {
                guard requestID == id, !Task.isCancelled else { return }
                if let proposalStarted { proposalSeconds = ProcessInfo.processInfo.systemUptime - proposalStarted }
                else { intentSeconds = ProcessInfo.processInfo.systemUptime - modelStarted }
                elapsed = intentSeconds + proposalSeconds
                finishIssue("Autofill couldn’t finish: \(error.localizedDescription)", id: id)
            }
        }
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(IntentPrompts.timeoutSeconds)) } catch { return }
            guard let self, self.requestID == id, self.processing else { return }
            self.task?.cancel()
            self.finishIssue("Recognition or the model took too long. Close this preview and circle the text again to retry.", id: id)
            self.requestID = UUID() // A late framework response cannot replace this message.
        }
    }

    private func sourcesUnchanged(_ search: LectureSearch, noteID: UUID, request: UUID) async throws -> Bool {
        let revision = try await LectureLibrary.shared.revision(noteID: noteID)
        guard requestID == request, !Task.isCancelled else { return false }
        guard revision == search.revision else {
            citations = []; sourceLabel = "Lecture PDFs · sources changed"; sourceDetail = ""
            finishIssue("Lecture sources changed during this request. Circle the text again to use the current sources.", id: request)
            return false
        }
        return true
    }

    private func settleMotion(after duration: TimeInterval) {
        motionTask?.cancel()
        motionActive = !UIAccessibility.isReduceMotionEnabled
        guard motionActive else { return }
        motionTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(duration)) } catch { return }
            self?.motionActive = false
        }
    }

    private func finishIssue(_ message: String, id: UUID) {
        guard requestID == id else { return }
        proposal = nil
        if let modelStartedAt, phase == .inferring || phase == .proposing || phase == .drafting {
            elapsed = ProcessInfo.processInfo.systemUptime - modelStartedAt
            if phase == .inferring { intentSeconds = elapsed }
            else { proposalSeconds = max(0, elapsed - intentSeconds) }
        }
        issue = message; phase = .finished; timeout?.cancel()
    }

    static func unavailableMessage(_ model: SystemLanguageModel = .default) -> String {
        switch model.availability {
        case .available: return "Foundation Models is ready."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Text recognized. Enable Apple Intelligence in system Settings to infer intent."
        case .unavailable(.modelNotReady):
            return "Text recognized. The on-device model is still downloading or preparing. Try again when Apple Intelligence is ready."
        case .unavailable(.deviceNotEligible):
            return "Text recognized. Foundation Models is unavailable on this device or simulator. Test intent on an Apple Intelligence-capable iPad with the model enabled."
        case .unavailable: return "Text recognized. Foundation Models is currently unavailable on this device."
        @unknown default: return "Foundation Models availability is unknown on this OS."
        }
    }
}
