import FoundationModels
import Observation
import PencilKit
import SwiftUI

@Observable @MainActor
final class CircleIntentState {
    enum Phase { case idle, tracing, recognizing, inferring, finished }
    var phase = Phase.idle
    var droplet: CircleDropletDynamics?
    var tailAnchor: CGPoint?
    var paintedPath = CGMutablePath() as CGPath
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
        phase = .idle; textBounds = []; popupBounds = .zero
        droplet = nil; tailAnchor = nil; paintedPath = CGMutablePath(); closedBoundary = nil; fittedRectangle = nil
        closedAt = nil; morphBegan = nil; motionActive = false
        motionTask?.cancel(); motionTask = nil
    }

    func trace(_ points: [CGPoint]) {
        if phase != .tracing { cancel(); phase = .tracing; issue = nil; recognizedText = "" }
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
        selectionBounds = CircleGeometry.path(screenPolygon).boundingBoxOfPath
        closedAt = Date.timeIntervalSinceReferenceDate
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
