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

    /// The planner owns this boundary now that circles have a single purpose.
    /// Do not silently truncate a selection or promote nearby text into its place.
    static func checkInput(selected: String, context: String) throws {
        guard !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GapPlanError.invalidReferences("emptySelection")
        }
        guard selected.count <= IntentPrompts.selectedCharacterLimit,
              context.count <= IntentPrompts.contextCharacterLimit else { throw GapPlanError.contextLimit }
        guard ![selected, context].contains(where: LectureGroundingPolicy.containsInstructionOverride) else {
            throw GapPlanError.instructionRisk
        }
    }

    @available(iOS 27, macOS 27, *)
    static func infer(selected: String, context: String, mode: CircleRetrievalMode = .structuredGap,
                      model: SystemLanguageModel = .default, observer: PipelineObserver? = nil) async throws -> CirclePlan {
        try Task.checkCancellation()
        try checkInput(selected: selected, context: context)
        let transcript = GapTranscript(selected: selected, context: context)
        if let explicit = try explicitPlan(in: transcript, mode: mode) {
            await observer?(.began(id: "binding", title: "Identify the unfinished heading", instructions: nil, input: selected))
            try Task.checkCancellation()
            await observer?(.completed(id: "binding", summary: "Local syntax check · no model call\n" + explicit.intent + "\n" + explicit.clarification))
            try Task.checkCancellation()
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
            var candidate = response.content
            if let question = transcript.question, !candidate.subjectQuotes.isEmpty {
                candidate.targets = question.targets
                candidate.informationNeeds = [question.text]
                let questionIDs = Set(question.targets.map(\.blockID))
                candidate.alreadyCovered.removeAll { questionIDs.contains($0.blockID) }
            }
            await observer?(.completed(id: "gap", summary: String(decoding: try encoder.encode(candidate), as: UTF8.self)))
            var checked = try await checkCandidate(candidate, transcript: transcript, model: model, observer: observer)
            var calls = 2 + checked.calls
            var tokens = IntentPrompts.intentTokenLimit + MissingInformationPrompts.responseTokens + checked.responseTokens
            if checked.canRepair {
                let instructions = checked.questionReferenceRepair
                    ? QuestionReferenceRepair.instructions : GroundedReferenceRepair.instructions
                let repairTokens = checked.questionReferenceRepair
                    ? QuestionReferenceRepair.responseTokens : GroundedReferenceRepair.responseTokens
                let request = String(decoding: try encoder.encode(transcript.blocks), as: UTF8.self)
                let repairSchema = checked.questionReferenceRepair
                    ? QuestionReferenceRepair.generationSchema : GroundedReferenceRepair.generationSchema
                let repairCount = try await model.tokenCount(for: Instructions(instructions))
                    + model.tokenCount(for: repairSchema) + model.tokenCount(for: Prompt(request))
                guard repairCount + repairTokens + 128 <= model.contextSize else { throw GapPlanError.contextLimit }
                await observer?(.began(id: "referenceRepair", title: "Re-anchor the inferred references", instructions: instructions, input: request))
                try Task.checkCancellation()
                let repair: GroundedReferenceRepair
                if checked.questionReferenceRepair, let question = transcript.blocks.first(where: \.selected) {
                    let response = try await LanguageModelSession(model: model, instructions: instructions).respond(to: request,
                        generating: QuestionReferenceRepair.self,
                        options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: repairTokens)).content
                    repair = GroundedReferenceRepair(targetQuotes: [question.text], subjectQuotes: response.subjectQuotes,
                        informationNeed: question.text, coveredQuotes: [])
                } else {
                    repair = try await LanguageModelSession(model: model, instructions: instructions).respond(to: request,
                        generating: GroundedReferenceRepair.self,
                        options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: repairTokens)).content
                }
                try Task.checkCancellation()
                calls += 1; tokens += repairTokens
                await observer?(.completed(id: "referenceRepair", summary: String(decoding: try encoder.encode(repair), as: UTF8.self)))
                try Task.checkCancellation()
                if let anchored = try? repair.anchored(in: transcript) {
                    // Exactly one repair. It cannot bypass scope or final grounding.
                    let repairObserver: PipelineObserver = { event in
                        switch event {
                        case let .began(id, title, instructions, input):
                            await observer?(.began(id: "referenceRepair." + id, title: title, instructions: instructions, input: input))
                        case let .completed(id, summary):
                            await observer?(.completed(id: "referenceRepair." + id, summary: summary))
                        }
                    }
                    checked = try await checkCandidate(anchored, transcript: transcript, model: model, observer: repairObserver, explainScope: true)
                    calls += checked.calls; tokens += checked.responseTokens
                }
            }
            try Task.checkCancellation()
            if let gap = checked.gap {
                return CirclePlan(intent: gap.intent, action: gap.action, evidence: gap.targetText, clarification: "", gap: gap,
                    inputTokens: count, responseTokenLimit: tokens, planningPasses: calls,
                    preliminaryIntent: preliminary.intent, bindingStrategy: "reviewedContextualInference")
            }
            return CirclePlan(intent: preliminary.intent, action: "Clarify the intended addition before retrieving evidence.",
                evidence: "", clarification: checked.question, gap: nil, inputTokens: count,
                responseTokenLimit: tokens, planningPasses: calls, preliminaryIntent: preliminary.intent,
                bindingStrategy: "contextualClarification")
        }
    }

    private struct CandidateCheck {
        var gap: ValidatedGapPlan? = nil
        var question = "What would you like to add to the selected notes?"
        var canRepair = false
        var questionReferenceRepair = false
        var calls = 0
        var responseTokens = 0
    }

    @available(iOS 27, macOS 27, *)
    private static func checkCandidate(_ candidate: ContextualGapReferences, transcript: GapTranscript,
                                       model: SystemLanguageModel, observer: PipelineObserver?, explainScope: Bool = false) async throws -> CandidateCheck {
        let resolution = try await resolveScope(candidate, transcript: transcript, model: model, observer: observer, explainScope: explainScope)
        var result = CandidateCheck(calls: resolution.calls, responseTokens: resolution.responseTokens)
        if let question = resolution.question {
            result.question = question
            result.canRepair = resolution.unanchored && !candidate.targets.isEmpty && !candidate.informationNeeds.isEmpty
            return result
        }
        let bound = resolution.plan
        let subjects = try bound.subjects(in: transcript)
        let explicitOperation = bound.targets.count == 1 ? GapHeadingRequest.inspect(bound.targets[0].quote)?.operation : nil
        let questionOperation: GapOperation? = transcript.question.map { GapHeadingRequest.isExplanationQuestion($0.text) ? .explain : .continueThought }
        let proposed = MissingInformationPlan(alreadyCovered: bound.alreadyCovered, targets: bound.targets,
            informationNeeds: bound.informationNeeds, operation: explicitOperation ?? questionOperation ?? .continueThought, subjects: subjects,
            completionGoal: "supply \(bound.informationNeeds.joined(separator: ", ")) for \(subjects.map(\.quote).joined(separator: " and "))")
        do { result.gap = try ValidatedGapPlan.validate(proposed, in: transcript) }
        catch let error as GapPlanError {
            guard case .invalidReferences(let reason) = error else { throw error }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            await observer?(.began(id: "planValidation", title: "Check the inferred references", instructions: nil,
                input: String(decoding: try encoder.encode(proposed), as: UTF8.self)))
            await observer?(.completed(id: "planValidation", summary: "No validated addition: " + reason))
            // A selected question can be unanswered even when it is a complete
            // sentence. Reuse the one existing original-notes repair only when
            // no scope calls have been spent, preserving the six-call ceiling.
            result.canRepair = canRepairQuestionReferences(reason: reason, candidate: candidate,
                transcript: transcript, scopeCalls: result.calls)
            result.questionReferenceRepair = result.canRepair
        }
        return result
    }

    static func canRepairQuestionReferences(reason: String, candidate: ContextualGapReferences,
                                            transcript: GapTranscript, scopeCalls: Int) -> Bool {
        let selected = transcript.blocks.filter(\.selected)
        guard scopeCalls == 0, selected.count == 1, selected[0].text.count <= 120,
              transcript.selected.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?"),
              transcript.selected.filter({ $0 == "?" }).count == 1,
              !candidate.informationNeeds.isEmpty else { return false }
        return (reason == "fieldCount" && candidate.targets.isEmpty) || reason.hasPrefix("invalidSpan:")
    }

    private struct ScopeResolution {
        var plan: ContextualGapReferences
        var question: String? = nil
        var unanchored = false
        var calls = 0
        var responseTokens = 0
    }

    @available(iOS 27, macOS 27, *)
    private static func resolveScope(_ candidate: ContextualGapReferences, transcript: GapTranscript,
                                     model: SystemLanguageModel, observer: PipelineObserver?, explainScope: Bool) async throws -> ScopeResolution {
        var result = ScopeResolution(plan: candidate)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let subjects: [GapTextReference]
        do { subjects = try candidate.subjects(in: transcript) }
        catch let error as GapPlanError {
            guard case .invalidReferences(let reason) = error else { throw error }
            await observer?(.began(id: "planValidation", title: "Check the inferred references", instructions: nil,
                input: String(decoding: try encoder.encode(candidate), as: UTF8.self)))
            await observer?(.completed(id: "planValidation", summary: "Unanchored subject: " + reason))
            result.question = ContextualScopeChoice.unresolvedQuestion(in: transcript)
            result.unanchored = true
            return result
        }
        let notes = "Selected notes:\n" + transcript.selected + "\nNearby notes:\n" + transcript.context
        // A counterpart may be inferred only from text-grounded content-role pairs,
        // with one incomplete selected topic and a shared established pattern.
        let selectedBlocks = transcript.blocks.filter(\.selected)
        if transcript.question == nil && (2...4).contains(selectedBlocks.count) && subjects.contains(where: { $0.blockID.hasPrefix("S") }) {
            let request = String(decoding: try encoder.encode(transcript.blocks), as: UTF8.self)
            let instructions = ContextualScopePrompts.roles
            let count = try await model.tokenCount(for: Instructions(instructions))
                + model.tokenCount(for: GroundedPatternMap.generationSchema) + model.tokenCount(for: Prompt(request))
            guard count + 950 + 128 <= model.contextSize else { throw GapPlanError.contextLimit }
            await observer?(.began(id: "structure", title: "Check the pattern in the notes", instructions: instructions, input: request))
            try Task.checkCancellation()
            let pattern = try await LanguageModelSession(model: model, instructions: instructions).respond(to: request,
                generating: GroundedPatternMap.self, options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 950)).content
            let map = pattern.map
            try Task.checkCancellation()
            result.calls += 1; result.responseTokens += 950
            await observer?(.completed(id: "structure", summary: String(decoding: try encoder.encode(pattern), as: UTF8.self)))
            var mappedCandidate = candidate
            mappedCandidate.subjectQuotes = map.content.map(\.topic).reduce(into: [String]()) { names, name in
                if !names.contains(name) { names.append(name) }
            }
            if ContextualRoleMap.isComplete(map, candidate: mappedCandidate, in: transcript) {
                result.question = "These notes already supply the shared pattern. What would you like to add?"
                return result
            }
            if let focused = ContextualRoleMap.focus(map, candidate: mappedCandidate, in: transcript) {
                result.plan = focused
                return result
            }
        }
        guard subjects.count > 1 else { return result }
        let choices = ContextualScopeChoice.choices(subjects: subjects.map(\.quote))
        let namesRequestedTogether = candidate.targets.contains { target in
            subjects.allSatisfy { target.quote.localizedCaseInsensitiveContains($0.quote) }
        }
        let need = namesRequestedTogether ? candidate.informationNeeds.joined(separator: ", ") : "the requested content"
        let choiceText = choices.map { choice in
            let omitted = subjects.map(\.quote).filter { !choice.subjects.contains($0) }
            return "\(choice.id): Add \(need) for \(choice.subjects.joined(separator: " and "))"
                + (choice.subjects.count == 1 ? " alone" : " as the requested relationship involving ALL of these topics")
                + (omitted.isEmpty ? "." : ", omitting \(omitted.joined(separator: " and ")).")
        }.joined(separator: "\n")
        let request = notes + "\nPossible scopes:\n" + choiceText
            + "\nDo the student's words or the completed-versus-missing pattern distinguish ONE of these scopes from the other possibilities, without guessing?"
        let selectionInstructions = ContextualScopePrompts.choice
        let selectionRequest = explainScope ? request + "\nExplain the reference before selecting the uniquely supported candidate ID. Return NONE if there is no unique supported scope."
            : request + "\nReturn only the uniquely supported candidate ID, or NONE if there is no unique supported scope."
        let schemaTokens = explainScope ? try await model.tokenCount(for: GroundedScopeSelection.generationSchema) : 0
        let responseTokens = explainScope ? 250 : 40
        let selectionCount = try await model.tokenCount(for: Instructions(selectionInstructions)) + model.tokenCount(for: Prompt(selectionRequest)) + schemaTokens
        guard selectionCount + responseTokens + 128 <= model.contextSize else { throw GapPlanError.contextLimit }
        await observer?(.began(id: "scopeBinding", title: "Resolve the intended subjects", instructions: selectionInstructions, input: selectionRequest))
        try Task.checkCancellation()
        let session = LanguageModelSession(model: model, instructions: selectionInstructions)
        let id: String, summary: String
        if explainScope {
            let selection = try await session.respond(to: selectionRequest, generating: GroundedScopeSelection.self,
                options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: responseTokens)).content
            id = selection.scopeID.trimmingCharacters(in: .whitespacesAndNewlines)
            summary = selection.reasoning + "\n" + id
        } else {
            id = try await session.respond(to: selectionRequest,
                options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: responseTokens)).content.trimmingCharacters(in: .whitespacesAndNewlines)
            summary = id
        }
        try Task.checkCancellation()
        result.calls += 1; result.responseTokens += responseTokens
        await observer?(.completed(id: "scopeBinding", summary: summary))
        guard let choice = choices.first(where: { $0.id == id }) else {
            result.question = ContextualScopeChoice.question(subjects: subjects.map(\.quote)); return result
        }
        if choice.subjects.count > 1 {
            let instructions = CollectiveReference.instructions
            let request = "Selected text: " + transcript.selected
            let count = try await model.tokenCount(for: Instructions(instructions))
                + model.tokenCount(for: CollectiveReference.generationSchema) + model.tokenCount(for: Prompt(request))
            guard count + 120 + 128 <= model.contextSize else { throw GapPlanError.contextLimit }
            await observer?(.began(id: "scopeCue", title: "Ground the shared reference", instructions: instructions, input: request))
            try Task.checkCancellation()
            let cue = try await LanguageModelSession(model: model, instructions: instructions).respond(to: request,
                generating: CollectiveReference.self, options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 120)).content
            try Task.checkCancellation()
            result.calls += 1; result.responseTokens += 120
            await observer?(.completed(id: "scopeCue", summary: cue.selectedCue))
            guard cue.isGrounded(in: transcript.selected) else {
                result.question = ContextualScopeChoice.question(subjects: subjects.map(\.quote)); return result
            }
        }
        result.plan.subjectQuotes = choice.subjects
        if transcript.question == nil, choice.subjects.count == 1, let subject = subjects.first(where: { $0.quote == choice.subjects[0] }), subject.blockID.hasPrefix("S") {
            result.plan.targets = [subject]
        }
        // Preserve the user's actual relation instead of broadening an inferred
        // label into an additional technical requirement.
        if let question = transcript.question {
            result.plan.targets = question.targets
            result.plan.informationNeeds = [question.text]
        } else if choice.subjects.count > 1 {
            let selectedRequest = candidate.targets.map(\.quote).joined(separator: " ")
            if candidate.targets.count == 1, !selectedRequest.isEmpty, selectedRequest.count <= 120,
               !subjects.contains(where: { $0.quote == selectedRequest }) {
                result.plan.informationNeeds = [selectedRequest]
            }
        }
        return result
    }

}
