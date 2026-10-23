import Foundation

/// Request-local diagnostics captured at the actual call boundary. These inputs
/// are never persisted, fed back into a model, or reconstructed from later state.
nonisolated enum PipelineEvent: Sendable {
    case began(id: String, title: String, instructions: String?, input: String)
    case completed(id: String, summary: String)
}

typealias PipelineObserver = @Sendable (PipelineEvent) async -> Void

nonisolated struct PipelineStep: Identifiable, Sendable {
    enum Status: Sendable { case running, completed, stopped }
    let id: String
    let title: String
    let instructions: String?
    let input: String
    var status = Status.running
    var summary = ""
}

nonisolated struct PipelineTrace: Sendable {
    private(set) var steps: [PipelineStep] = []

    mutating func receive(_ event: PipelineEvent) {
        switch event {
        case let .began(id, title, instructions, input):
            guard !steps.contains(where: { $0.id == id }) else { return }
            steps.append(PipelineStep(id: id, title: title, instructions: instructions, input: input))
        case let .completed(id, summary):
            guard let index = steps.firstIndex(where: { $0.id == id && $0.status == .running }) else { return }
            steps[index].status = .completed; steps[index].summary = summary
        }
    }

    mutating func stopRunning() {
        for index in steps.indices where steps[index].status == .running { steps[index].status = .stopped }
    }
}
