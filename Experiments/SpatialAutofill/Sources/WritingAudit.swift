import Foundation

enum WritingAudit {
    struct Fixture {
        let id: String
        let selected: String
        let context: String
        var sources: [String] = []
        let criterion: String
        var layout: [SpatialLine]? = nil
    }
    static let fixtures: [Fixture] = [
        .init(id:"pdf-parsing",selected:"Lexical analysis: groups characters into tokens.\nParsing:",context:"",criterion:"Continue the heading; grammar check and syntax tree; no lexical-analysis repetition."),
        .init(id:"pdf-dynamic",selected:"Static scoping: follows lexical nesting.\nDynamic scoping:",context:"",criterion:"Continue with the lookup rule; no repeated heading or synonym."),
        .init(id:"pdf-example",selected:"Example of a closure:",context:"A closure retains its lexical environment.",criterion:"Concrete makeAdder instance, retained binding and behavior; do not reduce to definition."),
        .init(id:"pdf-reason",selected:"It keeps working after the creating function returns because",context:"A closure retains its captured variables.",criterion:"Continue the unfinished clause with captured environment explanation; no repeated clause, invented detail or unwarranted example-specific scope."),
        .init(id:"qualified-negative",selected:"Did the Luma pilot establish improved recall?",context:"",sources:["In the fictional Luma pilot, twelve participants tried a new review method. The pilot did not establish an improvement in recall. The small sample was insufficient to rule out an effect. No effect size was reported."],criterion:"Not established, retain small-sample uncertainty; never claim no effect."),
        .init(id:"missing-quantity",selected:"By what percentage did the Luma method improve recall?",context:"",sources:["The fictional Luma pilot did not establish an improvement in recall. The small sample was insufficient to rule out an effect. No effect size was reported."],criterion:"Withhold unreported percentage."),
        .init(id:"corrected-value",selected:"How many chambers does Luma have?",context:"",sources:["The fictional Luma sample has seven chambers.","Correction: Luma has nine chambers, not seven. This replaces the earlier chamber count for Luma."],criterion:"Nine as current count; concise correction."),
        .init(id:"definition-only",selected:"Example of a semaphore:",context:"",sources:["A semaphore is a synchronization primitive used to coordinate access to a shared resource."],criterion:"Withhold a concrete example unsupported by source."),
        .init(id:"concise-definition",selected:"Neral: stores recent items.\nZeffa:",context:"",sources:["In this fictional data structure exercise, Zeffa is a bounded queue. It stores at most twelve pending entries. Entries leave in arrival order. If it is full, a new entry is rejected. This behavior is separate from Neral, which stores recent items."],criterion:"Capacity twelve, arrival order, reject when full, no Neral repetition; natural continuation."),
        .init(id:"transfer-conditional",selected:"Rova admission:",context:"This table records when each fictional device accepts a packet.",sources:["The fictional Rova device accepts a packet only if its queue contains fewer than four packets and its link is active. Otherwise the packet is rejected. The Tavin device uses a different policy."],criterion:"Preserve both conjunction conditions and rejection otherwise; no Tavin."),
        .init(id:"transfer-association",selected:"Does the Vela study show that reminders cause better retention?",context:"",sources:["In the fictional Vela observational study, reminder use was associated with higher retention. Participants selected whether to use reminders. The study did not establish that reminders caused the difference."],criterion:"Association not causation; preserve observational/self-selection limitation."),
        .init(id:"transfer-prefix",selected:"A Daro job is retried only when",context:"Daro is the fictional scheduler in this lecture.",sources:["The fictional Daro scheduler retries a failed job only when the job is marked retryable and its attempt count is below three. Jobs without either condition are not retried."],criterion:"Grammatical continuation; preserve retryable AND attempts below three; no repeated prefix."),
        .init(id:"transfer-scope",selected:"How many slots does the revision B Mivo buffer have?",context:"",sources:["The fictional Mivo buffer has six slots in revision A. Revision B has ten slots; this update does not change revision A."],criterion:"Revision B ten; do not claim all Mivo buffers ten or revision A corrected."),
        .init(id:"transfer-negation",selected:"Did the Nemi trial prove the treatment has no effect?",context:"",sources:["The fictional Nemi trial found no statistically significant improvement. Its confidence interval included both no effect and a potentially useful benefit. It did not establish absence of an effect."],criterion:"No proof of no effect; confidence interval includes no effect and useful benefit."),
        .init(id:"transfer-missing",selected:"What is the maximum temperature tolerated by the Fera sensor?",context:"",sources:["The fictional Fera sensor measures temperature. This lecture does not report a maximum operating temperature."],criterion:"Withhold unreported temperature; never fabricate number."),
        .init(id:"transfer-example",selected:"Example of a Lerin gate:",context:"",sources:["A fictional Lerin gate admits only one task at a time. In the lecture example, task Ada acquires the gate before updating a shared counter. Task Bo waits until Ada releases it, then updates the counter."],criterion:"Keep Ada/Bo concrete sequence and gate behavior, not just definition."),
        .init(id:"transfer-bounded",selected:"Falo cache:",context:"Sera cache: retains recent entries.",sources:["The fictional Falo cache holds five records. A sixth insertion evicts the oldest record. Reading a record does not change the eviction order."],criterion:"Capacity five, oldest eviction on insertion, reads do not reorder; no invented LRU behavior."),
        .init(id:"spatial-pdf-static",selected:"Static scope resolves variable names.\nDynamic scope resolves variable names.\nLookup follows the calling sequence.",context:"For each scope, record its purpose and lookup rule.",criterion:"Select Static scope; retrieve its lexical lookup rule from the PDF; no new dynamic-scope explanation.",layout:[
            .init(blockID:"S1",text:"Static scope resolves variable names.",page:"p1",rect:[60,100,370,25]),
            .init(blockID:"S2",text:"Dynamic scope resolves variable names.",page:"p1",rect:[560,100,370,25]),
            .init(blockID:"S3",text:"Lookup follows the calling sequence.",page:"p1",rect:[580,140,350,25])]),
        .init(id:"spatial-pdf-dynamic",selected:"Static scope resolves variable names.\nDynamic scope resolves variable names.\nLookup follows lexical nesting.",context:"For each scope, record its purpose and lookup rule.",criterion:"Select Dynamic scope; retrieve its active-call lookup rule from the PDF; no new static-scope explanation.",layout:[
            .init(blockID:"S1",text:"Static scope resolves variable names.",page:"p1",rect:[60,100,370,25]),
            .init(blockID:"S2",text:"Dynamic scope resolves variable names.",page:"p1",rect:[560,100,370,25]),
            .init(blockID:"S3",text:"Lookup follows lexical nesting.",page:"p1",rect:[80,140,350,25])])
    ]

