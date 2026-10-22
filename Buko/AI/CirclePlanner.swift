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
            let needs: [String]
            let format: String
            switch binding.operation {
            case .define: needs = ["definition"]; format = "definition"
            case .compare: needs = ["difference"]; format = "comparison"
            default: return nil
            }
            let gap = try ValidatedGapPlan.validate(binding.plan(needs: needs), in: transcript)
            let target = gap.targetText.hasSuffix(":") ? String(gap.targetText.dropLast()) : gap.targetText
            return CirclePlan(intent: "The user wants to \(binding.operation.verb) \(target).",
                action: "Add a concise \(format) beneath \(target).", evidence: gap.targetText, clarification: "",
                gap: mode == .structuredGap ? gap : nil, inputTokens: nil, responseTokenLimit: 0,
                planningPasses: 0, preliminaryIntent: nil, bindingStrategy: "explicitSyntax")
        }
    }

    @available(iOS 27, macOS 27, *)
    static func infer(selected: String, context: String, mode: CircleRetrievalMode,
                      model: SystemLanguageModel = .default) async throws -> CirclePlan {
        try Task.checkCancellation()
        guard ![selected, context].contains(where: LectureGroundingPolicy.containsInstructionOverride) else {
            throw GapPlanError.instructionRisk
        }
        let transcript = GapTranscript(selected: selected, context: context)
        if let explicit = try explicitPlan(in: transcript, mode: mode) { return explicit }
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
            // Freeform requests still use clarification followed by independently
            // validated target references. Explicit syntax returned above.
            let preliminary = try await infer(selected: selected, context: context, mode: .baseline, model: model)
            if !preliminary.clarification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return CirclePlan(intent: preliminary.intent, action: preliminary.action, evidence: preliminary.evidence,
                    clarification: preliminary.clarification, gap: nil, inputTokens: nil,
                    responseTokenLimit: IntentPrompts.intentTokenLimit, planningPasses: 1, preliminaryIntent: preliminary.intent)
            }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let blocks = try JSONSerialization.jsonObject(with: encoder.encode(transcript.blocks))
            let fields: [String: Any] = ["blocks": blocks]
            let prompt = String(decoding: try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]), as: UTF8.self)
            let instructions = MissingInformationPrompts.instructions
            let instructionCount = try await model.tokenCount(for: Instructions(instructions))
            let schemaCount = try await model.tokenCount(for: MissingInformationPlan.generationSchema)
            let promptCount = try await model.tokenCount(for: Prompt(prompt))
            let count = instructionCount + schemaCount + promptCount
            guard count + MissingInformationPrompts.responseTokens + 128 <= model.contextSize else {
                throw GapPlanError.contextLimit
            }
            try Task.checkCancellation()
            let session = LanguageModelSession(model: model, instructions: instructions)
            let response = try await session.respond(to: prompt, generating: MissingInformationPlan.self,
                options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: MissingInformationPrompts.responseTokens))
            let proposed = response.content
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
                bindingStrategy: "modelReferences")
        }
    }
}
