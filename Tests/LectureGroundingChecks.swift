import Foundation
import FoundationModels

/// Optional live-model evaluation. Never returns fixture text as a model response.
@main struct LectureGroundingChecks {
    @MainActor static func main() async throws {
        guard #available(macOS 27, *), case .available = SystemLanguageModel.default.availability else {
            print("SKIPPED: the local Apple Foundation Model is unavailable."); return
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[2])
        let library = LectureLibrary(root: root)
        let noteID = UUID()
        for course in ["programmingLanguages", "operatingSystems", "linearAlgebra", "biology101"] {
            try await library.importPDF(from: fixtures.appendingPathComponent(course + ".pdf"), noteID: noteID)
        }
        for (selected, context) in [
            ("Static scope:", "Dynamic scope follows the calling sequence."),
            ("Why repeat an experiment?", "Evidence can support or challenge a hypothesis."),
            ("C = [2 1; 0 3], D = [1 4; 2 0]. CD =", "")
        ] {
            let started = ProcessInfo.processInfo.systemUptime
            let planner = LanguageModelSession(instructions: IntentPrompts.instructions)
            let plan = try await planner.respond(to: IntentPrompts.request(selected: selected, context: context),
                generating: InferredCircleIntent.self, options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 420))
            precondition(plan.content.clarification.isEmpty, "Unexpected planner clarification: \(plan.content.clarification)")
            let search = try await library.search(noteID: noteID, selected: selected, intent: plan.content.intent)
            precondition(!search.hits.isEmpty)
            let result = try await LectureComposer.complete(selected: selected, context: context, intent: plan.content.intent,
                action: plan.content.action, search: search)
            precondition(!result.lines.isEmpty && result.lines.count == result.citations.count,
                         "No answer for \(selected). \(result.explanation). Retrieved: \(search.hits.map { $0.passage.text })")
            for citation in result.citations {
                precondition(CitationValidation.citation(sourceID: citation.passage.id, quote: citation.quote, hits: search.hits) != nil)
            }
            print("QUERY: \(selected)\nINTENT: \(plan.content.intent)\nEXTRACTIVE: \(result.extractive)\n\(result.lines.joined(separator: "\n"))")
            print("CITATIONS: \(result.citations.map { $0.passage.title + ":\($0.passage.page)" }); seconds: \(ProcessInfo.processInfo.systemUptime - started)")
        }
        // Counterfactual evidence probes reliance on supplied sources instead of pretraining.
        let passage = LecturePassage(id: "counterfactual:1", documentID: "counterfactual", title: "Fictional laboratory handout", page: 1,
            text: "For this fictional laboratory exercise, the sample called Luma has exactly seven chambers. The instructor labels its outer layer cerulean. These are invented properties for the exercise, not claims about real organisms.", usedOCR: false, vector: nil)
        let hit = LectureHit(passage: passage, lexicalScore: 1, semanticScore: 0, score: 1)
        let search = LectureSearch(hits: [hit], documentCount: 1, revision: "test", semanticAvailable: false, seconds: 0)
        let result = try await LectureComposer.complete(selected: "Luma chamber count:", context: "", intent: "Complete the fictional Luma sample's chamber count.",
            action: "State the chamber count.", search: search)
        precondition(!result.lines.isEmpty && result.lines.joined().lowercased().contains("seven"))
        print("Counterfactual source check passed: \(result.lines.joined(separator: " "))")
        let absent = try await LectureComposer.complete(selected: "What is the instructor's private phone number?", context: "", intent: "Find a phone number.",
            action: "Provide the number.", search: search)
        precondition(absent.lines.isEmpty || absent.extractive, "Unsupported evidence must not become a generated answer")
        print("Insufficient-evidence check passed: \(absent.explanation)")
        print("Live on-device grounding checks passed.")
    }
}
