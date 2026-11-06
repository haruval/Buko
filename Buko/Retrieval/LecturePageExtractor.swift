import Foundation
import PDFKit
import Vision

/// Native text is preserved when covered OCR agrees. Suspect lines get a sharper
/// OCR pass before an unresolved disagreement quarantines the page.
/// OCR also adds visible text outside native regions, including mixed pages.
nonisolated enum LecturePageExtractor {
    static let version = 4

    struct Result {
        let text: String
        let usedOCR: Bool
        var hasTextDisagreement = false
    }

    static func extract(_ page: PDFPage) throws -> Result {
        try Task.checkCancellation()
        let native = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard native.count <= 80_000 else { throw LectureLibrary.LibraryError.pageTextLimit }
        let nativeLines = page.selection(for: NSRange(location: 0, length: page.numberOfCharacters))?
            .selectionsByLine().filter { !($0.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { Line(text: $0.string ?? "", bounds: $0.bounds(for: page)) } ?? []
        let normalizedNative = normalized(native)
        let recognized = try recognize(page)
        var additions: [String] = []
        var recheckedLines: Set<Int> = []
        for line in recognized {
            let coveringIndices = nativeLines.indices.filter { index in
                let nativeLine = nativeLines[index]
                let intersection = nativeLine.bounds.insetBy(dx: -1, dy: -1).intersection(line.bounds)
                return !intersection.isNull && intersection.width * intersection.height >= line.bounds.width * line.bounds.height * 0.6
            }
            let text = normalized(line.text)
            guard !text.isEmpty else { continue }
            if !coveringIndices.isEmpty {
                // Compare only the covering native line, not matching text elsewhere
                // on the page. OCR may split a native line into shorter observations.
                // Compare words and signed/decimal numbers in prose. Single-letter
                // math symbols and punctuation are unreliable OCR comparisons; this
                // is a bounded disagreement detector, not full layout verification.
                let tokens = comparisonTokens(line.text)
                let visible = " " + tokens.joined(separator: " ") + " "
                if tokens.contains(where: { $0.filter(\.isLetter).count > 1 }),
                   !coveringIndices.contains(where: {
                       (" " + comparisonTokens(nativeLines[$0].text).joined(separator: " ") + " ").contains(visible)
                   }) {
                    // Whole-page OCR can merge grammar symbols into a prose word
                    // (e.g. E | E -> EIE), even with confidence 1. Re-read the actual
                    // pixels at higher resolution; never fuzzy-match away a changed
                    // word, number or negation. Bound the extra work per page.
                    guard coveringIndices.count == 1, let index = coveringIndices.first else {
                        return Result(text: "", usedOCR: true, hasTextDisagreement: true)
                    }
                    if !recheckedLines.contains(index) {
                        guard recheckedLines.count < 8,
                              try recheck(nativeLines[index], on: page) else {
                            return Result(text: "", usedOCR: true, hasTextDisagreement: true)
                        }
                        recheckedLines.insert(index)
                    }
                }
                continue
            }
            guard !normalizedNative.contains(text) else { continue }
            additions.append(line.text)
        }
        // Preserve PDFKit's text and order exactly; supplementary OCR follows it.
        // This is plain-text extraction, not reconstruction of table/column layout.
        return Result(text: ([native] + additions).filter { !$0.isEmpty }.joined(separator: "\n"),
                      usedOCR: !additions.isEmpty)
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func comparisonTokens(_ text: String) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "−", with: "-")
        let regex = try! NSRegularExpression(pattern: #"[-+]?\d+(?:[.,]\d+)*|[\p{L}]+(?:'[\p{L}]+)*"#)
        return regex.matches(in: folded, range: NSRange(folded.startIndex..., in: folded)).compactMap {
            guard let range = Range($0.range, in: folded) else { return nil }
            let token = String(folded[range])
            return token.contains(where: \.isNumber) || token.filter(\.isLetter).count > 1 ? token : nil
        }
    }

    struct Line {
        let text: String
        let bounds: CGRect
    }

    private static func recheck(_ native: Line, on page: PDFPage) throws -> Bool {
        let retry = try recognize(page, region: native.bounds.insetBy(dx: -4, dy: -3))
            .filter { native.bounds.insetBy(dx: -1, dy: -1).contains(CGPoint(x: $0.bounds.midX, y: $0.bounds.midY)) }
            .sorted { $0.bounds.minX < $1.bounds.minX }
        let expected = comparisonTokens(native.text)
        // A missing/partial OCR result cannot clear the warning. Require the
        // entire native line's comparable text, not a matching fragment.
        return !expected.isEmpty && retry.flatMap { comparisonTokens($0.text) } == expected
    }

    static func recognize(_ page: PDFPage, region: CGRect? = nil) throws -> [Line] {
        guard let pdfPage = page.pageRef else { throw ExtractionError.renderingFailed }
        // Render in unrotated PDF page space, matching PDFSelection bounds, even
        // when the PDF's display rotation is 90/180/270 degrees.
        let mediaBox = pdfPage.getBoxRect(.mediaBox)
        let bounds = region.map { $0.intersection(mediaBox) } ?? mediaBox
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
            throw ExtractionError.renderingFailed
        }
        // A retry renders just one line, so extra detail does not require a large
        // whole-page bitmap. Both passes retain hard raster-size bounds.
        let scale = region == nil ? min(2, 1800 / max(bounds.width, bounds.height))
            : min(4, 3600 / max(bounds.width, bounds.height))
        let width = max(1, Int(bounds.width * scale)), height = max(1, Int(bounds.height * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ExtractionError.renderingFailed
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Independent scales account for integer raster-size rounding.
        context.scaleBy(x: CGFloat(width) / bounds.width, y: CGFloat(height) / bounds.height)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        context.drawPDFPage(pdfPage)
        guard let image = context.makeImage() else { throw ExtractionError.renderingFailed }
        try Task.checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate; request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        try Task.checkCancellation()
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let rect = observation.boundingBox
            return Line(text: text, bounds: CGRect(x: bounds.minX + rect.minX * bounds.width,
                                                  y: bounds.minY + rect.minY * bounds.height,
                                                  width: rect.width * bounds.width, height: rect.height * bounds.height))
        }
    }

    private enum ExtractionError: LocalizedError {
        case renderingFailed
        var errorDescription: String? { "A PDF page could not be rendered to check for scanned text. The source was not reindexed." }
    }
}
