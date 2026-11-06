import Foundation
import AppKit
import CoreGraphics
import PDFKit
import PencilKit
import CryptoKit

enum SpatialBindingIntegrationAudit {
    static func pdf(_ url: URL, includeNeral: Bool) throws {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw GapPlanError.invalidReferences("pdfContext") }
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let text = "Component capacities\n\nLuma buffers inputs. Luma can buffer up to eight entries."
            + (includeNeral ? "\n\nNeral buffers inputs. Neral can buffer up to five entries." : "")
        (text as NSString).draw(in: CGRect(x: 48, y: 400, width: 516, height: 300), withAttributes: [
            .font: NSFont.systemFont(ofSize: 17), .foregroundColor: NSColor.black
        ])
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage(); context.closePDF()
        guard PDFDocument(url: url)?.string?.contains("eight entries") == true else { throw GapPlanError.invalidReferences("pdfText") }
    }
    @MainActor static func run(args: [String], output: URL) async throws {
        let root = output.deletingPathExtension()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let library = LectureLibrary(root: root.appendingPathComponent("library"))
        var records: [[String:Any]] = []
        for (id, rightFilled, supported) in [("ink-field-left", false, true), ("ink-field-right", true, true), ("ink-field-unsupported", false, false)] {
            let source = root.appendingPathComponent(id + ".pdf")
            try pdf(source, includeNeral: supported)
            let note = UUID(); try await library.importPDF(from: source, noteID: note)
            let rows: [(String, CGFloat, CGFloat)] = [
                ("Luma:", 60, 110), ("Neral:", 560, 110),
                ("Purpose: buffer inputs.", 60, 150), ("Purpose: buffer inputs.", 560, 150),
                (rightFilled ? "Capacity: five entries." : "Capacity: eight entries.", rightFilled ? 560 : 60, 190)
            ]
            let selection = PKDrawing(strokes: rows.flatMap { InkAudit.ink($0.0, x:$0.1, y:$0.2, width:370).strokes })
            let context = InkAudit.ink("Record purpose and capacity for each component.", x:60, y:50, width:870)
            let drawing = PKDrawing(strokes:selection.strokes + context.strokes)
            let bytes = drawing.dataRepresentation()
            try bytes.write(to: root.appendingPathComponent(id + ".drawing"))
            let b = selection.bounds.insetBy(dx: -5, dy: -5)
            let polygon = [CGPoint(x:b.minX,y:b.minY),CGPoint(x:b.maxX,y:b.minY),CGPoint(x:b.maxX,y:b.maxY),CGPoint(x:b.minX,y:b.maxY)]
            let recorder = ContextualIntentChecks.Recorder()
            let observer: PipelineObserver = { await recorder.receive($0) }
            var row: [String:Any] = ["id":id, "expectedSubject":rightFilled ? "Luma":"Neral", "supported":supported]
            do {
                guard let capture = try await SpatialInkReader().read(drawing:drawing,polygon:polygon) else { throw GapPlanError.invalidReferences("fieldCapture") }
                row["capture"] = try JSONSerialization.jsonObject(with:JSONEncoder().encode(capture))
                let plan = try await SpatialPlanner.infer(selected:capture.text,context:capture.context,lines:capture.lines,observer:observer)
                row["bindingStrategy"] = plan.bindingStrategy ?? ""
                row["planningPasses"] = plan.planningPasses
                guard let gap = plan.gap else { throw GapPlanError.invalidReferences("fieldNoPlan:"+plan.clarification) }
                row["gap"] = try JSONSerialization.jsonObject(with:JSONEncoder().encode(gap.value))
                let search = try await library.search(noteID:note,selected:capture.text,intent:plan.intent,gap:gap)
                let evidence = try await LectureComposer.complete(selected:capture.text,context:capture.context,intent:plan.intent,action:plan.action,search:search,observer:observer)
                let draft = try await AutofillWriter.draft(selected:capture.text,context:capture.context,intent:plan.intent,action:plan.action,gap:gap.value,evidence:evidence,search:search,observer:observer)
                let answer = draft.content?.text ?? ""
                row["draft"] = answer; row["draftExplanation"] = draft.explanation
                row["citations"] = draft.content?.lines.map { ["text":$0.text,"citationIndices":$0.citationIndices] as [String:Any] } ?? []
                row["sourcePassages"] = search.hits.map { $0.passage.text }
                let targetOK = gap.value.subjects?.contains { $0.quote.localizedCaseInsensitiveContains(rightFilled ? "Luma":"Neral") } == true
                let answerOK = supported ? (rightFilled ? answer.localizedCaseInsensitiveContains("eight") || answer.contains("8") : answer.localizedCaseInsensitiveContains("five") || answer.contains("5")) : answer.isEmpty
                let citationsOK = !supported || (draft.content?.lines.allSatisfy { !$0.citationIndices.isEmpty } == true)
                let otherCapacityAbsent = !supported || !answer.localizedCaseInsensitiveContains(rightFilled ? "five" : "eight")
                row["passed"] = targetOK && answerOK && citationsOK && otherCapacityAbsent && plan.bindingStrategy == "validatedSpatialInventory"
            } catch { row["error"] = String(describing:error); row["passed"] = false }
            row["drawingUnchanged"] = bytes == drawing.dataRepresentation()
            row["trace"] = await recorder.trace.steps.map { ["id":$0.id,"input":$0.input,"summary":$0.summary] }
            records.append(row)
            try SpatialAudit.save(["provenance":"Generated PencilKit handwriting, actual OS recognition, actual local PDF import/retrieval/evidence/writer; no physical-device claim", "cases":records],to:output)
            print("BINDING INTEGRATION \(id) passed=\(row["passed"]!) \(row["error"] ?? row["draft"] ?? "")")
        }
    }
}
