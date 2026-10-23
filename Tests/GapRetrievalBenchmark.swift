import Foundation
import FoundationModels
import CoreGraphics
import CoreText
import CryptoKit
import Darwin

/// Real local-model paired experiment, not a quality regression test. Nonzero
/// failures are retained in the report; no fabricated model responses or gold queries.
@main struct GapRetrievalBenchmark {
    struct StageFailure: Error {
        let record: [String: Any]
        let underlying: Error
    }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func json<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: [.fragmentsAllowed])
    }

    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        let args = CommandLine.arguments
        func option(_ name: String) -> String? {
            guard let index = args.firstIndex(of: name), args.indices.contains(index + 1) else { return nil }
            return args[index + 1]
        }
        guard let fixturePath = option("--fixture"), let outputPath = option("--output"), let rootPath = option("--root") else {
            throw BenchmarkError.invalidFixture("Usage: --fixture manifest.json --output report.json --root isolated-directory [--validate-only] [--case ID] [--repetitions 1...5]")
        }
        let fixtureURL = URL(fileURLWithPath: fixturePath)
        let fixtureData = try Data(contentsOf: fixtureURL)
        let fixture = try JSONDecoder().decode(GapBenchmarkFixture.self, from: fixtureData)
        try fixture.validate()
        let repetitions = Int(option("--repetitions") ?? "1") ?? 0
        guard (1...5).contains(repetitions) else { throw BenchmarkError.invalidFixture("Use 1–5 repetitions") }
        let cases = fixture.cases.filter { option("--case") == nil || $0.id == option("--case") }
        guard !cases.isEmpty else { throw BenchmarkError.invalidFixture("Unknown --case") }
        var report: [String: Any] = [
            "schemaVersion": 1, "fixtureSHA256": hash(fixtureData), "split": fixture.split,
            "provenance": fixture.provenance, "frozenAt": fixture.frozenAt as Any? ?? NSNull(),
            "date": ISO8601DateFormatter().string(from: .now), "repetitions": repetitions,
            "os": ProcessInfo.processInfo.operatingSystemVersionString, "locale": Locale.current.identifier,
            "caseSubset": cases.map(\.id), "status": "prepared", "results": [],
            "limitations": "Synthetic development data unless manifest says otherwise. Transcript replay, not ink recognition or iPad latency. Automatic support-span coverage is not human-rated relevance, entailment or educational benefit. Apple assets are not pinned."
        ]
        func save() throws {
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        }
        if args.contains("--validate-only") {
            report["status"] = "schemaValidated"; try save()
            print("Validated \(fixture.cases.count) \(fixture.split) cases. No model or PDF was run."); return
        }
        guard #available(macOS 27, *), case .available = SystemLanguageModel.default.availability else {
            report["status"] = "skippedModelUnavailable"; try save()
            print("SKIPPED: Apple on-device model unavailable"); exit(77)
        }
        let model = SystemLanguageModel.default
        report["contextSize"] = model.contextSize
        report["modelVariantDescription"] = String(describing: model.variant)
        report["sampling"] = "greedy"
        report["baselinePromptSHA256"] = hash(Data(IntentPrompts.instructions.utf8))
        report["gapPromptSHA256"] = hash(Data(MissingInformationPrompts.instructions.utf8))
        report["explicitSyntaxPlanning"] = "Shared exact-text binding; no model call. See bindingStrategy and planningPasses per request."
        report["selectorPromptSHA256"] = hash(Data(LectureComposer.instructions.utf8))
        report["gapSchemaSHA256"] = hash(Data(String(describing: ContextualGapReferences.generationSchema).utf8))
        var codeHashes: [String: String] = [:]
        for path in ["Buko/AI/IntentPrompts.swift", "Buko/AI/MissingInformationPlan.swift", "Buko/AI/CirclePlanner.swift",
                     "Buko/Retrieval/LectureRetrieval.swift", "Buko/Retrieval/GapRetrieval.swift",
                     "Buko/Retrieval/LectureLibrary.swift", "Buko/Retrieval/LecturePageExtractor.swift",
                     "Buko/Retrieval/LectureComposer.swift", "Buko/Retrieval/LectureGroundingPolicy.swift",
                     "Tests/GapBenchmarkSupport.swift", "Tests/GapRetrievalBenchmark.swift"] {
            codeHashes[path] = hash(try Data(contentsOf: URL(fileURLWithPath: path)))
        }
        report["codeSHA256"] = codeHashes
        report["baselineSchemaSHA256"] = hash(Data(String(describing: InferredCircleIntent.generationSchema).utf8))
        report["selectorSchemaSHA256"] = hash(Data(String(describing: GroundedLectureSelection.generationSchema).utf8))
        report["gapRetrievalVersion"] = GapRetrieval.version
        report["gapPromptVersion"] = MissingInformationPrompts.version
        report["evidenceCharacterLimit"] = LectureRetrieval.maxEvidenceCharacters
        report["evidenceHitLimit"] = 4
        let root = URL(fileURLWithPath: rootPath)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let library = LectureLibrary(root: root.appendingPathComponent("library"))
        let noteID = UUID()
        var documentIDs: [String: String] = [:], sources: [[String: Any]] = []
        let importStart = ProcessInfo.processInfo.systemUptime
        for (index, source) in fixture.sources.enumerated() {
            let url: URL
            if let pages = source.textPages {
                url = root.appendingPathComponent("fixture-\(index).pdf")
                try render(pages, title: source.title, to: url)
            } else {
                url = fixtureURL.deletingLastPathComponent().appendingPathComponent(source.pdfPath!)
            }
            let document = try await library.importPDF(from: url, noteID: noteID)
            documentIDs[source.id] = document.id
            sources.append(["id": source.id, "sha256": document.id, "pages": document.pageCount,
                "extractionVersion": document.extractionVersion as Any? ?? NSNull(),
                "embeddingRevision": document.embeddingRevision as Any? ?? NSNull(),
                "passages": document.passages.map { ["id": $0.id, "page": $0.page, "text": $0.text, "usedOCR": $0.usedOCR] as [String: Any] },
                "textDisagreementPages": document.textDisagreementPages ?? []])
        }
        report["sources"] = sources
        report["importSeconds"] = ProcessInfo.processInfo.systemUptime - importStart
        // Gold quotes are checked against the actual index, not assumed to have
        // survived PDF extraction. Invalid annotations stop the experiment.
        let indexed = try await library.documents(noteID: noteID).flatMap(\.passages).map {
            LectureHit(passage: $0, lexicalScore: 0, semanticScore: 0, score: 0)
        }
        for item in cases {
            for set in item.sufficientEvidenceSets where !GapBenchmarkMetrics.covers(set, hits: indexed, documentIDs: documentIDs) {
                report["status"] = "invalidEvidenceAnnotations"; report["invalidCase"] = item.id; try save()
                throw BenchmarkError.invalidFixture("Gold spans absent from imported index: \(item.id)")
            }
        }
        var records: [[String: Any]] = []
        var errors = 0
        for repetition in 0..<repetitions {
            for (index, item) in cases.enumerated() {
                let modes: [CircleRetrievalMode] = (index + repetition).isMultiple(of: 2)
                    ? [.baseline, .structuredGap] : [.structuredGap, .baseline]
                for mode in modes {
                    var record: [String: Any] = ["case": item.id, "mode": mode.rawValue, "repetition": repetition,
                        "selected": item.selected, "context": item.context, "gold": try json(item),
                        "status": "running", "retrievalAttempted": false,
                        "retrievedCompleteEvidence": false, "selectedCompleteEvidence": false]
                    let start = ProcessInfo.processInfo.systemUptime
                    do {
                        let result = try await timed {
                            try await evaluate(item, mode: mode, model: model, library: library, noteID: noteID, documentIDs: documentIDs)
                        }
                        record.merge(result) { _, new in new }
                    } catch {
                        let cause: Error
                        if let failure = error as? StageFailure {
                            record.merge(failure.record) { _, new in new }; cause = failure.underlying
                        } else {
                            cause = error; record["failureStage"] = "plannerOrWatchdog"
                        }
                        record["status"] = "error"; record["error"] = String(describing: cause); errors += 1
                        if let rejected = cause as? RejectedGapPlan {
                            record["rejectedGap"] = try json(rejected.proposed)
                            record["rejectionReason"] = String(describing: rejected.reason)
                            record["preliminaryIntent"] = rejected.preliminaryIntent
                        }
                    }
                    record["totalSeconds"] = ProcessInfo.processInfo.systemUptime - start
                    let status = record["status"] as? String
                    let answered = status == "excerpts"
                    let supported = record["selectedCompleteEvidence"] as? Bool == true
                    // These are annotation-based diagnostics, not semantic truth.
                    record["unexpectedExcerpt"] = item.expectedBehavior != "answer" && answered
                    record["missedAnswer"] = item.expectedBehavior == "answer" && !supported
                    record["expectedBehaviorMatched"] = item.expectedBehavior == "answer" ? answered && supported
                        : item.expectedBehavior == "clarify" ? status == "clarification"
                        : status == "abstained" || status == "noEvidence"
                    records.append(record); report["results"] = records; report["status"] = "running"; try save()
                    print("\(item.id) / \(mode.rawValue): \(record["status"]!) · evidence \(record["retrievedCompleteEvidence"]!) · \(String(format: "%.2f", record["totalSeconds"] as! Double))s")
                }
            }
        }
        report["status"] = errors == 0 ? "completed" : "completedWithErrors"
        report["errors"] = errors
        report["summary"] = [CircleRetrievalMode.baseline, .structuredGap].map { mode in
            let rows = records.filter { $0["mode"] as? String == mode.rawValue }
            let answerIDs = Set(cases.filter { $0.expectedBehavior == "answer" }.map(\.id))
            let answerRows = rows.filter { answerIDs.contains($0["case"] as! String) }
            return ["mode": mode.rawValue, "requests": rows.count, "answerableRequests": answerRows.count,
                "retrievedCompleteEvidence": answerRows.filter { $0["retrievedCompleteEvidence"] as? Bool == true }.count,
                "answerableRetrievalAttempts": answerRows.filter { $0["retrievalAttempted"] as? Bool == true }.count,
                "answerableWithoutRetrieval": answerRows.filter { $0["retrievalAttempted"] as? Bool != true }.count,
                "incompleteEvidenceAfterRetrieval": answerRows.filter { $0["retrievalCompleted"] as? Bool == true
                    && $0["retrievedCompleteEvidence"] as? Bool != true }.count,
                "selectedCompleteEvidence": answerRows.filter { $0["selectedCompleteEvidence"] as? Bool == true }.count,
                "clarifications": rows.filter { $0["status"] as? String == "clarification" }.count,
                "expectedBehaviorMatched": rows.filter { $0["expectedBehaviorMatched"] as? Bool == true }.count,
                "unexpectedExcerpts": rows.filter { $0["unexpectedExcerpt"] as? Bool == true }.count,
                "missedAnswers": rows.filter { $0["missedAnswer"] as? Bool == true }.count,
                "errors": rows.filter { $0["status"] as? String == "error" }.count,
                "meanSeconds": rows.compactMap { $0["totalSeconds"] as? Double }.reduce(0, +) / Double(rows.count)] as [String: Any]
        }
        try save()
        print("Benchmark completed; quality failures remain in JSON. Results are paired development observations, not a superiority claim.")
        if errors > 0 { exit(1) }
    }

    @available(macOS 27, *)
    static func evaluate(_ item: GapBenchmarkFixture.Case, mode: CircleRetrievalMode, model: SystemLanguageModel,
                         library: LectureLibrary, noteID: UUID, documentIDs: [String: String]) async throws -> [String: Any] {
        let started = ProcessInfo.processInfo.systemUptime
        let plan = try await CirclePlanner.infer(selected: item.selected, context: item.context, mode: mode, model: model)
        var record: [String: Any] = ["intent": plan.intent, "action": plan.action, "evidence": plan.evidence,
            "clarification": plan.clarification, "plannerSeconds": ProcessInfo.processInfo.systemUptime - started,
            "structuredPassInputTokens": plan.inputTokens as Any? ?? NSNull(), "plannerOutputTokenBudget": plan.responseTokenLimit,
            "planningPasses": plan.planningPasses, "preliminaryIntent": plan.preliminaryIntent as Any? ?? NSNull(),
            "bindingStrategy": plan.bindingStrategy as Any? ?? NSNull(),
            "gap": try plan.gap.map { try json($0.value) } ?? NSNull()]
        if let gap = plan.gap {
            record["expectedTargetQuoteCoverage"] = item.expectedTargetQuotes.isEmpty ? NSNull()
                : item.expectedTargetQuotes.allSatisfy { expected in gap.value.targets.contains {
                    CitationValidation.normalized($0.quote).contains(CitationValidation.normalized(expected))
                } }
        }
        if !plan.clarification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            record["status"] = "clarification"; return record
        }
        record["retrievalAttempted"] = true
        record["failureStage"] = "retrieval"
        do {
            let search = try await library.search(noteID: noteID, selected: item.selected, intent: plan.intent, gap: plan.gap)
            record["retrievalCompleted"] = true
            record["retrievalSeconds"] = search.seconds
            record["semanticAvailable"] = search.semanticAvailable
            record["gapTrace"] = try search.gapTrace.map { try json($0) } ?? NSNull()
            record["retrieved"] = search.hits.map { ["id": $0.id, "text": $0.passage.text, "page": $0.passage.page,
                "lexicalScore": $0.lexicalScore, "semanticScore": $0.semanticScore, "score": $0.score] as [String: Any] }
            record["retrievedCompleteEvidence"] = GapBenchmarkMetrics.complete(item, hits: search.hits, documentIDs: documentIDs)
            record["evidenceSpanRecall"] = GapBenchmarkMetrics.recall(item, hits: search.hits, documentIDs: documentIDs) as Any? ?? NSNull()
            let selectionStart = ProcessInfo.processInfo.systemUptime
            record["failureStage"] = "selectorOrRoute"
            switch CircleCompletionRoute.select(for: item.selected, hasLectureEvidence: !search.hits.isEmpty) {
            case .arithmetic(let result):
                record["status"] = "arithmetic"; record["lines"] = result.lines; record["clarification"] = result.clarification
            case .noEvidence:
                record["status"] = "noEvidence"; record["unverifiedSourceText"] = search.hasUnverifiedText
            case .lecture:
                let completion = try await LectureComposer.complete(selected: item.selected, context: item.context,
                    intent: plan.intent, action: plan.action, search: search, model: model)
                let selectedIDs = Set(completion.citations.map { $0.passage.id })
                record["selectedCompleteEvidence"] = GapBenchmarkMetrics.complete(item,
                    hits: search.hits.filter { selectedIDs.contains($0.id) }, documentIDs: documentIDs)
                record["status"] = completion.lines.isEmpty ? "abstained" : "excerpts"
                record["lines"] = completion.lines; record["selectedIDs"] = selectedIDs.sorted()
                record["explanation"] = completion.explanation
                record["verbatim"] = !completion.lines.isEmpty && completion.lines.count == completion.citations.count
                    && zip(completion.lines, completion.citations).allSatisfy { $0 == $1.passage.text }
            }
            record["selectorSeconds"] = ProcessInfo.processInfo.systemUptime - selectionStart
            record.removeValue(forKey: "failureStage")
            return record
        } catch { throw StageFailure(record: record, underlying: error) }
    }

    static func timed<T>(_ work: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask { try await Task.sleep(for: .seconds(90)); throw BenchmarkError.timeout }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    static func render(_ pages: [String], title: String, to url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &box, [kCGPDFContextTitle: title] as CFDictionary) else {
            throw BenchmarkError.invalidFixture("Cannot create isolated fixture PDF")
        }
        defer { context.closePDF() }
        for text in pages {
            let string = NSAttributedString(string: text, attributes: [.font: CTFontCreateWithName("Helvetica" as CFString, 12, nil),
                                                                      .foregroundColor: CGColor(gray: 0, alpha: 1)])
            let setter = CTFramesetterCreateWithAttributedString(string)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0),
                CGPath(rect: CGRect(x: 36, y: 36, width: 540, height: 720), transform: nil), nil)
            guard CTFrameGetVisibleStringRange(frame).length == string.length else {
                throw BenchmarkError.invalidFixture("Synthetic fixture page would clip text; split it into pages")
            }
            context.beginPDFPage(nil); CTFrameDraw(frame, context); context.endPDFPage()
        }
    }
}
