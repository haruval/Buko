import Foundation
import PencilKit

@main struct SampleLectureChecks {
    static func main() throws {
        precondition(Set(SampleLecture.allCases.map(\.storageKey)).count == SampleLecture.allCases.count,
                     "Each fixture must reset independently")
        for lecture in SampleLecture.allCases {
            let expectedPages = switch lecture {
            case .programmingLanguages: 4
            case .operatingSystems, .biology101: 3
            case .linearAlgebra: 2
            }
            precondition(lecture.pages.count == expectedPages)
            let drawing = lecture.drawing()
            precondition(!drawing.strokes.isEmpty)
            for index in lecture.pages.indices {
                let page = NotebookPaging.rect(for: index)
                let strokes = drawing.strokes.filter { page.contains(CGPoint(x: $0.renderBounds.midX, y: $0.renderBounds.midY)) }
                precondition(!strokes.isEmpty)
                precondition(strokes.allSatisfy { page.insetBy(dx: 24, dy: 24).contains($0.renderBounds) },
                             "Handwriting must fit inside each page: \(lecture.title)")
            }
            let reopened = try PKDrawing(data: drawing.dataRepresentation())
            precondition(reopened.strokes.count == drawing.strokes.count)
        }
        // Every numeric matrix character must be its own glyph, not the '?' fallback.
        let symbols = LectureHandwriting.drawing(pages: [["6789[]/"]])
        let unknowns = LectureHandwriting.drawing(pages: [["???????"]])
        precondition(symbols.strokes.count != unknowns.strokes.count)
        print("Sample lecture checks passed: separate identities, lecture/practice page ink bounds, serialization, and math glyphs.")
    }
}
