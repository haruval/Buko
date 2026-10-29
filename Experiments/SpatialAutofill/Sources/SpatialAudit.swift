import Foundation
import FoundationModels
import CryptoKit

struct SpatialFixture: Codable {
    struct FrozenPassage: Codable { let title: String; let physical_page: Int; let text: String }
    let id: String
    let selected: String
    let context: String
    let lines: [SpatialLine]
    let subjects: [String]
    let needs: [String]
    let clarify: Bool
    var pdf: String? = nil
    var answerTerms: [[String]]? = nil
    var frozenPassages: [FrozenPassage]? = nil
}

enum SpatialAudit {
    static func save(_ value: [String: Any], to output: URL) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            .write(to: output, options: .atomic)
    }
    @MainActor static func run(args: [String], output: URL) async throws {
        func option(_ key: String) -> String? {
            guard let index = args.firstIndex(of: key), args.indices.contains(index + 1) else { return nil }
            return args[index + 1]
        }
        guard !FileManager.default.fileExists(atPath: output.path) else { throw GapPlanError.invalidReferences("outputExists") }
        if args.contains("--capture-checks") { try await CaptureAudit.run(args:args,output:output); return }
        if args.contains("--ink-guards") { try await InkGuardAudit.run(output:output); return }
        if args.contains("--cancel-spatial") { try await cancellationChecks(output:output); return }
        if args.contains("--self-check") {
            try selfChecks(); try WrapAudit.run(); try await explicitBindingChecks(); planningModeChecks()
            try save(["passed": 56], to: output); return
        }
        if args.contains("--ink") { try await InkAudit.run(args: args, output: output); return }
        guard let path = option("--fixtures") else { throw GapPlanError.invalidReferences("missingFixtures") }
        struct Corpus: Decodable { let cases: [SpatialFixture] }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let corpus = try JSONDecoder().decode(Corpus.self, from: data)
        let filter = option("--case")?.split(separator: ",").map(String.init)
        let items = corpus.cases.filter { filter == nil || filter!.contains($0.id) }
        let repetitions = Int(option("--repetitions") ?? "1") ?? 0
        guard !items.isEmpty, (1...3).contains(repetitions) else { throw GapPlanError.invalidReferences("invalidRun") }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let libraryRoot = output.deletingPathExtension().appendingPathExtension("library")
        let library = LectureLibrary(root:libraryRoot)
        var sourceNotes: [String:UUID] = [:]
        for pdf in Set(items.compactMap(\.pdf)).sorted() {
            let note = UUID(); sourceNotes[pdf] = note
            try await library.importPDF(from:URL(fileURLWithPath:"Buko/Resources/Lectures/"+pdf+".pdf"),noteID:note)
        }
        var records: [[String: Any]] = []
        for repetition in 1...repetitions {
          for (index, original) in items.enumerated() {
            let normalized = try SpatialGroups.coalescedWraps(original.lines,transcript:GapTranscript(selected:original.selected,context:original.context))
            let item = args.contains("--coalesce-wraps") ? SpatialFixture(id:original.id,
                selected:normalized.lines.map(\.text).joined(separator:"\n"),context:original.context,lines:normalized.lines,
                subjects:original.subjects,needs:original.needs,clarify:original.clarify,pdf:original.pdf,answerTerms:original.answerTerms,frozenPassages:original.frozenPassages) : original
            for candidate in (args.contains("--candidate-only") ? [true] : ((index + repetition).isMultiple(of: 2) ? [false, true] : [true, false])) {
                var record: [String: Any] = ["id": item.id, "candidate": candidate, "repetition": repetition,
                    "selected": item.selected, "context": item.context,
                    "expectedSubjects": item.subjects, "expectedNeeds": item.needs, "expectedClarification": item.clarify]
                record["originalSelected"] = original.selected
                record["coalescedWraps"] = args.contains("--coalesce-wraps")
                let recorder = ContextualIntentChecks.Recorder()
                let observer: PipelineObserver = { event in await recorder.receive(event) }
                let start = ProcessInfo.processInfo.systemUptime
                do {
                    let plan = try await (candidate ? SpatialPlanner.infer(selected: item.selected, context: item.context, lines: item.lines, observer: observer)
                        : CirclePlanner.infer(selected: item.selected, context: item.context, observer: observer))
                    if candidate {
                        let limit = plan.bindingStrategy?.hasPrefix("spatialThen.") == true
                            ? SpatialPlanner.maximumFallbackPasses : SpatialPlanner.maximumSpatialPasses
                        if plan.bindingStrategy?.hasPrefix("spatial") == true || plan.bindingStrategy == "validatedSpatialInventory" {
                            precondition(plan.planningPasses <= limit, "Spatial planning exceeded its call budget")
                        }
                    }
                    record["clarification"] = plan.clarification
                    record["bindingStrategy"] = plan.bindingStrategy ?? ""
                    record["planningPasses"] = plan.planningPasses
                    var passed = item.clarify && plan.gap == nil && !plan.clarification.isEmpty
                    if let gap = plan.gap {
                        record["gap"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(gap.value))
                        let subjects = gap.value.subjects?.map { $0.quote.lowercased() } ?? []
                        let need = gap.value.informationNeeds.joined(separator: " ").lowercased()
                        passed = !item.clarify && plan.clarification.isEmpty && subjects.count == item.subjects.count
                            && item.subjects.allSatisfy { expected in subjects.contains { $0.contains(expected.lowercased()) } }
                            && item.needs.contains { need.contains($0.lowercased()) }
                        if let pdf = item.pdf, let note = sourceNotes[pdf] {
                            let search: LectureSearch
                            if let passages = item.frozenPassages {
                                let hits = passages.enumerated().map { index,p in
                                    LectureHit(passage:.init(id:"frozen-\(index)",documentID:"actual-app-pdf",title:p.title,page:p.physical_page,text:p.text,usedOCR:false,vector:nil),lexicalScore:1,semanticScore:0,score:1)
                                }
                                search = LectureSearch(hits:hits,documentCount:1,revision:"frozen-app-retrieval",semanticAvailable:false,seconds:0,gapPlan:gap)
                                record["frozenAppRetrieval"] = true
                            } else { search = try await library.search(noteID:note,selected:item.selected,intent:plan.intent,gap:gap) }
                            let evidence = try await LectureComposer.complete(selected:item.selected,context:item.context,intent:plan.intent,action:plan.action,search:search,observer:observer)
                            let draft = try await AutofillWriter.draft(selected:item.selected,context:item.context,intent:plan.intent,action:plan.action,gap:gap.value,evidence:evidence,search:search,observer:observer)
                            let text = draft.content?.text ?? ""
                            record["draft"] = text; record["draftExplanation"] = draft.explanation
                            record["retrieved"] = search.hits.map { ["text":$0.passage.text,"page":$0.passage.page] as [String:Any] }
                            record["evidenceExplanation"] = evidence.explanation
                            record["draftLines"] = draft.content?.lines.map { ["text":$0.text,"citationIndices":$0.citationIndices] as [String:Any] } ?? []
                            let complete = !text.isEmpty && (item.answerTerms ?? []).allSatisfy { alternatives in
                                alternatives.contains { text.localizedCaseInsensitiveContains($0) }
                            }
                            record["answerTermsPassed"] = complete
                            passed = passed && complete
                        }
                    }
                    record["passed"] = passed
                } catch { record["passed"] = false; record["error"] = String(describing: error) }
                record["seconds"] = ProcessInfo.processInfo.systemUptime - start
                record["trace"] = await recorder.trace.steps.map { ["id": $0.id, "instructions": $0.instructions ?? "", "input": $0.input, "summary": $0.summary] }
                records.append(record)
                try save(["formatVersion": 1, "corpusSHA256": hash, "partition": "synthetic development", "records": records], to: output)
                print("SPATIAL \(item.id) candidate=\(candidate): \(record["passed"]!) \(record["error"] ?? record["clarification"] ?? "")")
            }
          }
        }
        print("SPATIAL complete \(records.count) trials")
    }

    static func cancellationChecks(output: URL) async throws {
        var reports: [[String:Any]] = []
        let selected = "A queue serves items in arrival order.\nA stack serves the newest item first.\nA printer handles\nwaiting jobs this way."
        let transcript = GapTranscript(selected:selected,context:"")
        let lines = transcript.blocks.enumerated().map { index,block in SpatialLine(blockID:block.id,text:block.text,page:"p1",rect:[[60.0,100,370,25],[560,100,370,25],[80,140,350,25],[80,180,350,25]][index]) }
        for stage in ["spatialInventory", "spatialRepair", "spatialParagraphRepair", "spatialRequest"] {
            for boundary in ["began", "completed"] {
                let recorder = ContextualIntentChecks.Recorder()
                let isParagraph = stage == "spatialParagraphRepair" || stage == "spatialRequest"
                let input = isParagraph ? "Static scope resolves variable names.\ndynamic scope resolves variable names.\nLookup follows Lexical nesting." : selected
                let nearby = isParagraph ? "record each scope's purpose and lookup rule." : "Give a concrete use for each structure."
                let rows = isParagraph ? GapTranscript(selected:input,context:nearby).blocks.filter(\.selected).enumerated().map { index,block in
                    SpatialLine(blockID:block.id,text:block.text,page:"p1",rect:[[60.0,82.5,370,15],[560,82.5,370,15],[80,112.5,370,15]][index])
                } : lines
                let task = Task {
                    let observer: PipelineObserver = { event in
                        await recorder.receive(event)
                        switch event {
                        case .began(let id, _, _, _) where id == stage && boundary == "began": withUnsafeCurrentTask { $0?.cancel() }
                        case .completed(let id, _) where id == stage && boundary == "completed": withUnsafeCurrentTask { $0?.cancel() }
                        default: break
                        }
                    }
                    return try await SpatialPlanner.infer(selected:input,context:nearby,lines:rows,observer:observer)
                }
                do { _ = try await task.value; preconditionFailure("Cancellation returned a plan") } catch is CancellationError {}
                let steps = await recorder.trace.steps
                precondition(steps.last?.id == stage)
                reports.append(["stage":stage,"boundary":boundary,"passed":true,"observed":steps.map(\.id)])
            }
        }
        try save(["checks":reports],to:output)
        print("CANCELLATION 8/8")
    }

    static func explicitBindingChecks() async throws {
        for selected in ["Parsing:", "Parsing:\nType checking:"] {
            let recorder = ContextualIntentChecks.Recorder()
            let observer: PipelineObserver = { await recorder.receive($0) }
            let plan = try await SpatialPlanner.infer(selected:selected,context:"",lines:nil,observer:observer)
            let expected = try CirclePlanner.explicitPlan(in:GapTranscript(selected:selected,context:""),mode:.structuredGap)!
            precondition(plan.planningPasses == 0 && plan.intent == expected.intent && plan.clarification == expected.clarification)
            let steps = await recorder.trace.steps
            precondition(steps.map(\.id) == ["binding"] && steps.first?.status == .completed)
        }
        for boundary in ["began", "completed"] {
            let task = Task {
                let observer: PipelineObserver = { event in
                    switch event {
                    case .began(let id, _, _, _) where id == "binding" && boundary == "began": withUnsafeCurrentTask { $0?.cancel() }
                    case .completed(let id, _) where id == "binding" && boundary == "completed": withUnsafeCurrentTask { $0?.cancel() }
                    default: break
                    }
                }
                return try await SpatialPlanner.infer(selected:"Parsing:",context:"",lines:nil,observer:observer)
            }
            do { _ = try await task.value; preconditionFailure("Explicit binding returned after cancellation") }
            catch is CancellationError { }
        }
    }

    static func planningModeChecks() {
        precondition(AutofillPlanningMode.resolve() == .standard)
        precondition(AutofillPlanningMode.resolve(enabled: false, arguments: ["--spatial-fixture", "static"]) == .standard)
        precondition(AutofillPlanningMode.resolve(enabled: true) == .layoutAware)
        precondition(AutofillPlanningMode.resolve(enabled: true, arguments: ["--spatial-baseline"]) == .standard)
        precondition(AutofillPlanningMode.resolve(enabled: true, arguments: ["--spatial-fixture", "static"]) == .layoutAware)
        var nextArguments: [String] = []
        let requestMode = AutofillPlanningMode.resolve(enabled: true, arguments: nextArguments)
        nextArguments.append("--spatial-baseline")
        precondition(requestMode == .layoutAware && AutofillPlanningMode.resolve(enabled: true, arguments: nextArguments) == .standard)
    }

    static func selfChecks() throws {
        precondition(SpatialPlanner.refinedNeeds(["capacity","failure behavior"],cue:.init(blockID:"C1",quote:"capacity")) == ["capacity","failure behavior"])
        precondition(SpatialPlanner.refinedNeeds(["example"],cue:nil) == ["example"])
        precondition(SpatialPlanner.needsCounterpartContext(["property"],cue:.init(blockID:"C1",quote:"memory ownership")))
        precondition(!SpatialPlanner.needsCounterpartContext(["lookup"],cue:.init(blockID:"C1",quote:"Lookup rule")))
        precondition(!SpatialPlanner.needsCounterpartContext(["example"],cue:nil))
        let cueTranscript = GapTranscript(selected:"A and B",context:"Record Memory ownership.\nrange range")
        precondition(SpatialPlanner.anchoredCue(.init(blockID:"C1",quote:"memory ownership"),in:cueTranscript)?.quote == "Memory ownership")
        precondition(SpatialPlanner.anchoredCue(.init(blockID:"C1",quote:"memory possession"),in:cueTranscript) == nil)
        precondition(SpatialPlanner.anchoredCue(.init(blockID:"G1",quote:"Memory ownership"),in:cueTranscript) == nil)
        precondition(SpatialPlanner.anchoredCue(.init(blockID:"",quote:"Memory ownership"),in:cueTranscript) == nil)
        precondition(SpatialPlanner.anchoredCue(.init(blockID:"C2",quote:"range"),in:cueTranscript) == nil)
        precondition(SpatialPlanner.anchoredCue(.init(blockID:"",quote:""),in:cueTranscript) == .init(blockID:"",quote:""))
        precondition(SpatialPlanner.anchoredCue(.init(blockID:"C1",quote:String(repeating:"x",count:121)),in:cueTranscript) == nil)
        precondition(SpatialPlanner.anchoredCue(.init(blockID:"C1",quote:" "),in:cueTranscript) == nil)
        let selected = "Alpha stores items.\nBeta stores items.\nLimit: six items."
        let transcript = GapTranscript(selected: selected, context: "")
        func line(_ index: Int, _ rect: [Double], page: String = "p1", text: String? = nil) -> SpatialLine {
            .init(blockID: "S\(index+1)", text: text ?? transcript.blocks[index].text, page: page, rect: rect)
        }
        let input = [line(0,[60,100,370,25]),line(1,[560,100,370,25]),line(2,[80,140,350,25])]
        let groups = try SpatialGroups.validated(input, transcript: transcript)
        precondition(groups.groups.contains(["S1","S3"]) && groups.groups.contains(["S2"]))
        func rejects(_ values: [SpatialLine]) {
            do { _ = try SpatialGroups.validated(values, transcript: transcript); preconditionFailure("Invalid geometry accepted") } catch {}
        }
        rejects(Array(input.prefix(2)))
        rejects([input[0], input[1], line(2,[80,140,350,25],text:"Different words")])
        rejects([input[0], input[1], line(2,[80,140,.infinity,25])])
        rejects([input[0], input[1], line(2,[80,140,1000,25])])
        let tied = try SpatialGroups.validated([input[0],input[1],line(2,[60,140,870,25])], transcript: transcript)
        precondition(tied.groups.count == 3)
        let paged = try SpatialGroups.validated([input[0],input[1],line(2,[80,140,350,25],page:"p2")], transcript: transcript)
        precondition(paged.groups.count == 3)
        let bad = GroundedPatternMap(topics: [
            .init(topic:"Alpha",supplied:[.init(role:"meaning",quote:transcript.blocks[0].text)]),
            .init(topic:"Beta",supplied:[.init(role:"meaning",quote:transcript.blocks[1].text),.init(role:"limit",quote:transcript.blocks[2].text)])], requiredRoles:["meaning","limit"])
        precondition(!groups.allows(bad,transcript:transcript))
        let repeated = GapTranscript(selected: "Alpha stores items.\nBeta stores items.\nAlpha holds six items.", context: "")
        let repeatedLines = zip(input,repeated.blocks.filter(\.selected)).map { line,block in SpatialLine(blockID:line.blockID,text:block.text,page:line.page,rect:line.rect) }
        let repeatedLayout = try SpatialGroups.validated(repeatedLines,transcript:repeated)
        let repeatedMap = GroundedPatternMap(topics:[.init(topic:"Alpha",supplied:[.init(role:"meaning",quote:"Alpha stores items."),.init(role:"capacity",quote:"Alpha holds six items.")]),.init(topic:"Beta",supplied:[.init(role:"meaning",quote:"Beta stores items.")])],requiredRoles:["meaning","capacity"])
        precondition(repeatedLayout.allows(repeatedMap,transcript:repeated),"A topic repeated inside its own region is anchored")
        let crossRegion = [repeatedLines[0],repeatedLines[1],SpatialLine(blockID:"S3",text:repeatedLines[2].text,page:"p1",rect:[580,140,350,25])]
        let conflictingLayout = try SpatialGroups.validated(crossRegion,transcript:repeated)
        precondition(!conflictingLayout.allows(repeatedMap,transcript:repeated),"Repeated topic across groups is ambiguous")
        let page = NotebookPaging.rect(for:0)
        let first = CGRect(x:page.minX+60,y:100,width:300,height:20)
        let second = first.offsetBy(dx:0,dy:NotebookPaging.pageStride)
        precondition(SpatialInkReader.pageLocation(first)?.rect == SpatialInkReader.pageLocation(second)?.rect)
        precondition(SpatialInkReader.pageLocation(first)?.page != SpatialInkReader.pageLocation(second)?.page)
        precondition(SpatialInkReader.pageLocation(CGRect(x:page.minX,y:page.maxY-5,width:50,height:20)) == nil)
        precondition(SpatialInkReader.pageLocation(CGRect(x:page.minX-1,y:100,width:50,height:20)) == nil)
        let wrappedTranscript = GapTranscript(selected:"Alpha stores items.\nBeta stores items.\nA short\ncontinued example.",context:"")
        let wrappedLines = wrappedTranscript.blocks.enumerated().map { index,block in SpatialLine(blockID:block.id,text:block.text,page:"p1",rect:[[60.0,100,370,25],[560,100,370,25],[80,140,350,25],[80,180,350,25]][index]) }
        let wrappedLayout = try SpatialGroups.validated(wrappedLines,transcript:wrappedTranscript)
        let value = SpatialInventory(regions:[.init(regionID:"G1",topic:"Alpha",supplied:[.init(role:"meaning",quote:"Alpha stores items."),.init(role:"example",quote:"A short continued example.")]),.init(regionID:"G2",topic:"Beta",supplied:[.init(role:"meaning",quote:"Beta stores items.")])],requiredRoles:["meaning","example"],basis:"test",kind:.parallelPattern)
        let anchored = SpatialPlanner.anchoredInventory(value,layout:wrappedLayout,transcript:wrappedTranscript)
        precondition(anchored.topics[0].supplied.map(\.quote) == ["Alpha stores items.","A short","continued example."])
        var changed = value; changed.regions[0].supplied[1].quote = "A different continued example."
        precondition(!wrappedLayout.allows(SpatialPlanner.anchoredInventory(changed,layout:wrappedLayout,transcript:wrappedTranscript),transcript:wrappedTranscript))
        precondition(SpatialInkReader.pageLocation(CGRect(x:page.minX,y:CGFloat.greatestFiniteMagnitude/2,width:50,height:20)) == nil)
        let prefix = GapTranscript(selected:"A magnet separates magnetic material.",context:"")
        let qualified = SpatialPlanner.uniqueTarget(.init(blockID:"S1",quote:"magnet"),in:prefix)
        precondition(qualified?.quote == "A magnet")
        let repeatedTopic = GapTranscript(selected:"A magnet attracts another magnet.",context:"")
        precondition(SpatialPlanner.uniqueTarget(.init(blockID:"S1",quote:"magnet"),in:repeatedTopic) == nil)
        let identifiers = GapTranscript(selected:"Device M1 differs from M10.",context:"")
        precondition(SpatialPlanner.uniqueTarget(.init(blockID:"S1",quote:"M1"),in:identifiers)?.quote == "Device M1")
        let ordinary = GapTextReference(blockID:"S1",quote:"magnet")
        precondition(SpatialPlanner.uniqueTarget(ordinary,in:GapTranscript(selected:"A magnet attracts iron.",context:"")) == ordinary)
        print("SELF-CHECK 34 structural checks; four explicit-binding checks follow")
    }
}
