import PDFKit
import SwiftUI

struct LectureSourceThumbnail: View {
    let noteID: UUID
    let passage: LecturePassage
    let quote: String
    @State private var image: UIImage?
    @State private var unavailable = false
    private static let renderer = LectureThumbnailRenderer()

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 200)
                    .background(.white).clipShape(.rect(cornerRadius: 10))
                    .accessibilityLabel("PDF page \(passage.page), retrieved passage highlighted")
                    .accessibilityIdentifier("autofillSourceThumbnail")
            } else if unavailable {
                Label("Page crop unavailable · open PDF to inspect", systemImage: "doc.text.magnifyingglass")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 100)
                    .accessibilityLabel("Loading source page")
            }
        }
        .task(id: "\(noteID)|\(passage.id)|\(quote)") {
            image = nil; unavailable = false
            do {
                let url = try await LectureLibrary.shared.pdfURL(noteID: noteID, documentID: passage.documentID)
                let data = try await Self.renderer.render(url: url, page: passage.page, quote: quote, usedOCR: passage.usedOCR)
                try Task.checkCancellation()
                image = UIImage(data: data)
                unavailable = image == nil
            } catch is CancellationError { }
            catch { unavailable = true }
        }
    }
}

/// Each request owns its PDFKit document off the UI thread. Highlights are
/// resolved against exact source text, never a model-generated location.
actor LectureThumbnailRenderer {
    enum RenderError: Error { case missingPage, missingText, invalidGeometry }

    static func range(of quote: String, in text: String) -> NSRange? {
        let words = quote.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty, text.count <= 80_000 else { return nil }
        let pattern = words.map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: #"\s+"#)
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return match.range
    }

    func render(url: URL, page number: Int, quote: String, usedOCR: Bool) throws -> Data {
        try Task.checkCancellation()
        guard number > 0, let document = PDFDocument(url: url), let page = document.page(at: number - 1),
              let pdf = page.pageRef else { throw RenderError.missingPage }
        var highlights: [CGRect] = []
        if let text = page.string, let range = Self.range(of: quote, in: text) {
            highlights = page.selection(for: range)?.selectionsByLine().map { $0.bounds(for: page) } ?? []
        }
        if highlights.isEmpty, usedOCR {
            let lines = try LecturePageExtractor.recognize(page)
            let text = lines.map(\.text).joined(separator: "\n")
            if let match = Self.range(of: quote, in: text) {
                var offset = 0
                for line in lines {
                    let length = (line.text as NSString).length
                    if NSIntersectionRange(match, NSRange(location: offset, length: length)).length > 0 { highlights.append(line.bounds) }
                    offset += length + 1
                }
            }
        }
        let pageBounds = pdf.getBoxRect(.cropBox)
        highlights = highlights.map { $0.intersection(pageBounds) }.filter { !$0.isNull && !$0.isEmpty }
        guard !highlights.isEmpty else { throw RenderError.missingText }
        var crop = highlights.reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -18, dy: -14)
        let minimumWidth = min(pageBounds.width, 280)
        if crop.width < minimumWidth { crop = crop.insetBy(dx: -(minimumWidth - crop.width) / 2, dy: 0) }
        crop = crop.intersection(pageBounds)
        guard !crop.isEmpty, [crop.minX, crop.minY, crop.width, crop.height].allSatisfy(\.isFinite) else { throw RenderError.invalidGeometry }
        let scale = min(2, 1000 / max(crop.width, crop.height))
        let width = max(1, Int(ceil(crop.width * scale))), height = max(1, Int(ceil(crop.height * scale)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw RenderError.invalidGeometry }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: CGFloat(width) / crop.width, y: CGFloat(height) / crop.height)
        context.translateBy(x: -crop.minX, y: -crop.minY)
        context.drawPDFPage(pdf)
        context.setBlendMode(.multiply)
        context.setFillColor(CGColor(red: 1, green: 0.86, blue: 0.15, alpha: 0.36))
        for rect in highlights { context.fill(rect.insetBy(dx: -1, dy: -1)) }
        try Task.checkCancellation()
        guard let image = context.makeImage(), let data = UIImage(cgImage: image).pngData() else { throw RenderError.invalidGeometry }
        return data
    }
}
