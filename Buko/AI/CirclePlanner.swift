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

/// Shared by the app and benchmark. Baseline retains its original prompt,
/// schema, greedy sampling and output cap. Never silently falls back between modes.
nonisolated enum CirclePlanner {
    @available(iOS 27, macOS 27, *)
    static func infer(selected: String, context: String, mode: CircleRetrievalMode,
                      model: SystemLanguageModel = .default) async throws -> CirclePlan {
        try Task.checkCancellation()
        guard ![selected, context].contains(where: LectureGroundingPolicy.containsInstructionOverride) else {
            throw GapPlanError.instructionRisk
        }
        switch mode {
        case .baseline:
            let session = LanguageModelSession(model: model, instructions: IntentPrompts.instructions)
            let response = try await session.respond(to: IntentPrompts.request(selected: selected, context: context),
                generating: InferredCircleIntent.self,
                options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: IntentPrompts.intentTokenLimit))
            try Task.checkCancellation()
            return CirclePlan(intent: response.content.intent, action: response.content.action,
                evidence: response.content.evidence, clarification: response.content.clarification,
                gap: nil, inputTokens: nil, responseTokenLimit: IntentPrompts.intentTokenLimit,
                planningPasses: 1, preliminaryIntent: nil)
        case .structuredGap:
            // Keep the established clarification pass. Bind targets independently:
            // a mistaken preliminary intent must not override the actual text.
            // The benchmark retains that hypothesis and reports both calls/cost.
            let preliminary = try await infer(selected: selected, context: context, mode: .baseline, model: model)
            if !preliminary.clarification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return CirclePlan(intent: preliminary.intent, action: preliminary.action, evidence: preliminary.evidence,
                    clarification: preliminary.clarification, gap: nil, inputTokens: nil,
                    responseTokenLimit: IntentPrompts.intentTokenLimit, planningPasses: 1, preliminaryIntent: preliminary.intent)
            }
            let transcript = GapTranscript(selected: selected, context: context)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let blocks = try JSONSerialization.jsonObject(with: encoder.encode(transcript.blocks))
            var fields: [String: Any] = ["blocks": blocks]
            let binding: GapSyntaxBinding.Binding?
            switch GapSyntaxBinding.inspect(transcript) {
            case .bound(let value): binding = value
            case .unconstrained: binding = nil
            case .ambiguousHeadings:
                return CirclePlan(intent: preliminary.intent, action: preliminary.action, evidence: preliminary.evidence,
                    clarification: "Which heading should I complete? Circle one heading, or write an explicit comparison.",
                    gap: nil, inputTokens: nil, responseTokenLimit: IntentPrompts.intentTokenLimit,
                    planningPasses: 1, preliminaryIntent: preliminary.intent, bindingStrategy: "ambiguousHeadings")
            }
            if let binding { fields["binding"] = try JSONSerialization.jsonObject(with: encoder.encode(binding)) }
            let prompt = String(decoding: try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]), as: UTF8.self)
            let instructions = binding == nil ? MissingInformationPrompts.instructions : MissingInformationPrompts.boundInstructions
            let instructionCount = try await model.tokenCount(for: Instructions(instructions))
            let schema = binding == nil ? MissingInformationPlan.generationSchema : BoundInformationNeeds.generationSchema
            let schemaCount = try await model.tokenCount(for: schema)
            let promptCount = try await model.tokenCount(for: Prompt(prompt))
            let count = instructionCount + schemaCount + promptCount
            guard count + MissingInformationPrompts.responseTokens + 128 <= model.contextSize else {
                throw GapPlanError.contextLimit
            }
            try Task.checkCancellation()
            let session = LanguageModelSession(model: model, instructions: instructions)
            let proposed: MissingInformationPlan
            if let binding {
                let response = try await session.respond(to: prompt, generating: BoundInformationNeeds.self,
                    options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: MissingInformationPrompts.responseTokens))
                proposed = binding.plan(needs: response.content.informationNeeds)
            } else {
                let response = try await session.respond(to: prompt, generating: MissingInformationPlan.self,
                    options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: MissingInformationPrompts.responseTokens))
                proposed = response.content
            }
            try Task.checkCancellation()
            let gap: ValidatedGapPlan
            do { gap = try ValidatedGapPlan.validate(proposed, in: transcript) }
            catch let error as GapPlanError {
                throw RejectedGapPlan(proposed: proposed, reason: error, preliminaryIntent: preliminary.intent)
            }
            return CirclePlan(intent: gap.intent, action: gap.action, evidence: gap.targetText,
                clarification: "", gap: gap,
                inputTokens: count, responseTokenLimit: IntentPrompts.intentTokenLimit + MissingInformationPrompts.responseTokens,
                planningPasses: 2, preliminaryIntent: preliminary.intent,
                bindingStrategy: binding == nil ? "modelReferences" : "explicitSyntax")
        }
    }
}
