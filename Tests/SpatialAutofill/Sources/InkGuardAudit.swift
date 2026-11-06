import Foundation
import PencilKit

enum InkGuardAudit {
    static func polygon(_ bounds: CGRect) -> [CGPoint] {
        [CGPoint(x:bounds.minX,y:bounds.minY),CGPoint(x:bounds.maxX,y:bounds.minY),CGPoint(x:bounds.maxX,y:bounds.maxY),CGPoint(x:bounds.minX,y:bounds.maxY)]
    }
    @MainActor static func run(output: URL) async throws {
        let left = InkAudit.ink("Alpha stores items.",x:60,y:110,width:370)
        let right = InkAudit.ink("Alpha stores items.",x:560,y:110,width:370)
        let annotation = InkAudit.ink("Limit: eight items.",x:80,y:150,width:370)
        let drawing = PKDrawing(strokes:left.strokes+right.strokes+annotation.strokes)
        let data = drawing.dataRepresentation()
        let bounds = drawing.bounds.insetBy(dx:-5,dy:-5)
        let single = try await SpatialInkReader().read(drawing:drawing,polygon:polygon(left.bounds.insetBy(dx:-3,dy:-3)))
        let empty = try await SpatialInkReader().read(drawing:PKDrawing(),polygon:polygon(bounds))
        precondition(single == nil && empty == nil)
        let preflightTask = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await SpatialCircleBridge.read(drawing:drawing,polygon:polygon(bounds),mode:.standard)
        }
        do { _ = try await preflightTask.value; preconditionFailure("Cancelled baseline bridge returned") } catch is CancellationError {}
        guard let first = try await SpatialInkReader().read(drawing:drawing,polygon:polygon(bounds)) else { preconditionFailure("Duplicate-text ink must retain independent geometry") }
        let lines = first.lines
        print("GUARD first: \(lines.map(\.text)) ids=\(first.selectedStrokeIDs.count) strokes=\(drawing.strokes.count)")
        precondition(lines.count == 3 && Set(first.lineStrokeIDs.flatMap { $0 }).count == drawing.strokes.count)
        precondition(lines.filter { $0.text.lowercased().contains("alpha") }.count == 2)
        precondition(Set(first.lineStrokeIDs[0]).isDisjoint(with:Set(first.lineStrokeIDs[1])))

        var moved = drawing
        moved.transform(using:CGAffineTransform(translationX:0,y:NotebookPaging.pageStride))
        guard let second = try await SpatialInkReader().read(drawing:moved,polygon:polygon(bounds.offsetBy(dx:0,dy:NotebookPaging.pageStride))) else { preconditionFailure("Page translation lost geometry") }
        print("GUARD translated: \(second.lines.map(\.rect))")
        let translated = second.lines
        precondition(lines.count == translated.count && translated.allSatisfy { $0.page == "p2" })
        for line in lines {
            let match = translated.first { abs($0.rect[0]-line.rect[0]) < 4 && abs($0.rect[1]-line.rect[1]) < 3 }!
            // PencilKit quantizes transformed render extents: allow four
            // document points, while requiring unchanged region ownership.
            precondition(zip(line.rect,match.rect).allSatisfy { abs($0-$1) < 4 })
        }
        let firstLayout = try SpatialGroups.validated(lines,transcript:GapTranscript(selected:first.text,context:first.context))
        let movedLayout = try SpatialGroups.validated(translated,transcript:GapTranscript(selected:second.text,context:second.context))
        precondition(firstLayout.groups == movedLayout.groups)
        precondition(drawing.dataRepresentation() == data)

        // The same words outside the circle remain context, not selected ink.
        let contextInk = InkAudit.ink("Alpha stores items.",x:60,y:50,width:370)
        let withContext = PKDrawing(strokes:drawing.strokes+contextInk.strokes)
        guard let separated = try await SpatialInkReader().read(drawing:withContext,polygon:polygon(bounds)) else { preconditionFailure("Context must remain separate") }
        precondition(Set(separated.selectedStrokeIDs) == Set(drawing.strokes.map(\.id)))
        precondition(Set(separated.lineStrokeIDs.flatMap { $0 }).isDisjoint(with:Set(contextInk.strokes.map(\.id))))

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await SpatialInkReader().read(drawing:drawing,polygon:polygon(bounds))
        }
        do { _ = try await task.value; preconditionFailure("Cancelled capture returned") } catch is CancellationError {}
        do { _ = try await SpatialCircleBridge.read(drawing:PKDrawing(),polygon:polygon(bounds),mode:.layoutAware); preconditionFailure("Empty capture succeeded") }
        catch CircleInkReader.ReadError.noInk {}
        try SpatialAudit.save(["passed":9,"checks":["multiple regions retain exact geometry","one selected region bypasses per-line OCR","empty geometry bypasses per-line OCR","pre-cancelled baseline bridge returns no result","duplicate text keeps distinct stroke ownership","page translation preserves local geometry","selected and nearby identical text remain separate","pre-cancelled capture returns no result","empty selection refuses"],"first":try JSONSerialization.jsonObject(with:JSONEncoder().encode(first)),"translated":try JSONSerialization.jsonObject(with:JSONEncoder().encode(second))],to:output)
        print("INK GUARDS 9/9")
    }
}
