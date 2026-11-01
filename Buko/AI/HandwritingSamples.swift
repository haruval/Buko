import Foundation
import PencilKit

nonisolated struct HandwritingSample: Codable, Sendable {
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

    enum SampleError: Error { case invalidInk }

    /// Normalize actual transformed ink, not its containing row. Whole words
    /// share the fallback's cap/x-height and baseline, including descenders.
    static func normalized(drawing: PKDrawing, text: String) throws -> HandwritingSample {
        guard !drawing.strokes.isEmpty, drawing.strokes.count <= 1_200,
              text.count <= 128, drawing.strokes.allSatisfy({ $0.mask == nil }) else { throw SampleError.invalidInk }
        func pathBounds(_ drawing: PKDrawing) -> CGRect {
            let points = drawing.strokes.flatMap { stroke in stroke.path.map { $0.location.applying(stroke.transform) } }
            guard let first = points.first else { return .null }
            return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { bounds, point in
                CGRect(x: min(bounds.minX, point.x), y: min(bounds.minY, point.y),
                    width: max(bounds.maxX, point.x) - min(bounds.minX, point.x),
                    height: max(bounds.maxY, point.y) - min(bounds.minY, point.y))
            }
        }
        let reference = text.compactMap { HandwrittenFont.sample(String($0)) }
            .compactMap { try? PKDrawing(data: $0.drawingData) }
            .reduce(CGRect.null) { $0.union(pathBounds($1)) }
        guard !reference.isNull else { throw SampleError.invalidInk }
        let bounds = pathBounds(drawing)
        guard bounds.height >= 0.5, bounds.width >= 0,
              [bounds.minX, bounds.minY, bounds.width, bounds.height].allSatisfy(\.isFinite) else { throw SampleError.invalidInk }
        let factor = reference.height / bounds.height
        let widths = drawing.strokes.flatMap { stroke in
            stroke.path.map { $0.size.width * hypot(stroke.transform.a, stroke.transform.b) * factor }
        }.filter { $0.isFinite && $0 > 0 }.sorted()
        guard let median = widths.dropFirst(widths.count / 2).first else { throw SampleError.invalidInk }
        let strokes = drawing.strokes.map { stroke in
            let strokeScale = hypot(stroke.transform.a, stroke.transform.b)
            let points = stroke.path.map { point -> PKStrokePoint in
                let location = point.location.applying(stroke.transform)
                let width = 7.2 * min(1.35, max(0.65, point.size.width * strokeScale * factor / median))
                return PKStrokePoint(location: CGPoint(x: 12 + (location.x - bounds.minX) * factor,
                    y: reference.minY + (location.y - bounds.minY) * factor), timeOffset: point.timeOffset,
                    size: CGSize(width: width, height: width), opacity: point.opacity,
                    force: point.force, azimuth: point.azimuth, altitude: point.altitude)
            }
            return PKStroke(ink: stroke.ink, path: PKStrokePath(controlPoints: points, creationDate: stroke.path.creationDate))
        }
        return try HandwritingSample(drawing: PKDrawing(strokes: strokes))
    }
}

/// Explicit alphabet input is user data, separate from regenerable note caches.
@MainActor final class PersonalAlphabetStore {
    static let letters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)
    private(set) var samples: [String: HandwritingSample] = [:]
    private let url: URL?
    private var loadError: Error?

    init(url: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("BukoPersonalAlphabet.json")) {
        self.url = url
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 4_000_000 else { throw HandwritingSample.SampleError.invalidInk }
            let loaded = try JSONDecoder().decode([String: HandwritingSample].self, from: Data(contentsOf: url))
            guard loaded.count <= 52 else { throw HandwritingSample.SampleError.invalidInk }
            for (key, sample) in loaded {
                guard Self.letters.contains(key) else { throw HandwritingSample.SampleError.invalidInk }
                _ = try HandwritingSample(drawing: PKDrawing(data: sample.drawingData))
            }
            samples = loaded
        } catch { loadError = error }
    }

    func save(_ drawing: PKDrawing, for letter: String) throws {
        if let loadError { throw loadError }
        guard Self.letters.contains(letter), let url else { throw HandwritingSample.SampleError.invalidInk }
        var next = samples
        next[letter] = try HandwritingSample.normalized(drawing: drawing, text: letter)
        let data = try JSONEncoder().encode(next)
        guard data.count <= 4_000_000 else { throw HandwritingSample.SampleError.invalidInk }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        samples = next
    }
}
