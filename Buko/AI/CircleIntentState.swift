import FoundationModels
import Observation
import PencilKit
import SwiftUI

@Observable @MainActor
final class CircleIntentState {
    enum Phase { case idle, tracing, recognizing, inferring, finished }
    var phase = Phase.idle
    var outline: [CGPoint] = []
    var flowOrigin: CGPoint?
    var flowBegan: TimeInterval = 0
    var pointTimes: [TimeInterval] = []
    var releasedAt: TimeInterval?

    var textBounds: [CGRect] = []
    var selectionBounds = CGRect.zero
    var recognizedText = ""
    var intent = ""
    var evidence = ""
    var clarification = ""
    var issue: String?
    var elapsed: Double = 0
    var recognitionMethod = ""
    var popupBounds = CGRect.zero
    private var requestID = UUID()
    private var task: Task<Void, Never>?
    private var timeout: Task<Void, Never>?

    var processing: Bool { phase == .recognizing || phase == .inferring }

    func cancel() {
        requestID = UUID()
        task?.cancel(); task = nil
        timeout?.cancel(); timeout = nil
        phase = .idle; outline = []; textBounds = []; popupBounds = .zero
        flowOrigin = nil; pointTimes = []; releasedAt = nil; flowBegan = 0
    }

    func trace(_ points: [CGPoint]) {
        if phase != .tracing { cancel(); phase = .tracing; issue = nil; recognizedText = "" }
        let now = Date.timeIntervalSinceReferenceDate
        if points.count > pointTimes.count {
            pointTimes.append(contentsOf: repeatElement(now, count: points.count - pointTimes.count))
        }
        if flowOrigin == nil, let origin = CircleGeometry.flowOrigin(points) {
            flowOrigin = origin
            flowBegan = now
            // The initial accumulated arc starts as a seed and unfurls in touch order.
            pointTimes = points.indices.map { now + Double($0) / Double(max(1, points.count - 1)) * 0.16 }
        }
        outline = points
        selectionBounds = CircleGeometry.path(points).boundingBoxOfPath
    }

    func analyze(drawing: PKDrawing, polygon: [CGPoint], scale: CGFloat, offset: CGPoint) {
        guard #available(iOS 27, *) else {
            issue = "Handwriting intent requires iPadOS 27."; phase = .finished; return
        }
        releasedAt = Date.timeIntervalSinceReferenceDate
        if flowOrigin == nil { flowOrigin = CGPoint(x: selectionBounds.midX, y: selectionBounds.midY); flowBegan = releasedAt! }
        task?.cancel(); timeout?.cancel()
        let id = UUID(); requestID = id
        phase = .recognizing; issue = nil; intent = ""; evidence = ""; clarification = ""
        let started = Date()
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
            recognizedText = reading.text
            recognitionMethod = reading.method
            var placement = Transaction(animation: nil)
            placement.disablesAnimations = true
            withTransaction(placement) {
                self.textBounds = reading.boxes.map {
                    PageGeometry.screenRect($0, scale: scale, offset: offset).insetBy(dx: -14, dy: -12)
                }
                self.phase = .inferring
            }
            let context = reading.context
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                finishIssue(Self.unavailableMessage(model), id: id); return
            }
            do {
                let session = LanguageModelSession(model: model, instructions: IntentPrompts.instructions)
                let response = try await session.respond(
                    to: IntentPrompts.request(selected: recognizedText, context: context),
                    generating: InferredCircleIntent.self,
                    options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 320))
                guard requestID == id, !Task.isCancelled else { return }
                intent = response.content.intent
                evidence = response.content.evidence
                clarification = response.content.clarification
                elapsed = Date().timeIntervalSince(started)
                phase = .finished; timeout?.cancel()
            } catch {
                guard requestID == id, !Task.isCancelled else { return }
                finishIssue("Foundation Models couldn’t infer intent: \(error.localizedDescription)", id: id)
            }
        }
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(45)) } catch { return }
            guard let self, self.requestID == id, self.processing else { return }
            self.task?.cancel()
            self.finishIssue("Recognition or the model took too long. Circle the text again to retry.", id: id)
            self.requestID = UUID() // A late framework response cannot replace this message.
        }
    }

    private func finishIssue(_ message: String, id: UUID) {
        guard requestID == id else { return }
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
