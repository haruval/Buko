import Foundation
import FoundationModels

nonisolated struct CirclePlan: Sendable {
    let intent: String
    let action: String
    let evidence: String
    let clarification: String
    let gap: ValidatedGapPlan?
    let inputTokens: Int?
    let responseTokenLimit: Int
    let planningPasses: Int
    let preliminaryIntent: String?
    var bindingStrategy: String? = nil
}

/// Shared by the app and benchmark. Explicit selected syntax fixes the target
/// before model inference; freeform requests retain the model planning path.
nonisolated enum CirclePlanner {
    /// Bind only the narrow heading/comparison grammar, never nearby headings or
    /// inferred answers. Both retrieval modes share this target contract.
    static func explicitPlan(in transcript: GapTranscript, mode: CircleRetrievalMode) throws -> CirclePlan? {
        switch GapSyntaxBinding.inspect(transcript) {
        case .unconstrained: return nil
        case .ambiguousHeadings:
            return CirclePlan(intent: "The user wants to complete the selected notes.",
                action: "Confirm which heading to complete before retrieving evidence.", evidence: "",
                clarification: "Which heading should I complete? Circle one heading, or write an explicit comparison.",
                gap: nil, inputTokens: nil, responseTokenLimit: 0, planningPasses: 0,
                preliminaryIntent: nil, bindingStrategy: "ambiguousHeadings")
        case .bound(let binding):
            let format: String
            switch binding.operation {
            case .define: format = "definition"
            case .giveExample: format = binding.headingRequest?.need ?? "concrete example"
            case .compare: format = "comparison"
            case .explain: format = "explanation of \(binding.informationNeeds.joined(separator: ", "))"
            default: return nil
            }
            let gap = try ValidatedGapPlan.validate(binding.plan(needs: binding.informationNeeds), in: transcript)
            let target = gap.targetText.hasSuffix(":") ? String(gap.targetText.dropLast()) : gap.targetText
            let subject = binding.headingRequest?.subject ?? target
            let intent = binding.operation == .giveExample
                ? "The user wants a \(format) of \(subject)."
                : binding.operation == .explain ? "The user wants an \(format) for \(subject)."
                : "The user wants to \(binding.operation.verb) \(subject)."
            return CirclePlan(intent: intent,
                action: "Add a concise \(format) beneath \(target).", evidence: gap.targetText, clarification: "",
                gap: mode == .structuredGap ? gap : nil, inputTokens: nil, responseTokenLimit: 0,
                planningPasses: 0, preliminaryIntent: nil, bindingStrategy: "explicitSyntax")
        }
    }

    @available(iOS 27, macOS 27, *)
    static func infer(selected: String, context: String, mode: CircleRetrievalMode = .structuredGap,
                      model: SystemLanguageModel = .default, observer: PipelineObserver? = nil) async throws -> CirclePlan {
        try Task.checkCancellation()
        guard ![selected, context].contains(where: LectureGroundingPolicy.containsInstructionOverride) else {
            throw GapPlanError.instructionRisk
        }
        let transcript = GapTranscript(selected: selected, context: context)
        if let explicit = try explicitPlan(in: transcript, mode: mode) {
            await observer?(.began(id: "binding", title: "Identify the unfinished heading", instructions: nil, input: selected))
            try Task.checkCancellation()
            await observer?(.completed(id: "binding", summary: "Local syntax check · no model call\n" + explicit.intent + "\n" + explicit.clarification))
            return explicit
        }
        switch mode {
        case .baseline:
            let request = IntentPrompts.request(selected: selected, context: context)
            await observer?(.began(id: "intent", title: "Infer intent", instructions: IntentPrompts.instructions, input: request))
            try Task.checkCancellation()
            let session = LanguageModelSession(model: model, instructions: IntentPrompts.instructions)
            let response = try await session.respond(to: request,
                generating: InferredCircleIntent.self,
                options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: IntentPrompts.intentTokenLimit))
            try Task.checkCancellation()
            await observer?(.completed(id: "intent", summary: response.content.intent + "\n" + response.content.action + "\n" + response.content.clarification))
            return CirclePlan(intent: response.content.intent, action: response.content.action,
                evidence: response.content.evidence, clarification: response.content.clarification,
                gap: nil, inputTokens: nil, responseTokenLimit: IntentPrompts.intentTokenLimit,
                planningPasses: 1, preliminaryIntent: nil)
        case .structuredGap:
            // Carry the first interpretation into a coverage/reference review.
            // It is a hypothesis, not permission to repeat already-written content.
            let preliminary = try await infer(selected: transcript.selected, context: transcript.context,
                mode: .baseline, model: model, observer: observer)
            if !preliminary.clarification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return preliminary }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let blocks = ["selected_handwriting": transcript.blocks.filter(\.selected),
                          "nearby_context_only": transcript.blocks.filter { !$0.selected }]
            let fields: [String: Any] = ["blocks": try JSONSerialization.jsonObject(with: encoder.encode(blocks)),
                "preliminary_hypothesis": ["intent": preliminary.intent, "action": preliminary.action]]
            let prompt = String(decoding: try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]), as: UTF8.self)
            let instructions = MissingInformationPrompts.instructions
            let count = try await model.tokenCount(for: Instructions(instructions))
                + model.tokenCount(for: ContextualGapReferences.generationSchema) + model.tokenCount(for: Prompt(prompt))
            guard count + MissingInformationPrompts.responseTokens + 128 <= model.contextSize else { throw GapPlanError.contextLimit }
            try Task.checkCancellation()
            await observer?(.began(id: "gap", title: "Infer what the notes are missing", instructions: instructions, input: prompt))
            try Task.checkCancellation()
            let response = try await LanguageModelSession(model: model, instructions: instructions).respond(to: prompt,
                generating: ContextualGapReferences.self,
                options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: MissingInformationPrompts.responseTokens))
            try Task.checkCancellation()
            let bound = response.content
            let subjects = try bound.subjects(in: transcript)
            let explicitOperation = bound.targets.count == 1 ? GapHeadingRequest.inspect(bound.targets[0].quote)?.operation : nil
            let proposed = MissingInformationPlan(alreadyCovered: bound.alreadyCovered, targets: bound.targets,
                informationNeeds: bound.informationNeeds, operation: explicitOperation ?? .continueThought, subjects: subjects,
                completionGoal: "supply \(bound.informationNeeds.joined(separator: ", ")) for \(subjects.map(\.quote).joined(separator: " and "))")
            let gap: ValidatedGapPlan
            do { gap = try ValidatedGapPlan.validate(proposed, in: transcript) }
            catch let error as GapPlanError { throw RejectedGapPlan(proposed: proposed, reason: error, preliminaryIntent: preliminary.intent) }
            await observer?(.completed(id: "gap", summary: gap.intent + "\nNeeds: " + gap.value.informationNeeds.joined(separator: ", ")))
            return CirclePlan(intent: gap.intent, action: gap.action, evidence: gap.targetText, clarification: "", gap: gap,
                inputTokens: count, responseTokenLimit: IntentPrompts.intentTokenLimit + MissingInformationPrompts.responseTokens,
                planningPasses: 2, preliminaryIntent: preliminary.intent, bindingStrategy: "contextualInference")
        }
    }
}
