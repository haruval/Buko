import Foundation
import PencilKit

nonisolated struct HandwritingSample: Sendable {
    static let baseline: CGFloat = 126
    static let capHeight: CGFloat = 72
    let drawingData: Data

    init(drawing: PKDrawing) throws {
        let bounds = drawing.bounds
        guard !drawing.strokes.isEmpty, bounds.width > 0, bounds.height > 0,
              bounds.minX >= 0, bounds.minY >= 0,
              bounds.maxX <= 2_400, bounds.maxY <= 216 else { throw SampleError.invalidInk }
        drawingData = MonochromeInk.canonical(drawing).dataRepresentation()
    }

    /// Preserve the complete pen paths, including dots and descenders. Scaling is
    /// relative to the writing's cap height, never the individual glyph's height.
    init(drawing: PKDrawing, referenceTop: CGFloat, referenceHeight: CGFloat) throws {
        guard referenceHeight >= 4, referenceHeight <= 160 else { throw SampleError.invalidInk }
        let scale = Self.capHeight / referenceHeight
        let transform = CGAffineTransform(scaleX: scale, y: scale).concatenating(
            CGAffineTransform(translationX: 12 - drawing.bounds.minX * scale, y: 54 - referenceTop * scale))
        try self.init(drawing: PKDrawing(strokes: drawing.strokes.map {
            var stroke = $0; stroke.transform = stroke.transform.concatenating(transform); return stroke
        }))
    }
    enum SampleError: Error { case invalidInk }
}
