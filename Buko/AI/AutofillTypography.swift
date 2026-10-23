import PencilKit

/// Geometry comes from real ink; transcript text is used only to identify the
/// unfinished heading. No character-width guesses are used to locate its colon.
nonisolated enum AutofillTypography {
    struct Row: Sendable { var bounds: CGRect; var strokes: [PKStroke] }
    struct Style: Sendable {
        let height: CGFloat
        let top: CGFloat
        let lineSpacing: CGFloat
    }
    struct Anchor: Sendable {
        let row: CGRect
        let x: CGFloat
        let top: CGFloat
        let height: CGFloat
        let lineSpacing: CGFloat
    }

    static func rows(_ strokes: [PKStroke]) -> [Row] {
        var rows: [Row] = []
        for stroke in strokes.sorted(by: { $0.renderBounds.minY < $1.renderBounds.minY }) {
            let b = stroke.renderBounds
            guard b.width.isFinite, b.height.isFinite, !b.isEmpty else { continue }
            if let last = rows.last, b.minY < last.bounds.maxY + 3 {
                rows[rows.count - 1].bounds = last.bounds.union(b)
                rows[rows.count - 1].strokes.append(stroke)
            } else { rows.append(Row(bounds: b, strokes: [stroke])) }
        }
        return rows
    }

    static func style(_ row: Row, neighbors: [Row]) -> Style {
        let heights = row.strokes.map { $0.renderBounds.height }
            .filter { $0 >= max(4, row.bounds.height * 0.28) && $0 <= 160 }.sorted()
        let height = min(96, max(10, heights.isEmpty ? row.bounds.height : heights[(heights.count - 1) * 3 / 4]))
        let gaps = zip(neighbors, neighbors.dropFirst()).map { $1.bounds.minY - $0.bounds.minY }
            .filter { $0 >= height * 1.35 && $0 <= height * 3 }.sorted()
        return Style(height: height, top: row.bounds.minY,
                     lineSpacing: gaps.isEmpty ? height * 1.8 : gaps[gaps.count / 2])
    }

    /// A colon's two compact dots give a geometric spacing example without
    /// estimating character widths from OCR. Ambiguous marks simply use a space.
    static func colonGap(in row: Row, height: CGFloat) -> CGFloat? {
        let dots = row.strokes.map(\.renderBounds).filter { $0.width < height * 0.35 && $0.height < height * 0.35 }
        for (index, a) in dots.enumerated() {
            for b in dots.dropFirst(index + 1) where abs(a.midX - b.midX) < height * 0.15 {
                let separation = abs(a.midY - b.midY)
                guard separation > height * 0.25 && separation < height * 0.85 else { continue }
                let colon = a.union(b)
                if let next = row.strokes.map(\.renderBounds).filter({ $0.minX > colon.maxX + 1 }).min(by: { $0.minX < $1.minX }) {
                    let gap = next.minX - colon.maxX
                    if gap >= height * 0.25 && gap <= height * 1.6 { return gap }
                }
            }
        }
        return nil
    }

    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    static func anchor(drawing: PKDrawing, selection: [CGPoint], selectedText: String,
                       target: String?, recognizedBounds: CGRect? = nil) -> Anchor? {
        let path = CircleGeometry.path(selection)
        let selected = drawing.strokes.filter { path.contains(CGPoint(x: $0.renderBounds.midX, y: $0.renderBounds.midY)) }
        let selectedRows = rows(selected)
        guard let last = selectedRows.last else { return nil }
        let textLines = selectedText.split(whereSeparator: \.isNewline).map { normalized(String($0)) }
        var heading = normalized(target ?? textLines.last ?? "")
        if let lastText = textLines.last, lastText.hasSuffix(":"), String(lastText.dropLast()) == heading {
            heading = lastText
        }
        guard heading.hasSuffix(":"), heading.count <= 100,
              heading.filter({ $0 == ":" }).count == 1 else { return nil }
        let candidate: Row
        if let recognizedBounds {
            guard let match = selectedRows.first(where: { $0.bounds.intersects(recognizedBounds) }) else { return nil }
            candidate = match
        } else {
            // An exact final transcript line maps to an exact physical final row.
            // A one-line OCR transcript spanning multiple ink rows is ambiguous.
            guard textLines.count == selectedRows.count, textLines.last == heading else { return nil }
            candidate = last
        }
        let page = NotebookPaging.rect(for: max(0, Int(candidate.bounds.midY / NotebookPaging.pageStride)))
        let nearby = rows(drawing.strokes.filter { $0.renderBounds.intersects(page) })
        let style = style(candidate, neighbors: nearby)
        let preceding = nearby.filter { $0.bounds.maxY < candidate.bounds.minY }.suffix(3)
        let gaps = preceding.compactMap { colonGap(in: $0, height: style.height) }
        let x = candidate.bounds.maxX + (gaps.last ?? style.height * 0.6)
        guard x + style.height * 4 < page.maxX - AutofillLayout.margin else { return nil }
        // Leave an adjacent column/answer alone. A fallback below the selection is
        // safer than interpreting existing ink to the right as expendable space.
        let lane = CGRect(x: x, y: candidate.bounds.minY, width: page.maxX - x,
                          height: candidate.bounds.height)
        guard !drawing.strokes.contains(where: { $0.renderBounds.intersects(lane) }) else { return nil }
        return Anchor(row: candidate.bounds, x: x, top: style.top, height: style.height, lineSpacing: style.lineSpacing)
    }
}
