import Foundation
import FoundationModels
import Darwin

/// Development transcript replays using the actual local model. These are not
/// handwriting-recognition tests, held-out accuracy, or iPad latency measures.
@main struct ContextualIntentChecks {
    actor Recorder {
        var trace = PipelineTrace()
        func receive(_ event: PipelineEvent) { trace.receive(event) }
    }
    struct Fixture {
        let id: String
        let selected: String
        let context: String
        var excludedSubjects: [String] = []
        let needs: [String]
        let subjects: [String]
        var clarify = false
    }
    static let fixtures: [Fixture] = [
        .init(id: "instance-after-definition", selected: "A closure keeps its captured variables after the outer function returns.\nOne tiny program would make this easier to see.", context: "", needs: ["instance", "example", "program", "illustration"], subjects: ["closure"]),
        .init(id: "pronoun-instance", selected: "What would that look like in a small program?", context: "A closure pairs a function with its captured lexical environment.", needs: ["instance", "example", "program", "illustration"], subjects: ["closure"]),
        .init(id: "picture-instance", selected: "The definition makes sense, but I can't picture one.", context: "A closure stores a function and its lexical environment, even after return.", needs: ["instance", "example", "illustration"], subjects: ["closure"]),
        .init(id: "causal-continuation", selected: "It keeps working after the creating function returns because", context: "A closure retains its captured variables.", needs: ["reason", "mechanism", "why"], subjects: ["closure"]),
        .init(id: "sequence-continuation", selected: "First turn the characters into tokens. Then", context: "Compiler front end: lexical analysis, parsing, semantic analysis.", needs: ["next", "subsequent", "parsing"], subjects: ["parsing|compiler"]),
        .init(id: "implicit-comparison", selected: "Both find variable bindings, but they differ in", context: "Static scoping follows lexical nesting. Dynamic scoping follows the calling sequence.", needs: ["difference", "contrast", "comparison", "mechanism", "lookup"], subjects: ["static", "dynamic"]),
        .init(id: "pattern-completion", selected: "Condensation changes vapor into liquid. A cold glass gets wet.\nEvaporation changes liquid into vapor.", context: "Pair each process with an everyday situation that shows it happening.", excludedSubjects: ["condensation"], needs: ["instance", "example", "situation"], subjects: ["evaporation"]),
        .init(id: "tradeoff", selected: "Caching avoids repeated work. The catch is", context: "Caching stores computed results for reuse.", needs: ["limitation", "drawback", "tradeoff", "cost", "disadvantage"], subjects: ["caching"]),
        .init(id: "paraphrased-cause", selected: "I understand what synchronization does, but not what makes it necessary.", context: "Synchronization coordinates concurrent access to shared state.", needs: ["reason", "necess", "motivation", "cause"], subjects: ["synchronization"]),
        .init(id: "explicit-question-control", selected: "What does parsing check?", context: "Lexical analysis groups characters into tokens.", needs: ["check", "verif", "grammar", "syntax", "purpose", "function"], subjects: ["parsing"]),
        .init(id: "unknown-fact-control", selected: "How many chambers does Luma have?", context: "", needs: ["count", "number", "chamber"], subjects: ["luma"]),
        .init(id: "completed-note-ambiguous", selected: "A closure captures variables from its lexical environment.", context: "", needs: [], subjects: [], clarify: true),
        .init(id: "ambiguous-referent", selected: "What would that look like in practice?", context: "Closures capture lexical variables. Semaphores coordinate access to a shared resource.", needs: [], subjects: [], clarify: true),
        .init(id: "pronoun-recursion", selected: "What would that look like in a small program?", context: "Recursion occurs when a function calls itself.", needs: ["instance", "example", "program", "illustration"], subjects: ["recursion"]),
        .init(id: "pronoun-semaphore", selected: "The definition makes sense, but I can't picture one.", context: "A semaphore coordinates access to a shared resource.", needs: ["instance", "example", "illustration"], subjects: ["semaphore"]),
        .init(id: "missing-operand", selected: "A = [1 ?; 3 4]. Find its determinant.", context: "", needs: [], subjects: [], clarify: true)
    ]

    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        let args = CommandLine.arguments
        func option(_ name: String) -> String? {
            guard let index = args.firstIndex(of: name), args.indices.contains(index + 1) else { return nil }
            return args[index + 1]
        }
        guard #available(macOS 27, *), case .available = SystemLanguageModel.default.availability else {
            print("SKIPPED: local model unavailable"); exit(77)
        }
        let output = URL(fileURLWithPath: option("--output") ?? "/private/tmp/BukoContextualIntent.json")
        let subset = option("--case")?.split(separator: ",").map(String.init)
        let selectedFixtures = fixtures.filter { subset == nil || subset!.contains($0.id) }
        precondition(!selectedFixtures.isEmpty)
        let libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("BukoContextualPipeline-" + UUID().uuidString)
        let library = LectureLibrary(root: libraryRoot)
        let noteID = UUID()
        defer { try? FileManager.default.removeItem(at: libraryRoot) }
        if args.contains("--pipeline") {
            try await library.importPDF(from: URL(fileURLWithPath: "Buko/Resources/Lectures/programmingLanguages.pdf"), noteID: noteID)
        }
        var records: [[String: Any]] = []
        for item in selectedFixtures {
            var record: [String: Any] = ["id": item.id, "selected": item.selected, "context": item.context]
            let recorder = Recorder()
            let observer: PipelineObserver = { event in await recorder.receive(event) }
            let started = ProcessInfo.processInfo.systemUptime
            do {
                // Every positive case must exercise inference, not syntax binding.
                let explicit = try CirclePlanner.explicitPlan(in: GapTranscript(selected: item.selected, context: item.context), mode: .structuredGap)
                precondition(explicit == nil)
                let result = try await CirclePlanner.infer(selected: item.selected, context: item.context, observer: observer)
                record["intent"] = result.intent
                record["clarification"] = result.clarification
                record["planningPasses"] = result.planningPasses
                record["bindingStrategy"] = result.bindingStrategy ?? ""
                if let gap = result.gap {
                    record["gap"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(gap.value))
                    record["query"] = gap.retrievalText
                }
                let query = result.gap?.retrievalText.lowercased() ?? ""
                var passed = item.clarify ? !result.clarification.isEmpty && result.gap == nil
                    : result.clarification.isEmpty && result.gap.map { gap in
                        let need = gap.value.informationNeeds.joined(separator: " ").lowercased()
                        return item.needs.contains(where: { need.contains($0) })
                    } == true && item.subjects.allSatisfy { alternatives in
                        alternatives.split(separator: "|").contains { query.contains($0) }
                    } && !item.excludedSubjects.contains(where: { query.contains($0) })
                if args.contains("--pipeline"), ["instance-after-definition", "pronoun-instance", "picture-instance",
                    "causal-continuation", "implicit-comparison", "explicit-question-control"].contains(item.id), let gap = result.gap {
                    let search = try await library.search(noteID: noteID, selected: item.selected, intent: result.intent, gap: gap)
                    let evidence = try await LectureComposer.complete(selected: item.selected, context: item.context,
                        intent: result.intent, action: result.action, search: search, observer: observer)
                    let draft = try await AutofillWriter.draft(selected: item.selected, context: item.context, intent: result.intent,
                        action: result.action, gap: gap.value, evidence: evidence, search: search, observer: observer)
                    record["draft"] = draft.content?.text ?? draft.explanation
                    record["sourcePages"] = evidence.citations.map { $0.passage.page }
                    passed = passed && draft.content != nil
                    if let text = draft.content?.text {
                        passed = passed && !AutofillWriter.repeatsExistingText([text], selected: item.selected, context: item.context)
                    }
                    if ["instance-after-definition", "pronoun-instance", "picture-instance"].contains(item.id) {
                        passed = passed && draft.content?.text.lowercased().contains("makeadder") == true
                        let definition = LecturePassage(id: "definition", documentID: "test", title: "Definition only", page: 1,
                            text: "A closure pairs a function with its captured lexical environment.", usedOCR: false, vector: nil)
                        let negativeSearch = LectureSearch(hits: [.init(passage: definition, lexicalScore: 1, semanticScore: 0, score: 1)],
                            documentCount: 1, revision: "test", semanticAvailable: false, seconds: 0, gapPlan: gap)
                        let negative = try await LectureComposer.complete(selected: item.selected, context: item.context,
                            intent: result.intent, action: result.action, search: negativeSearch)
                        passed = passed && !negative.extractive
                        record["definitionOnlyRefused"] = !negative.extractive
                    }
                    print("DRAFT \(item.id): \(record["draft"]!)")
                }
                record["passed"] = passed
            } catch {
                record["passed"] = false
                record["error"] = String(describing: error)
            }
            record["seconds"] = ProcessInfo.processInfo.systemUptime - started
            record["trace"] = await recorder.trace.steps.map { ["id": $0.id, "input": $0.input, "summary": $0.summary] }
            records.append(record)
            try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
            print("\(record["passed"] as? Bool == true ? "PASS" : "FAIL") \(item.id): \(record["intent"] ?? record["error"] ?? "") · query=\(record["query"] ?? "") · clarification=\(record["clarification"] ?? "")")
        }
        let count = records.filter { $0["passed"] as? Bool == true }.count
        print("Contextual intent: \(count)/\(records.count). Report: \(output.path)")
        if count != records.count { exit(1) }
    }
}
