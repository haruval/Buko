import Foundation
import PencilKit

@main struct CircleContextChecks {
    static func main() async throws {
        lineBreaks()
        let page = NotebookPaging.rect(for: 1)
        let selected = CGRect(x: page.minX + 65, y: page.minY + 145 + 20 * 48 - 10,
                              width: 440, height: 46)
        let context = CircleInkReader.contextBounds(around: selected)
        precondition(context.minX == page.minX && context.maxX == page.maxX)
        precondition(context.maxY <= page.maxY && context.minY >= page.minY)
        let top = CircleInkReader.contextBounds(around: CGRect(x: page.minX + 60, y: page.minY + 10, width: 80, height: 25))
        precondition(top.minY == page.minY, "Context must not include the previous page")
        guard #available(macOS 27, *) else { return }
        let polygon = [CGPoint(x: selected.minX, y: selected.minY), CGPoint(x: selected.maxX, y: selected.minY),
                       CGPoint(x: selected.maxX, y: selected.maxY), CGPoint(x: selected.minX, y: selected.maxY)]
        let result = try await CircleInkReader().read(drawing: SampleLecture.biology101.drawing(), polygon: polygon)
        let text = result.text.lowercased(), nearby = result.context.lowercased()
        print("SELECTED: \(result.text)\nCONTEXT: \(result.context)\nMETHOD: \(result.method)")
        precondition(text.contains("repeat") && text.contains("experiment"))
        precondition(!text.contains("evidence"), "Nearby content must not leak into selected transcript")
        precondition(nearby.contains("evidence") && nearby.contains("hypothesis"), "Read the complete nearby sentence")
        precondition(!nearby.contains("repeat an experiment"), "Selected strokes must be excluded from context")
        precondition(result.boxes.allSatisfy { $0.intersects(selected) }, "Highlight only selected handwriting")
        print("Nearby context checks passed: page bounds, real handwriting recognition, separate context and selected-only geometry.")
    }
    static func lineBreaks() {
        let text = "Keep appointment. Topic:"
        let boxes = ["Keep": [CGRect(x: 70, y: 140, width: 50, height: 25)],
                     "appointment.": [CGRect(x: 135, y: 142, width: 130, height: 23)],
                     "Topic:": [CGRect(x: 70, y: 190, width: 70, height: 25)]]
        precondition(CircleInkReader.restoringLineBreaks(in: text, wordBounds: boxes) == "Keep appointment.\nTopic:")
        let structured = "Keep appointment.\nTopic:"
        precondition(CircleInkReader.restoringLineBreaks(in: structured, wordBounds: [:]) == structured)
        var missing = boxes; missing["Topic:"] = []
        precondition(CircleInkReader.restoringLineBreaks(in: text, wordBounds: missing) == text)
        var ambiguous = boxes; ambiguous["Keep"]!.append(CGRect(x: 80, y: 300, width: 50, height: 25))
        precondition(CircleInkReader.restoringLineBreaks(in: text, wordBounds: ambiguous) == text)
        precondition(CircleInkReader.restoringLineBreaks(in: "Keep Keep", wordBounds: boxes) == "Keep Keep")
        var inline = boxes; inline["Topic:"] = [CGRect(x: 280, y: 190, width: 70, height: 25)]
        precondition(CircleInkReader.restoringLineBreaks(in: text, wordBounds: inline) == text, "Vertical annotations are not row resets")
        print("Line-break checks passed: preserve tokens/order, retain existing rows, decline incomplete/duplicate geometry.")
    }

}
