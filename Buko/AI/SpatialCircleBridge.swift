import Foundation
import PencilKit

/// Routes one captured request through bounded spatial reading or the original reader.
@available(iOS 27, macOS 27, *)
nonisolated enum SpatialCircleBridge {
    struct Reading: Sendable {
        let original: CircleInkReader.Result
        let lines: [SpatialLine]?
    }

    static func read(drawing: PKDrawing, polygon: [CGPoint], mode: AutofillPlanningMode) async throws -> Reading {
        try Task.checkCancellation()
        if mode == .standard {
            return try await fallback(drawing: drawing, polygon: polygon)
        }
        guard let capture = try await SpatialInkReader().read(drawing: drawing, polygon: polygon) else {
            return try await fallback(drawing: drawing, polygon: polygon)
        }
        try Task.checkCancellation()
        return .init(original: .init(text: capture.text, context: capture.context,
                                    boxes: capture.boxes, method: capture.method), lines: capture.lines)
    }

    private static func fallback(drawing: PKDrawing, polygon: [CGPoint]) async throws -> Reading {
        try Task.checkCancellation()
        let original = try await CircleInkReader().read(drawing: drawing, polygon: polygon)
        try Task.checkCancellation()
        return .init(original: original, lines: nil)
    }
}
