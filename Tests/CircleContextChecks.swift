import Foundation
import PencilKit

@main struct CircleContextChecks {
    static func main() async throws {
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
}
