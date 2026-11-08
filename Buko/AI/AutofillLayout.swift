import Foundation
import PencilKit

/// Stages a complete insertion without touching the live drawing or persisted note.
/// Existing ink moves as intact vertical bands. Paths, masks and pressure are retained.
nonisolated enum AutofillLayout {
    struct Line {
        let text: String
        let frame: CGRect
    }
    struct Result {
        let original: PKDrawing
        let existing: PKDrawing
        let inserted: PKDrawing
        let lines: [Line]
        let pageCount: Int
        let missing: [String]
        let letterHeight: CGFloat
        let sampledGlyphCount: Int
        let fallbackGlyphCount: Int
        var rendering: String { sampledGlyphCount == 0 ? "handwritten-fallback-v5" : "note-samples-with-fallback-v7" }
        var drawing: PKDrawing { PKDrawing(strokes: existing.strokes + inserted.strokes) }
        var bounds: CGRect { lines.reduce(.null) { $0.union($1.frame) } }
    }
    enum LayoutError: LocalizedError {
        case invalidGeometry, oversizedInk, tooMuchText
        var errorDescription: String? {
            switch self {
            case .invalidGeometry: "This region can’t be placed safely. Circle a heading on one page and try again."
            case .oversizedInk: "A drawing below this region is taller than a page. Move it before accepting this fill."
            case .tooMuchText: "This fill is too large to insert at once. Try circling a smaller request."
            }
        }
    }

    static let margin: CGFloat = 36
    private static let strokeWidthScale: CGFloat = 0.81

    /// Returns a top coordinate on paper, choosing the previous page only when
    /// the entire band fits there. It never leaves a line across the page gutter.
    static func onPaper(_ y: CGFloat, height: CGFloat, minimumTop: CGFloat? = nil) throws -> CGFloat {
        guard y.isFinite, height.isFinite, height > 0,
              height <= NotebookPaging.pageHeight - margin * 2 else { throw LayoutError.oversizedInk }
        let page = max(0, Int(floor(max(0, y) / NotebookPaging.pageStride)))
        let rect = NotebookPaging.rect(for: page)
        let top = max(y, rect.minY + margin)
        if top + height <= rect.maxY - margin { return top }
        let above = rect.maxY - margin - height
        if let minimumTop, above >= minimumTop, top - above <= margin + NotebookPaging.pageGap {
            return above
        }
        return NotebookPaging.rect(for: page + 1).minY + margin
    }

    static func stage(text: String, drawing: PKDrawing, selection: [CGPoint], pageCount: Int,
                      samples: [String: HandwritingSample], letterHeight: CGFloat? = nil,
                      selectedText: String = "", target: String? = nil, targetBounds: CGRect? = nil) throws -> Result {
        guard !text.isEmpty, text.count <= 4_800 else { throw LayoutError.tooMuchText }
        let region = CircleGeometry.path(selection)
        let selected = drawing.strokes.filter {
            region.contains(CGPoint(x: $0.renderBounds.midX, y: $0.renderBounds.midY))
        }
        guard !selected.isEmpty else { throw LayoutError.invalidGeometry }
        let selectedBounds = selected.reduce(CGRect.null) { $0.union($1.renderBounds) }
        let startPage = max(0, Int(selectedBounds.minY / NotebookPaging.pageStride))
        guard selectedBounds.maxY <= NotebookPaging.rect(for: startPage).maxY,
              pageCount > startPage else { throw LayoutError.invalidGeometry }
        let anchor = AutofillTypography.anchor(drawing: drawing, selection: selection, selectedText: selectedText,
                                              target: target, recognizedBounds: targetBounds)
        let selectedRows = AutofillTypography.rows(selected)
        let style = AutofillTypography.style(selectedRows.last!, neighbors: selectedRows)
        let size = min(96, max(10, letterHeight ?? anchor?.height ?? style.height))
        let scale = size / HandwritingSample.capHeight
        // Measure the selected pen in document coordinates, including resized ink.
        let nearbyWidths: [CGFloat] = selected.flatMap { stroke -> [CGFloat] in
            let transformScale = hypot(stroke.transform.a, stroke.transform.b)
            return stroke.path.map { $0.size.width * transformScale }
        }.filter { $0.isFinite && $0 > 0 }.sorted()
        let penWidth: CGFloat = nearbyWidths.isEmpty ? 2.5 : nearbyWidths[nearbyWidths.count / 2]
        // Small letters need room inside loops even when the selected pen is broad.
        let letterPenWidth = min(penWidth * strokeWidthScale, size / 8)
        var split = anchor?.row.maxY ?? selectedBounds.maxY
        for stroke in drawing.strokes.sorted(by: { $0.renderBounds.minY < $1.renderBounds.minY }) {
            let b = stroke.renderBounds
            guard b.minY.isFinite, b.maxY.isFinite else { throw LayoutError.invalidGeometry }
            if b.minY <= split && b.maxY > split { split = b.maxY }
        }
        let continuationLeft = max(PageGeometry.pageOriginX + margin, anchor?.row.minX
            ?? min(selectedBounds.minX, PageGeometry.pageOriginX + PageGeometry.pageWidth * 0.35))
        let right = PageGeometry.pageOriginX + PageGeometry.pageWidth - margin
        var decoded: [String: PKDrawing] = [:]
        for (key, value) in samples where key.count == 1 {
            let source = try PKDrawing(data: value.drawingData)
            if let normalized = try? HandwritingSample.normalized(drawing: source, text: key) {
                decoded[key] = try PKDrawing(data: normalized.drawingData)
            }
        }
        let personal = Set(decoded.keys)
        var missing: [String] = []
        for key in Set(text.filter { !$0.isWhitespace }.map(String.init)).sorted() where decoded[key] == nil {
            if let sample = HandwrittenFont.sample(key) { decoded[key] = try PKDrawing(data: sample.drawingData) }
            else { missing.append(key) }
        }
        for (key, glyph) in decoded {
            let widths = glyph.strokes.flatMap { stroke in
                stroke.path.map { $0.size.width * hypot(stroke.transform.a, stroke.transform.b) * scale }
            }.filter { $0.isFinite && $0 > 0 }.sorted()
            guard !widths.isEmpty else { continue }
            // Handwritten paths describe the center of a pen stroke. Core Text
            // fallback paths trace both edges of a glyph and use a fine outline.
            let usesCenterline = personal.contains(key) || HandwrittenFont.letters[key] != nil
            let ratio = usesCenterline ? letterPenWidth / widths[widths.count / 2] : strokeWidthScale
            decoded[key] = PKDrawing(strokes: glyph.strokes.map { stroke in
                let points = stroke.path.map { point in
                    PKStrokePoint(location: point.location, timeOffset: point.timeOffset,
                        size: CGSize(width: point.size.width * ratio, height: point.size.height * ratio),
                        opacity: point.opacity, force: point.force, azimuth: point.azimuth, altitude: point.altitude)
                }
                return PKStroke(ink: stroke.ink, path: PKStrokePath(controlPoints: points, creationDate: stroke.path.creationDate),
                                transform: stroke.transform, mask: stroke.mask, randomSeed: stroke.randomSeed)
            })
        }
        let used = decoded.values
        let sampleTop = min(54, used.map { $0.bounds.minY }.min() ?? 54)
        let sampleBottom = max(126, used.map { $0.bounds.maxY }.max() ?? 126)
        let inkHeight = (sampleBottom - sampleTop) * scale
        let lineHeight = max(anchor?.lineSpacing ?? style.lineSpacing, inkHeight + size * 0.35)
        let proposedY = anchor?.top ?? split + size * 0.5
        let onPaperY = try onPaper(proposedY, height: inkHeight)
        let startsInline = anchor != nil && abs(onPaperY - proposedY) < 0.001
        let firstLeft = startsInline ? anchor!.x : continuationLeft
        let firstY = startsInline ? onPaperY : try onPaper(split + size * 0.5, height: inkHeight)
        let space = size * 0.45
        struct Unit { let text: String; let glyph: PKDrawing?; let advance: CGFloat; let personal: Bool }
        func unit(_ key: String) -> Unit {
            let glyph = decoded[key]
            return Unit(text: key, glyph: glyph,
                        advance: max(size * 0.14, (glyph?.bounds.width ?? 40) * scale) + size * 0.12,
                        personal: personal.contains(key))
        }
        var rows: [[Unit]] = []
        // Only the first line shares the heading's row. Every continuation,
        // paragraph and new-page line returns to the heading's left edge.
        func availableWidth() -> CGFloat { right - (rows.isEmpty ? firstLeft : continuationLeft) }
        for paragraph in text.components(separatedBy: .newlines) {
            var line: [Unit] = [], used: CGFloat = 0
            for word in paragraph.split(whereSeparator: \.isWhitespace).map(String.init) {
                let letters = word.map { unit(String($0)) }
                let wordWidth = letters.reduce(CGFloat.zero) { $0 + $1.advance }
                if !line.isEmpty && used + space + wordWidth > availableWidth() {
                    rows.append(line); line = []; used = 0
                }
                // Don't break a word just to occupy the short space after a
                // long heading. Start it intact on the full-width line below.
                if line.isEmpty && rows.isEmpty && firstLeft > continuationLeft && wordWidth > availableWidth() {
                    rows.append([])
                }
                if !line.isEmpty { line.append(Unit(text: " ", glyph: nil, advance: space, personal: false)); used += space }
                for letter in letters {
                    if used + letter.advance > availableWidth() && !line.isEmpty { rows.append(line); line = []; used = 0 }
                    guard letter.advance <= availableWidth() else { throw LayoutError.invalidGeometry }
                    line.append(letter); used += letter.advance
                }
            }
            rows.append(line)
        }
        var lines: [Line] = [], ink: [PKStroke] = []
        var sampledCount = 0, fallbackCount = 0
        var y = firstY
        var bottom: CGFloat = y
        for (index, row) in rows.enumerated() {
            y = try onPaper(y, height: inkHeight)
            let left = index == 0 ? firstLeft : continuationLeft
            let rowWidth = row.reduce(CGFloat.zero) { $0 + $1.advance }
            if !row.isEmpty {
                lines.append(Line(text: row.map(\.text).joined(), frame: CGRect(x: left, y: y, width: rowWidth, height: inkHeight)))
            }
            var x = left
            for letter in row {
                defer { x += letter.advance }
                guard let glyph = letter.glyph else { continue }
                if letter.personal { sampledCount += letter.text.count } else { fallbackCount += letter.text.count }
                let transform = CGAffineTransform(scaleX: scale, y: scale).concatenating(
                    CGAffineTransform(translationX: x - glyph.bounds.minX * scale, y: y - sampleTop * scale))
                ink += glyph.strokes.map { original in
                    PKStroke(ink: original.ink, path: original.path,
                             transform: original.transform.concatenating(transform), mask: original.mask,
                             randomSeed: original.randomSeed)
                }
            }
            bottom = y + inkHeight + size * 0.5
            y += lineHeight
            if index == 0 { y = max(y, split + size * 0.5) }
        }
        let lower = drawing.strokes.enumerated().filter { $0.element.renderBounds.minY > split }
            .sorted { $0.element.renderBounds.minY < $1.element.renderBounds.minY }
        var bands: [(indices: [Int], bounds: CGRect)] = []
        for (index, stroke) in lower {
            let b = stroke.renderBounds
            if let last = bands.last, b.minY <= last.bounds.maxY + 8 {
                bands[bands.count - 1].indices.append(index)
                bands[bands.count - 1].bounds = last.bounds.union(b)
            } else { bands.append(([index], b)) }
        }
        var moved = drawing.strokes
        var shift: CGFloat = 0
        for band in bands {
            // Leave existing whitespace when sufficient; move the remainder only
            // as far as necessary, propagating page-break displacement downward.
            let desired = max(band.bounds.minY + shift, bottom)
            let top = try onPaper(desired, height: band.bounds.height, minimumTop: bottom)
            shift = top - band.bounds.minY
            for index in band.indices {
                moved[index].transform = moved[index].transform.concatenating(
                    CGAffineTransform(translationX: 0, y: shift))
            }
            bottom = band.bounds.maxY + shift + 8
        }
        let finalBottom = max(lines.last?.frame.maxY ?? 0, moved.reduce(CGFloat.zero) { max($0, $1.renderBounds.maxY) })
        let count = max(pageCount, Int(floor(max(0, finalBottom - 0.001) / NotebookPaging.pageStride)) + 1)
        guard count <= pageCount + 32 else { throw LayoutError.tooMuchText }
        return Result(original: drawing, existing: PKDrawing(strokes: moved), inserted: PKDrawing(strokes: missing.isEmpty ? ink : []),
                      lines: lines, pageCount: count, missing: missing, letterHeight: size,
                      sampledGlyphCount: sampledCount, fallbackGlyphCount: fallbackCount)
    }
}
