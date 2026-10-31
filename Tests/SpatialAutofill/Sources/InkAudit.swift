import Foundation
import PencilKit
import AppKit
import CryptoKit

/// Generated hand-lettering, executed through the real OS recognizer. This is
/// capture/integration evidence, not independent human handwriting accuracy.
enum InkAudit {
    struct Fixture {
        let id: String
        let rows: [(String, CGFloat, CGFloat)]
        let context: String
        let subject: String
        let need: String
        var pdf = false
    }
    static let fixtures: [Fixture] = [
        .init(id:"ink-capacity-left",rows:[("Luma stores inputs.",60,110),("Neral stores inputs.",560,110),("Capacity: eight entries.",80,150)],context:"Record each component's purpose and capacity.",subject:"Neral",need:"capacity"),
        .init(id:"ink-capacity-right",rows:[("Luma stores inputs.",60,110),("Neral stores inputs.",560,110),("Capacity: eight entries.",580,150)],context:"Record each component's purpose and capacity.",subject:"Luma",need:"capacity"),
        .init(id:"ink-wrapped",rows:[("A queue serves items in arrival order.",60,110),("A stack serves the newest item first.",560,110),("A printer handles",80,150),("waiting jobs this way.",80,190)],context:"Give a concrete use for each structure.",subject:"stack",need:"use"),
        .init(id:"ink-processes",rows:[("Condensation changes vapor into liquid.",560,110),("Evaporation changes liquid into vapor.",60,110),("A cold glass gets wet.",580,150)],context:"Pair each process with an everyday situation.",subject:"Evaporation",need:"situation"),
        .init(id:"ink-limit",rows:[("Vexa tracks requests.",560,110),("Tovin tracks requests.",60,110),("Limit: six pending requests.",580,150)],context:"Record what each component does and its limit.",subject:"Tovin",need:"limit"),
        .init(id:"ink-static",rows:[("Static scope resolves variable names.",60,110),("Dynamic scope resolves variable names.",560,110),("Lookup follows the calling sequence.",580,150)],context:"Record each scope's purpose and lookup rule.",subject:"Static",need:"lookup",pdf:true),
        .init(id:"ink-dynamic",rows:[("Static scope resolves variable names.",60,110),("Dynamic scope resolves variable names.",560,110),("Lookup follows lexical nesting.",80,150)],context:"Record each scope's purpose and lookup rule.",subject:"Dynamic",need:"lookup",pdf:true)
    ]
    static func ink(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat) -> PKDrawing {
        var drawing = LectureHandwriting.drawing(pages:[[text]])
        let b = drawing.bounds
        let sx = min(1, width/b.width), sy: CGFloat = 20/b.height
        drawing.transform(using: CGAffineTransform(scaleX:sx,y:sy).concatenating(CGAffineTransform(translationX:PageGeometry.pageOriginX+x-b.minX*sx,y:y-b.minY*sy)))
        return drawing
    }
    @MainActor static func run(args: [String], output: URL) async throws {
        let root = output.deletingPathExtension()
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false)
        let libraryRoot = root.appendingPathComponent("library")
        print("INK preparing disposable library")
        let library = LectureLibrary(root:libraryRoot), note = UUID()
        try await library.importPDF(from:URL(fileURLWithPath:"Buko/Resources/Lectures/programmingLanguages.pdf"),noteID:note)
        print("INK imported PDF")
        var records: [[String:Any]] = []
        for fixture in fixtures {
            print("INK capture start \(fixture.id)")
            let selected = PKDrawing(strokes:fixture.rows.flatMap { ink($0.0,x:$0.1,y:$0.2,width:370).strokes })
            print("INK strokes=\(selected.strokes.count) unique=\(Set(selected.strokes.map(\.id)).count) runs=\(SpatialInkReader.strokeRuns(selected.strokes)?.count ?? -1)")
            let contextInk = ink(fixture.context,x:60,y:50,width:870)
            let drawing = PKDrawing(strokes:selected.strokes+contextInk.strokes)
            let original = drawing.dataRepresentation()
            try original.write(to:root.appendingPathComponent(fixture.id+".drawing"))
            let image = drawing.image(from:drawing.bounds.insetBy(dx:-20,dy:-20),scale:1.5)
            var imageRect = CGRect(origin:.zero,size:image.size)
            if let cg = image.cgImage(forProposedRect:&imageRect,context:nil,hints:nil),
               let png = NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:]) {
                try png.write(to:root.appendingPathComponent(fixture.id+".png"))
            }
            let b = selected.bounds.insetBy(dx:-5,dy:-5)
            let polygon = [CGPoint(x:b.minX,y:b.minY),CGPoint(x:b.maxX,y:b.minY),CGPoint(x:b.maxX,y:b.maxY),CGPoint(x:b.minX,y:b.maxY)]
            var row: [String:Any] = ["id":fixture.id,"expectedSubject":fixture.subject,"expectedNeed":fixture.need,"authoredText":fixture.rows.map { $0.0 },"authoredContext":fixture.context]
            let recorder = ContextualIntentChecks.Recorder()
            let observer: PipelineObserver = { await recorder.receive($0) }
            do {
                let start = ProcessInfo.processInfo.systemUptime
                guard let capture = try await SpatialInkReader().read(drawing:drawing,polygon:polygon) else { throw GapPlanError.invalidReferences("missingSpatialCapture") }
                print("INK recognized \(fixture.id): \(capture.text)")
                row["captureSeconds"] = ProcessInfo.processInfo.systemUptime-start
                row["lineCountMatches"] = SpatialInkReader.strokeRuns(selected.strokes)?.count == fixture.rows.count
                row["logicalLineCount"] = capture.lines.count
                row["drawingSHA256"] = SHA256.hash(data:original).map { String(format:"%02x",$0) }.joined()
                row["capture"] = try JSONSerialization.jsonObject(with:JSONEncoder().encode(capture))
                precondition(original == drawing.dataRepresentation(),"Capture must not mutate ink")
                precondition(Set(capture.selectedStrokeIDs) == Set(selected.strokes.map(\.id)),"Selection membership changed")
                precondition(Set(capture.lineStrokeIDs.flatMap { $0 }).isDisjoint(with:Set(contextInk.strokes.map(\.id))),"Context leaked into selected geometry")
                if args.contains("--capture-only") {
                    row["geometryAvailable"] = true
                    records.append(row)
                    try SpatialAudit.save(["cases":records],to:output)
                    continue
                }
                let originalCapture = try await CircleInkReader().read(drawing:drawing,polygon:polygon)
                row["currentCapture"] = ["text":originalCapture.text,"context":originalCapture.context,"method":originalCapture.method]
                let baseline = try await CirclePlanner.infer(selected:originalCapture.text,context:originalCapture.context)
                row["baseline"] = ["clarification":baseline.clarification,"query":baseline.gap?.retrievalText ?? ""]
                row["baselineTargetCorrect"] = baseline.gap?.value.subjects?.contains(where: { $0.quote.localizedCaseInsensitiveContains(fixture.subject) }) ?? false
                let plan = try await SpatialPlanner.infer(selected:capture.text,context:capture.context,lines:capture.lines,observer:observer)
                row["clarification"] = plan.clarification
                row["bindingStrategy"] = plan.bindingStrategy ?? ""
                row["geometryAvailable"] = true
                if let gap = plan.gap {
                    row["gap"] = try JSONSerialization.jsonObject(with:JSONEncoder().encode(gap.value))
                    row["targetCorrect"] = gap.value.subjects?.contains(where: { $0.quote.localizedCaseInsensitiveContains(fixture.subject) }) ?? false
                    let acceptedRoles = ["capacity":["capacity","limit"],"use":["use","example","instance","application"],"situation":["situation","example","instance"],"limit":["limit","capacity"],"lookup":["lookup","resolution","search","rule"]][fixture.need] ?? [fixture.need]
                    row["needCorrect"] = acceptedRoles.contains { gap.value.informationNeeds.joined(separator:" ").localizedCaseInsensitiveContains($0) }
                    if fixture.pdf {
                        let search = try await library.search(noteID:note,selected:capture.text,intent:plan.intent,gap:gap)
                        let evidence = try await LectureComposer.complete(selected:capture.text,context:capture.context,intent:plan.intent,action:plan.action,search:search,observer:observer)
                        let draft = try await AutofillWriter.draft(selected:capture.text,context:capture.context,intent:plan.intent,action:plan.action,gap:gap.value,evidence:evidence,search:search,observer:observer)
                        row["retrieved"] = search.hits.map { ["id":$0.id,"text":$0.passage.text,"page":$0.passage.page] as [String:Any] }
                        row["approved"] = evidence.citations.map { ["id":$0.passage.id,"quote":$0.quote] }
                        row["draft"] = draft.content?.text ?? ""
                        row["writerExplanation"] = draft.explanation
                        row["draftLines"] = draft.content?.lines.map { ["text":$0.text,"citationIndices":$0.citationIndices] as [String:Any] } ?? []
                    }
                } else { row["targetCorrect"] = false }
            } catch { row["error"] = String(describing:error) }
            row["trace"] = await recorder.trace.steps.map { ["id":$0.id,"instructions":$0.instructions ?? "","input":$0.input,"summary":$0.summary] }
            records.append(row)
            try SpatialAudit.save(["formatVersion":1,"provenance":"Generated PencilKit strokes, actual OS recognition, actual demo PDF, unchanged production RAG and writer","cases":records],to:output)
            print("INK \(fixture.id): geometry=\(row["geometryAvailable"] ?? false) target=\(row["targetCorrect"] ?? false) \(row["draft"] ?? row["error"] ?? row["clarification"] ?? "")")
        }
    }
}
