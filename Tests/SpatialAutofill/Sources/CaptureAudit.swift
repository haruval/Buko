import Foundation
import PencilKit

actor CaptureAuditCounter {
    static let shared = CaptureAuditCounter()
    private var calls: [Int] = []
    private var failFirst = false
    private var cancelFirst = false
    func reset(fail: Bool = false, cancel: Bool = false) { calls = []; failFirst = fail; cancelFirst = cancel }
    func begin(strokes: Int) -> Bool {
        calls.append(strokes)
        if cancelFirst && calls.count == 1 { withUnsafeCurrentTask { $0?.cancel() } }
        return failFirst && calls.count == 1
    }
    func snapshot() -> [Int] { calls }
}

enum CaptureAudit {
    struct Input: Decodable { let id: String; let path: String; let selectedIDs: [UUID] }
    @MainActor static func run(args: [String], output: URL) async throws {
        let inputs: [Input]
        if let index = args.firstIndex(of: "--capture-inputs"), args.indices.contains(index+1) {
            inputs = try JSONDecoder().decode([Input].self, from: Data(contentsOf:URL(fileURLWithPath:args[index+1])))
        } else {
            let root = output.deletingPathExtension()
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            var generated: [Input] = []
            for fixture in [InkAudit.fixtures[0], InkAudit.fixtures[2], InkAudit.fixtures[5]] {
                let selected = PKDrawing(strokes:fixture.rows.flatMap { InkAudit.ink($0.0,x:$0.1,y:$0.2,width:370).strokes })
                let context = InkAudit.ink(fixture.context,x:60,y:50,width:870)
                let drawing = PKDrawing(strokes:selected.strokes+context.strokes)
                let path = root.appendingPathComponent(fixture.id+".drawing")
                try drawing.dataRepresentation().write(to:path)
                generated.append(.init(id:fixture.id,path:path.path,selectedIDs:selected.strokes.map(\.id)))
                if generated.count == 1, let run = SpatialInkReader.strokeRuns(selected.strokes)?.first {
                    generated.append(.init(id:"single-region",path:path.path,selectedIDs:run.map(\.id)))
                }
            }
            inputs = generated
        }
        var rows: [[String:Any]] = []
        for repetition in 1...3 {
            for (index,input) in inputs.enumerated() {
                let drawing = try PKDrawing(data:Data(contentsOf:URL(fileURLWithPath:input.path)))
                let ids = Set(input.selectedIDs)
                let selected = drawing.strokes.filter { ids.contains($0.id) }
                precondition(selected.count == ids.count)
                let b = PKDrawing(strokes:selected).bounds.insetBy(dx:-5,dy:-5)
                let polygon = InkGuardAudit.polygon(b)
                for candidate in ((index+repetition).isMultiple(of:2) ? [false,true] : [true,false]) {
                    await CaptureAuditCounter.shared.reset()
                    let start = ProcessInfo.processInfo.systemUptime
                    let result = try await SpatialCircleBridge.read(drawing:drawing,polygon:polygon,
                        mode:candidate ? .layoutAware : .standard)
                    let elapsed = ProcessInfo.processInfo.systemUptime-start
                    let calls = await CaptureAuditCounter.shared.snapshot()
                    precondition(!calls.isEmpty, "Prepare with --instrument-reader")
                    if !candidate || input.id == "single-region" { precondition(calls.count == 1) }
                    rows.append(["id":input.id,"repetition":repetition,"candidate":candidate,
                        "seconds":elapsed,"readerCallStrokeCounts":await CaptureAuditCounter.shared.snapshot(),
                        "selectedStrokes":selected.count,"drawingStrokes":drawing.strokes.count,
                        "spatial":result.lines != nil,"method":result.original.method,
                        "text":result.original.text,"context":result.original.context])
                    try SpatialAudit.save(["records":rows],to:output)
                }
            }
        }
        let input = inputs[0]
        let drawing = try PKDrawing(data:Data(contentsOf:URL(fileURLWithPath:input.path)))
        let ids = Set(input.selectedIDs)
        let selected = drawing.strokes.filter { ids.contains($0.id) }
        let polygon = InkGuardAudit.polygon(PKDrawing(strokes:selected).bounds.insetBy(dx:-5,dy:-5))
        await CaptureAuditCounter.shared.reset(fail:true)
        let fallback = try await SpatialCircleBridge.read(drawing:drawing,polygon:polygon,mode:.layoutAware)
        let calls = await CaptureAuditCounter.shared.snapshot()
        precondition(fallback.lines == nil && calls.count == 2 && calls[1] == drawing.strokes.count)
        await CaptureAuditCounter.shared.reset()
        let expected = try await SpatialCircleBridge.read(drawing:drawing,polygon:polygon,mode:.standard)
        precondition(fallback.original.text == expected.original.text && fallback.original.context == expected.original.context
            && fallback.original.boxes == expected.original.boxes && fallback.original.method == expected.original.method)
        await CaptureAuditCounter.shared.reset(fail:true,cancel:true)
        do {
            _ = try await SpatialCircleBridge.read(drawing:drawing,polygon:polygon,mode:.layoutAware)
            preconditionFailure("Cancelled failed line returned a result")
        } catch is CancellationError { }
        let cancelledCalls = await CaptureAuditCounter.shared.snapshot()
        precondition(cancelledCalls.count == 1, "Cancellation must not launch fallback recognition")
        try SpatialAudit.save(["records":rows,"faultInjection":[
            "scope":"First measured-run reader throws unreadable; subsequent original readers are real.",
            "readerCallStrokeCounts":calls,"spatial":fallback.lines != nil,"text":fallback.original.text,
            "singleWholeDrawingFallbackConfirmed":true,"fallbackReadingPreserved":true,"cancelledBeforeFallback":cancelledCalls.count == 1]],to:output)
        print("CAPTURE CHECKS 24 paired captures; one fallback, original reading preserved, cancellation stops fallback")
    }
}
