import AppKit
import Foundation
import PencilKit

@main
struct MonochromeInkChecks {
    static func main() throws {
        let points = [
            PKStrokePoint(location: CGPoint(x: 10, y: 20), timeOffset: 0, size: CGSize(width: 3, height: 3), opacity: 1, force: 0.7, azimuth: 0.4, altitude: 1),
            PKStrokePoint(location: CGPoint(x: 100, y: 200), timeOffset: 0.2, size: CGSize(width: 5, height: 5), opacity: 0.9, force: 0.8, azimuth: 0.5, altitude: 1)
        ]
        let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 0))
        let mask = NSBezierPath(rect: CGRect(x: 0, y: 0, width: 150, height: 250))
        let stroke = PKStroke(ink: PKInk(.pen, color: .white), path: path,
                              transform: CGAffineTransform(translationX: 25, y: 35), mask: mask, randomSeed: 42)
        let original = PKDrawing(strokes: [stroke])
        let saved = MonochromeInk.canonical(original)
        precondition(MonochromeInk.matches(saved.strokes[0].ink.color, .black))
        let dark = MonochromeInk.recolor(saved, to: .white)
        precondition(MonochromeInk.matches(dark.strokes[0].ink.color, .white))
        let reloaded = try PKDrawing(data: MonochromeInk.canonical(dark).dataRepresentation())
        let light = MonochromeInk.recolor(reloaded, to: .black)
        precondition(MonochromeInk.matches(light.strokes[0].ink.color, .black))
        precondition(light.strokes[0].path.count == path.count)
        precondition(light.strokes[0].path[0].location == points[0].location)
        precondition(abs(light.strokes[0].path[0].force - points[0].force) < 0.0001)
        precondition(light.strokes[0].transform == stroke.transform)
        precondition(light.strokes[0].mask?.bounds == mask.bounds)
        precondition(light.strokes[0].randomSeed == stroke.randomSeed)
        precondition(MonochromeInk.matches(original.strokes[0].ink.color, .white))
        if #available(macOS 27, *) {
            // Exercise a whole tall note, not just its visible first page.
            let allPages = PKDrawing(strokes: (0..<8).map { page in
                PKStroke(ink: PKInk(.pen, color: .black), path: path,
                         transform: CGAffineTransform(translationX: 25, y: CGFloat(page) * 1500),
                         mask: mask, randomSeed: 42)
            })
            var presentation = InkPresentation()
            let darkPages = presentation.refresh(allPages, to: .white)
            precondition(darkPages.strokes.count == allPages.strokes.count)
            for (source, displayed) in zip(allPages.strokes, darkPages.strokes) {
                precondition(source.id != displayed.id, "Off-screen strokes need fresh render identities too")
                precondition(MonochromeInk.matches(displayed.ink.color, .white))
                precondition(displayed.transform == source.transform && displayed.path.count == source.path.count)
                precondition(displayed.randomSeed == source.randomSeed && displayed.mask?.bounds == source.mask?.bounds)
            }
            let lightPages = presentation.refresh(darkPages, to: .black)
            let canonicalPages = presentation.canonical(lightPages)
            precondition(canonicalPages.strokes.map(\.id) == allPages.strokes.map(\.id))
            precondition(presentation.canonical(darkPages).strokes.map(\.id) == allPages.strokes.map(\.id),
                         "Older undo snapshots must still recover document identities")
            let reopened = try PKDrawing(data: canonicalPages.dataRepresentation())
            precondition(reopened.strokes.map(\.id) == allPages.strokes.map(\.id))
            precondition(reopened.strokes.allSatisfy { MonochromeInk.matches($0.ink.color, .black) })
        }
        print("Monochrome ink checks passed: legacy white ink, light/dark presentation, canonical persistence, and stroke geometry preservation.")
    }
}
