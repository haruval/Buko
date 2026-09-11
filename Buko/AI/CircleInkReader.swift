import PencilKit
import Vision
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Snapshot work runs off the input actor. No mutation of the live drawing.
actor CircleInkReader {
    struct Result: Sendable {
        var text: String
        var context: String
        var boxes: [CGRect]
        var method: String
    }

    @available(iOS 27, macOS 27, *)
    func read(drawing: PKDrawing, polygon: [CGPoint]) async throws -> Result {
        let region = CircleGeometry.path(polygon)
        let bounds = region.boundingBoxOfPath
        let candidates = drawing.strokes.filter { $0.renderBounds.intersects(bounds) }
        let selected = candidates.filter { stroke in
            let samples = Array(stroke.path.interpolatedPoints(by: .distance(5)))
            let visible = samples.filter { point in
                stroke.mask?.contains(point.location) ?? true
            }
            guard !visible.isEmpty else { return false }
            let inside = visible.filter { region.contains($0.location.applying(stroke.transform)) }.count
            return Double(inside) / Double(visible.count) >= 0.5
        }
        guard !selected.isEmpty else { throw ReadError.noInk }
        let ids = Set(selected.map(\.id))
        let pageIndex = max(0, Int(bounds.midY / NotebookPaging.pageStride))
        let contextRect = bounds.insetBy(dx: -100, dy: -160).intersection(NotebookPaging.rect(for: pageIndex))
        let nearby = drawing.strokes.filter { ids.contains($0.id) || $0.renderBounds.intersects(contextRect) }
        let recognizer = PKStrokeRecognizer(preferredLanguages: [Locale.Language(identifier: "en")])
        await recognizer.updateDrawing(PKDrawing(strokes: nearby))
        try Task.checkCancellation()
        let text = (await recognizer.recognizedText(strokeIDs: ids) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        try Task.checkCancellation()
        if !text.isEmpty {
            var boxes: [CGRect] = []
            for word in Set(text.split(whereSeparator: \.isWhitespace).map(String.init)).sorted().prefix(48) {
                let matches = await recognizer.search(word)
                try Task.checkCancellation()
                boxes += matches.filter { !$0.strokes.isDisjoint(with: ids) }.map(\.bounds)
            }
            let context = await recognizer.recognizedText() ?? ""
            return Result(text: text, context: context,
                boxes: boxes.isEmpty ? selected.map(\.renderBounds) : boxes, method: "PencilKit strokes")
        }
        // Vision is a real OCR fallback for unavailable/empty stroke recognition.
        // Call Vision directly so we retain text geometry; OCRTool only returns text.
        let result = try rasterRead(PKDrawing(strokes: selected))
        guard !result.text.isEmpty else { throw ReadError.unreadable }
        try Task.checkCancellation()
        let context = (try? rasterRead(PKDrawing(strokes: nearby)).text) ?? ""
        return Result(text: result.text, context: context, boxes: result.boxes, method: "Vision OCR fallback")
    }

    private func rasterRead(_ drawing: PKDrawing) throws -> (text: String, boxes: [CGRect]) {
        let canonical = MonochromeInk.canonical(drawing)
        let rect = canonical.bounds.insetBy(dx: -14, dy: -14)
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { throw ReadError.noInk }
        let scale = min(3, 1800 / max(rect.width, rect.height))
        #if canImport(UIKit)
        let ink = canonical.image(from: rect, scale: scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let size = CGSize(width: rect.width * scale, height: rect.height * scale)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            ink.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let cgImage = image.cgImage else { throw ReadError.unreadable }
        #else
        let ink = canonical.image(from: rect, scale: scale)
        var imageRect = CGRect(origin: .zero, size: ink.size)
        guard let cgImage = ink.cgImage(forProposedRect: &imageRect, context: nil, hints: nil) else { throw ReadError.unreadable }
        #endif
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        let lines = (request.results ?? []).sorted {
            abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.02
                ? $0.boundingBox.midY > $1.boundingBox.midY : $0.boundingBox.minX < $1.boundingBox.minX
        }
        let boxes = lines.map { observation -> CGRect in
            let b = observation.boundingBox
            return CGRect(x: rect.minX + b.minX * rect.width, y: rect.minY + (1 - b.maxY) * rect.height,
                          width: b.width * rect.width, height: b.height * rect.height)
        }
        return (lines.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n"), boxes)
    }

    enum ReadError: LocalizedError {
        case noInk, unreadable
        var errorDescription: String? {
            switch self {
            case .noInk: "No ink inside this circle. Circle a heading or a few handwritten lines."
            case .unreadable: "The handwriting recognizers couldn’t read this region. Try a larger circle or clearer lettering."
            }
        }
    }
}
