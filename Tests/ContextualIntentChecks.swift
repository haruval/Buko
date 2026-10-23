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
        var excludedNeeds: [String] = []
        var expectedTargets: [String] = []
        var clarificationSubjects: [String] = []
        var evidence: [String] = []
        var draftTerms: [String] = []
    }
    static let fixtures: [Fixture] = [
        .init(id: "instance-after-definition", selected: "A closure keeps its captured variables after the outer function returns.\nOne tiny program would make this easier to see.", context: "", needs: ["instance", "example", "program", "illustration"], subjects: ["closure"]),
        .init(id: "pronoun-instance", selected: "What would that look like in a small program?", context: "A closure pairs a function with its captured lexical environment.", excludedSubjects: ["program"], needs: ["instance", "example", "program", "illustration"], subjects: ["closure"]),
        .init(id: "picture-instance", selected: "The definition makes sense, but I can't picture one.", context: "A closure stores a function and its lexical environment, even after return.", needs: ["instance", "example", "illustration"], subjects: ["closure"]),
        .init(id: "causal-continuation", selected: "It keeps working after the creating function returns because", context: "A closure retains its captured variables.", needs: ["reason", "mechanism", "why"], subjects: ["closure"]),
        .init(id: "sequence-continuation", selected: "First turn the characters into tokens. Then", context: "Compiler front end: lexical analysis, parsing, semantic analysis.", needs: ["next", "subsequent", "parsing"], subjects: ["parsing|compiler"]),
        .init(id: "implicit-comparison", selected: "Both find variable bindings, but they differ in", context: "Static scoping follows lexical nesting. Dynamic scoping follows the calling sequence.", needs: ["differ", "contrast", "comparison", "mechanism", "lookup"], subjects: ["static", "dynamic"]),
        .init(id: "pattern-completion", selected: "Condensation changes vapor into liquid. A cold glass gets wet.\nEvaporation changes liquid into vapor.", context: "Pair each process with an everyday situation that shows it happening.", excludedSubjects: ["condensation"], needs: ["instance", "example", "situation"], subjects: ["evaporation"], expectedTargets: ["Evaporation"], evidence: ["Evaporation changes liquid into vapor. For example, a wet towel dries as liquid water evaporates into the air.", "Condensation changes vapor into liquid. A cold glass gets wet when water vapor condenses on it."], draftTerms: ["towel", "water"]),
        .init(id: "tradeoff", selected: "Caching avoids repeated work. The catch is", context: "Caching stores computed results for reuse.", needs: ["limitation", "drawback", "tradeoff", "cost", "disadvantage"], subjects: ["caching"]),
        .init(id: "paraphrased-cause", selected: "I understand what synchronization does, but not what makes it necessary.", context: "Synchronization coordinates concurrent access to shared state.", needs: ["reason", "necess", "motivation", "cause"], subjects: ["synchronization"]),
        .init(id: "explicit-question-control", selected: "What does parsing check?", context: "Lexical analysis groups characters into tokens.", needs: ["check", "verif", "grammar", "syntax", "purpose", "function"], subjects: ["parsing"]),
        .init(id: "unknown-fact-control", selected: "How many chambers does Luma have?", context: "", needs: ["count", "number", "chamber"], subjects: ["luma"]),
        .init(id: "completed-note-ambiguous", selected: "A closure captures variables from its lexical environment.", context: "", needs: [], subjects: [], clarify: true),
        .init(id: "ambiguous-referent", selected: "What would that look like in practice?", context: "Closures capture lexical variables. Semaphores coordinate access to a shared resource.", needs: [], subjects: [], clarify: true, clarificationSubjects: ["closure", "semaphore"]),
        .init(id: "pronoun-recursion", selected: "What would that look like in a small program?", context: "Recursion occurs when a function calls itself.", excludedSubjects: ["program"], needs: ["instance", "example", "program", "illustration"], subjects: ["recursion"], excludedNeeds: ["two self-calls", "loop"]),
        .init(id: "pronoun-semaphore", selected: "The definition makes sense, but I can't picture one.", context: "A semaphore coordinates access to a shared resource.", needs: ["instance", "example", "illustration"], subjects: ["semaphore"]),
        .init(id: "missing-operand", selected: "A = [1 ?; 3 4]. Find its determinant.", context: "", needs: [], subjects: [], clarify: true),
        .init(id: "ambiguous-reversed", selected: "What would that look like in practice?", context: "Semaphores coordinate access to a shared resource. Closures capture lexical variables.", needs: [], subjects: [], clarify: true, clarificationSubjects: ["closure", "semaphore"]),
        .init(id: "collective-reference", selected: "What would both look like in practice?", context: "Closures capture lexical variables. Semaphores coordinate access to a shared resource.", needs: ["instance", "example", "illustration", "practice"], subjects: ["closure", "semaphore"]),
        .init(id: "disambiguated-reference", selected: "For the second concept, what would that look like in practice?", context: "Closures capture lexical variables.\nSemaphores coordinate access to a shared resource.", excludedSubjects: ["closure"], needs: ["instance", "example", "illustration", "practice"], subjects: ["semaphore"]),
        .init(id: "comparison-reversed", selected: "They both find variable bindings. The difference is", context: "Dynamic scoping follows the calling sequence. Static scoping follows lexical nesting.", needs: ["difference", "contrast", "comparison", "lookup"], subjects: ["static", "dynamic"]),
        .init(id: "comparison-transfer", selected: "Both transport data, but they differ in delivery", context: "TCP and UDP are transport protocols.", needs: ["difference", "contrast", "comparison", "delivery"], subjects: ["tcp", "udp"], evidence: ["TCP provides an ordered, reliable byte stream.", "UDP provides datagrams without guaranteed delivery or ordering."], draftTerms: ["tcp", "udp", "reliable|guarantee", "order"]),
        .init(id: "pattern-reversed", selected: "Evaporation changes liquid into vapor.\nCondensation changes vapor into liquid. A cold glass gets wet.", context: "Pair each process with an everyday situation that shows it happening.", excludedSubjects: ["condensation"], needs: ["instance", "example", "situation"], subjects: ["evaporation"], expectedTargets: ["Evaporation"]),
        .init(id: "pattern-swapped", selected: "Evaporation changes liquid into vapor. A wet towel dries.\nCondensation changes vapor into liquid.", context: "Pair each process with an everyday situation that shows it happening.", excludedSubjects: ["evaporation"], needs: ["instance", "example", "situation"], subjects: ["condensation"], expectedTargets: ["Condensation"]),
        .init(id: "pattern-transfer", selected: "A conductor lets current flow. Copper wiring carries current in a lamp.\nAn insulator resists current flow.", context: "Give a use alongside each meaning.", excludedSubjects: ["conductor"], needs: ["use", "application", "instance", "example"], subjects: ["insulator"], expectedTargets: ["insulator"], evidence: ["An insulator resists electrical current. Rubber insulation around a wire helps prevent current from passing to a person touching the wire."], draftTerms: ["rubber", "wire"]),
        .init(id: "complete-pattern", selected: "Evaporation changes liquid into vapor. A wet towel dries.\nCondensation changes vapor into liquid. A cold glass gets wet.", context: "Pair each process with an everyday situation that shows it happening.", needs: [], subjects: [], clarify: true)
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
                if let gap = result.gap {
                    let need = gap.expansion.lowercased()
                    passed = passed && !item.excludedNeeds.contains(where: { need.contains($0) })
                        && item.expectedTargets.allSatisfy { gap.targetText.localizedCaseInsensitiveContains($0) }
                }
                passed = passed && item.clarificationSubjects.allSatisfy { result.clarification.localizedCaseInsensitiveContains($0) }
                record["planPassed"] = passed
                let pipelineCase = ["instance-after-definition", "pronoun-instance", "picture-instance",
                    "causal-continuation", "implicit-comparison", "explicit-question-control"].contains(item.id) || !item.evidence.isEmpty
                if args.contains("--pipeline"), pipelineCase, let gap = result.gap {
                    let search: LectureSearch
                    if item.evidence.isEmpty {
                        search = try await library.search(noteID: noteID, selected: item.selected, intent: result.intent, gap: gap)
                    } else {
                        let passages = item.evidence.enumerated().map { LecturePassage(id: "fixture-\($0.offset)", documentID: "fixture", title: "Development lecture", page: $0.offset + 1, text: $0.element, usedOCR: false, vector: nil) }
                        let hits = GapRetrieval.search(passages: passages, selected: item.selected, intent: result.intent,
                            originalVector: nil, targetVector: nil, gap: gap, method: .lexical).hits
                        search = LectureSearch(hits: hits, documentCount: 1, revision: "fixture", semanticAvailable: false, seconds: 0, gapPlan: gap)
                    }
                    let evidence = try await LectureComposer.complete(selected: item.selected, context: item.context,
                        intent: result.intent, action: result.action, search: search, observer: observer)
                    let draft = try await AutofillWriter.draft(selected: item.selected, context: item.context, intent: result.intent,
                        action: result.action, gap: gap.value, evidence: evidence, search: search, observer: observer)
                    record["draft"] = draft.content?.text ?? draft.explanation
                    record["draftReady"] = draft.content != nil
                    record["sourcePages"] = evidence.citations.map { $0.passage.page }
                    passed = passed && draft.content != nil
                    if let text = draft.content?.text {
                        passed = passed && !AutofillWriter.repeatsExistingText([text], selected: item.selected, context: item.context)
                            && item.draftTerms.allSatisfy { alternatives in
                                alternatives.split(separator: "|").contains { text.localizedCaseInsensitiveContains($0) }
                            }
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
