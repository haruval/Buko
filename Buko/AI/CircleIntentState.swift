import FoundationModels
import Observation
import PencilKit
import SwiftUI

@Observable @MainActor
final class CircleIntentState {
    enum Phase { case idle, tracing, recognizing, inferring, proposing, finished }
    var phase = Phase.idle
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
    var intent = ""
    var action = ""
    var proposedLines: [String] = []
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

    var processing: Bool { phase == .recognizing || phase == .inferring || phase == .proposing }

    /// Routine input/camera changes can cancel work, but only X dismisses a result.
    func cancelPending() {
        guard phase != .finished else { return }
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
            let initial = CirclePopupPlacement.place(size: size, viewport: viewport,
                region: selectionBounds.applying(projection))
            popupAnchor = initial.origin.applying(projection.inverted())
        }
        if let popupAnchor {
            popupBounds = CirclePopupPlacement.projected(anchor: popupAnchor, size: size, projection: projection)
        }
    }

    func cancel() {
        requestID = UUID()
        task?.cancel(); task = nil
        timeout?.cancel(); timeout = nil
        arithmeticChecked = false
        modelStartedAt = nil
        action = ""; proposedLines = []; intentSeconds = 0; proposalSeconds = 0; recognitionSeconds = 0; elapsed = 0
        phase = .idle; textBounds = []; popupBounds = .zero; popupAnchor = nil
        droplet = nil; tailAnchor = nil; paintedPath = CGMutablePath(); closedBoundary = nil; fittedRectangle = nil
        release = nil; tracedPoints = []; projection = .identity
        closedAt = nil; morphBegan = nil; motionActive = false
        motionTask?.cancel(); motionTask = nil
    }

    func trace(_ points: [CGPoint]) {
        guard phase != .finished else { return }
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
        guard phase != .finished else { return }
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
            let context = reading.context
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                finishIssue(Self.unavailableMessage(model), id: id); return
            }
            let modelStarted = ProcessInfo.processInfo.systemUptime
            modelStartedAt = modelStarted
            var proposalStarted: Double?
            do {
                let session = LanguageModelSession(model: model, instructions: IntentPrompts.instructions)
                let response = try await session.respond(
                    to: IntentPrompts.request(selected: recognizedText, context: context),
                    generating: InferredCircleIntent.self,
                    options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: IntentPrompts.intentTokenLimit))
                guard requestID == id, !Task.isCancelled else { return }
                intent = response.content.intent
                action = response.content.action
                intentSeconds = ProcessInfo.processInfo.systemUptime - modelStarted
                elapsed = intentSeconds
                evidence = response.content.evidence
                clarification = response.content.clarification
                let checked = MatrixProductCheck.evaluate(recognizedText)
                if let checked, !checked.clarification.isEmpty { clarification = checked.clarification }
                if clarification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let checked, checked.clarification.isEmpty {
                    proposedLines = checked.lines
                    arithmeticChecked = true
                } else if clarification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    phase = .proposing
                    proposalStarted = ProcessInfo.processInfo.systemUptime
                    let writer = LanguageModelSession(model: model, instructions: IntentPrompts.proposalInstructions)
                    let proposal = try await writer.respond(
                        to: IntentPrompts.proposalRequest(selected: recognizedText, context: context, plan: response.content),
                        generating: ProposedCircleAction.self,
                        options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: IntentPrompts.proposalTokenLimit))
                    guard requestID == id, !Task.isCancelled else { return }
                    proposalSeconds = ProcessInfo.processInfo.systemUptime - (proposalStarted ?? modelStarted)
                    clarification = proposal.content.clarification.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Never offer an apparently ready answer alongside a request
                    // to clarify its operands or meaning.
                    if clarification.isEmpty {
                        proposedLines = proposal.content.lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                        if proposedLines.isEmpty { issue = "The model returned no proposed content. Try a clearer selection." }
                    }
                }
                elapsed = intentSeconds + proposalSeconds
                phase = .finished; timeout?.cancel()
            } catch {
                guard requestID == id, !Task.isCancelled else { return }
                if let proposalStarted { proposalSeconds = ProcessInfo.processInfo.systemUptime - proposalStarted }
                else { intentSeconds = ProcessInfo.processInfo.systemUptime - modelStarted }
                elapsed = intentSeconds + proposalSeconds
                finishIssue("Foundation Models couldn’t finish the \(phase == .proposing ? "proposal" : "intent") stage: \(error.localizedDescription)", id: id)
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
        if let modelStartedAt, phase == .inferring || phase == .proposing {
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