    @MainActor static func run(args: [String], output: URL) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BukoSpatialWriter-"+UUID().uuidString)
        let library = LectureLibrary(root: root); let note = UUID()
        defer { try? FileManager.default.removeItem(at: root) }
        try await library.importPDF(from: URL(fileURLWithPath:"Buko/Resources/Lectures/programmingLanguages.pdf"),noteID:note)
        var records: [[String:Any]] = []
        for (index, fixture) in fixtures.enumerated() {
            var row: [String:Any] = ["id":fixture.id,"selected":fixture.selected,"context":fixture.context,"criterion":fixture.criterion,
                "provenance":fixture.sources.isEmpty ? "repository demo lecture PDF, actual extraction/retrieval" : "synthetic development control"]
            let recorder = ContextualIntentChecks.Recorder()
            let observer: PipelineObserver = { event in await recorder.receive(event) }
            do {
                if fixture.layout != nil {
                    let baseline = try await CirclePlanner.infer(selected:fixture.selected,context:fixture.context)
                    row["textOnlyPlanning"] = ["clarification":baseline.clarification,"query":baseline.gap?.retrievalText ?? ""]
                }
                let plan = try await (fixture.layout != nil
                    ? SpatialPlanner.infer(selected:fixture.selected,context:fixture.context,lines:fixture.layout,observer:observer)
                    : CirclePlanner.infer(selected:fixture.selected,context:fixture.context,observer:observer))
                row["plannerBackend"] = fixture.layout == nil ? "unchanged system planner" : "isolated spatial inventory"
                row["clarification"] = plan.clarification
                guard let gap = plan.gap,plan.clarification.isEmpty else {
                    row["stage"]="planner withheld"; records.append(row); try SpatialAudit.save(["cases":records],to:output); continue
                }
                row["gap"] = try JSONSerialization.jsonObject(with:JSONEncoder().encode(gap.value))
                let search: LectureSearch
                if fixture.sources.isEmpty {
                    search = try await library.search(noteID:note,selected:fixture.selected,intent:plan.intent,gap:gap)
                } else {
                    let hits = fixture.sources.enumerated().map { index,text in
                        LectureHit(passage:.init(id:"control-\(index)",documentID:"synthetic",title:"Synthetic lecture control",page:index+1,text:text,usedOCR:false,vector:nil),lexicalScore:1,semanticScore:0,score:1)
                    }
                    search = LectureSearch(hits:hits,documentCount:1,revision:"synthetic",semanticAvailable:false,seconds:0,gapPlan:gap)
                }
                let evidence = try await LectureComposer.complete(selected:fixture.selected,context:fixture.context,intent:plan.intent,action:plan.action,search:search,observer:observer)
                row["retrieved"] = search.hits.map { ["id":$0.id,"text":$0.passage.text,"page":$0.passage.page] as [String:Any] }
                row["approved"] = evidence.citations.map { ["id":$0.passage.id,"quote":$0.quote] }
                row["evidenceReady"] = evidence.extractive
                row["evidenceExplanation"] = evidence.explanation
                var drafts: [[String:Any]] = []
                for candidate in (index.isMultiple(of:2) ? [false,true] : [true,false]) {
                    let trace = ContextualIntentChecks.Recorder()
                    let observer: PipelineObserver = { event in await trace.receive(event) }
                    let start = ProcessInfo.processInfo.systemUptime
                    let result = try await (candidate ? GroundedNoteWriter.draft(selected:fixture.selected,context:fixture.context,intent:plan.intent,action:plan.action,gap:gap.value,evidence:evidence,search:search,observer:observer)
                        : AutofillWriter.draft(selected:fixture.selected,context:fixture.context,intent:plan.intent,action:plan.action,gap:gap.value,evidence:evidence,search:search,observer:observer))
                    drafts.append(["candidate":candidate,"ready":result.content != nil,"text":result.content?.text ?? "","explanation":result.explanation,
                        "lines":result.content?.lines.map { ["text":$0.text,"citationIndices":$0.citationIndices] as [String:Any] } ?? [],
                        "seconds":ProcessInfo.processInfo.systemUptime-start,
                        "trace":await trace.trace.steps.map { ["id":$0.id,"instructions":$0.instructions ?? "","input":$0.input,"summary":$0.summary] }])
                    print("WRITING \(fixture.id) candidate=\(candidate): \(result.content?.text ?? result.explanation)")
                }
                row["drafts"] = drafts
            } catch { row["error"] = String(describing:error) }
            row["trace"] = await recorder.trace.steps.map { ["id":$0.id,"input":$0.input,"summary":$0.summary] }
            records.append(row)
            try SpatialAudit.save(["formatVersion":1,"partition":"development","cases":records],to:output)
        }
        print("WRITING complete \(records.count) cases")
    }
}
