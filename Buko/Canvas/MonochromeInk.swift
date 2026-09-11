import PencilKit
#if canImport(UIKit)
import UIKit
typealias InkColor = UIColor
#else
import AppKit
typealias InkColor = NSColor
#endif

/// Saved ink is always black. Presentation is an explicit recoloring of the same
/// stroke values, preserving their path, pressure, transform, mask, and random seed.
nonisolated enum MonochromeInk {
    static func matches(_ lhs: InkColor, _ rhs: InkColor) -> Bool {
        #if canImport(UIKit)
        var left = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        var right = left
        guard lhs.getRed(&left.0, green: &left.1, blue: &left.2, alpha: &left.3),
              rhs.getRed(&right.0, green: &right.1, blue: &right.2, alpha: &right.3) else { return false }
        let differences = [left.0 - right.0, left.1 - right.1, left.2 - right.2, left.3 - right.3]
        #else
        guard let left = lhs.usingColorSpace(.deviceRGB), let right = rhs.usingColorSpace(.deviceRGB) else { return false }
        let differences = [left.redComponent - right.redComponent, left.greenComponent - right.greenComponent,
                           left.blueComponent - right.blueComponent, left.alphaComponent - right.alphaComponent]
        #endif
        return differences.allSatisfy { abs($0) < 0.0001 }
    }

    static func recolor(_ drawing: PKDrawing, to color: InkColor) -> PKDrawing {
        PKDrawing(strokes: drawing.strokes.map { original in
            var stroke = original
            stroke.ink = PKInk(original.ink.inkType, color: color)
            return stroke
        })
    }

    static func canonical(_ drawing: PKDrawing) -> PKDrawing {
        recolor(drawing, to: .black)
    }
}

/// PencilKit 27 can retain off-screen tiles after an ink-only change. Refresh
/// every displayed stroke's render identity, while retaining its document ID for
/// persistence and for old drawings restored by undo. This state lives per note.
nonisolated struct InkPresentation {
    private var documentIDs: [UUID: UUID] = [:]

    mutating func refresh(_ drawing: PKDrawing, to color: InkColor) -> PKDrawing {
        guard #available(iOS 27, macOS 27, *) else { return MonochromeInk.recolor(drawing, to: color) }
        return PKDrawing(strokes: drawing.strokes.map { original in
            let documentID = documentIDs[original.id] ?? original.id
            let displayID = UUID()
            documentIDs[displayID] = documentID
            return copy(original, color: color, id: displayID)
        })
    }

    func canonical(_ drawing: PKDrawing) -> PKDrawing {
        guard #available(iOS 27, macOS 27, *) else { return MonochromeInk.canonical(drawing) }
        return PKDrawing(strokes: drawing.strokes.map { original in
            copy(original, color: .black, id: documentIDs[original.id] ?? original.id)
        })
    }

    @available(iOS 27, macOS 27, *)
    private func copy(_ stroke: PKStroke, color: InkColor, id: UUID) -> PKStroke {
        PKStroke(ink: PKInk(stroke.ink.inkType, color: color), path: stroke.path,
                 transform: stroke.transform, mask: stroke.mask, randomSeed: stroke.randomSeed,
                 id: id, renderGroupID: stroke.renderGroupID, renderState: stroke.renderState)
    }
}
