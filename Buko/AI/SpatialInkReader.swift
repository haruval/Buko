import Foundation
import PencilKit

/// Recognizes each spatial line from its own identified stroke set, preserving
/// physical ownership rather than pairing transcript rows with highlight boxes.
@available(iOS 27, macOS 27, *)
actor SpatialInkReader {
    nonisolated struct Capture: Codable, Sendable {
        let selectedStrokeIDs: [UUID]
        let text: String
        let context: String
        let lines: [SpatialLine]
        let lineStrokeIDs: [[UUID]]
        let boxes: [CGRect]
        let method: String
    }

    private static func selectedStrokes(drawing: PKDrawing, polygon: [CGPoint]) -> [PKStroke] {
        let region = CircleGeometry.path(polygon)
        return drawing.strokes.filter { stroke in
            guard stroke.renderBounds.intersects(region.boundingBoxOfPath) else { return false }
            let visible = stroke.path.interpolatedPoints(by: .distance(5)).filter { stroke.mask?.contains($0.location) ?? true }
            return !visible.isEmpty && Double(visible.filter { region.contains($0.location.applying(stroke.transform)) }.count) / Double(visible.count) >= 0.5
        }
    }

    func read(drawing: PKDrawing, polygon: [CGPoint]) async throws -> Capture? {
        try Task.checkCancellation()
        let region = CircleGeometry.path(polygon)
        let selected = Self.selectedStrokes(drawing: drawing, polygon: polygon)
        guard let runs = Self.strokeRuns(selected) else { return nil }
        // One geometry pass gates all per-line recognition. Unsupported layouts
        // return to the bridge, which alone owns the original-reader fallback.
        let runBounds = runs.map { $0.reduce(CGRect.null) { $0.union($1.renderBounds) } }
        let locations = runBounds.compactMap(Self.pageLocation)
        let measured = locations.enumerated().map { index, location in
            SpatialLine(blockID: "R\(index)", text: "", page: location.page, rect: location.rect)
        }
        guard locations.count == runs.count,
              (2...3).contains(SpatialGroups.measuredGroups(measured).count) else { return nil }
        try Task.checkCancellation()
        let ids = Set(selected.map(\.id))
        var texts: [String] = [], lines: [SpatialLine] = [], lineIDs: [[UUID]] = []
        for (index, run) in runs.enumerated() {
            try Task.checkCancellation()
            // Recognition sees only this geometric run. Repeated words in other
            // rows cannot steal its geometry or acquire its source stroke IDs.
            let bounds = runBounds[index]
            let inset = bounds.insetBy(dx:-3,dy:-3)
            let polygon = [CGPoint(x:inset.minX,y:inset.minY),CGPoint(x:inset.maxX,y:inset.minY),CGPoint(x:inset.maxX,y:inset.maxY),CGPoint(x:inset.minX,y:inset.maxY)]
            // Reuse the unchanged production recognizer, including its real
            // Vision fallback. Geometry belongs to this exact stroke run even
            // if PencilKit text recognition is unavailable or empty.
            let reading: CircleInkReader.Result
            do { reading = try await CircleInkReader().read(drawing:PKDrawing(strokes:run),polygon:polygon) }
            catch is CancellationError { throw CancellationError() }
            catch { try Task.checkCancellation(); return nil }
            let text = reading.text.trimmingCharacters(in:.whitespacesAndNewlines)
            try Task.checkCancellation()
            guard !text.isEmpty, !text.contains(where: \.isNewline), text.count <= 240 else { return nil }
            guard let location = Self.pageLocation(bounds) else { return nil }
            texts.append(text)
            lines.append(.init(blockID: "S\(index+1)", text: text, page: location.page, rect: location.rect))
            lineIDs.append(run.map(\.id))
        }
        guard Set(lineIDs.flatMap { $0 }) == ids, lineIDs.flatMap({ $0 }).count == ids.count else { return nil }
        let nearby = drawing.strokes.filter { !ids.contains($0.id) && $0.renderBounds.intersects(CircleInkReader.contextBounds(around: region.boundingBoxOfPath)) }
        let context: String
        if nearby.isEmpty { context = "" } else {
            let b = PKDrawing(strokes:nearby).bounds.insetBy(dx:-3,dy:-3)
            let polygon = [CGPoint(x:b.minX,y:b.minY),CGPoint(x:b.maxX,y:b.minY),CGPoint(x:b.maxX,y:b.maxY),CGPoint(x:b.minX,y:b.maxY)]
            do { context = try await CircleInkReader().read(drawing:PKDrawing(strokes:nearby),polygon:polygon).text }
            catch is CancellationError { throw CancellationError() }
            catch { context = "" }
        }
        try Task.checkCancellation()
        let text = texts.joined(separator: "\n")
        guard let normalized = try? SpatialGroups.coalescedWraps(lines, transcript: GapTranscript(selected: text, context: context)) else { return nil }
        let logicalIDs = normalized.origins.map { origin in origin.flatMap { id in lineIDs[lines.firstIndex { $0.blockID == id }!] } }
        let boxes = normalized.origins.map { origin in origin.reduce(CGRect.null) { bounds, id in
            bounds.union(runBounds[lines.firstIndex { $0.blockID == id }!])
        } }
        guard boxes.allSatisfy({ !$0.isNull && !$0.isInfinite }) else { return nil }
        try Task.checkCancellation()
        return .init(selectedStrokeIDs: selected.map(\.id),
                     text: normalized.lines.map(\.text).joined(separator: "\n"), context: context,
                     lines: normalized.lines, lineStrokeIDs: logicalIDs, boxes: boxes,
                     method: "Production PencilKit/Vision recognition per measured stroke run; conservative same-region wrap normalization")
    }

    static func pageLocation(_ bounds: CGRect) -> (page: String, rect: [Double])? {
        guard !bounds.isNull, !bounds.isInfinite, bounds.minY >= 0, bounds.width > 0, bounds.height > 0 else { return nil }
        let position = bounds.midY / NotebookPaging.pageStride
        guard position.isFinite, position < CGFloat(Int.max) else { return nil }
        let index = Int(position), page = NotebookPaging.rect(for: index)
        guard page.contains(bounds) else { return nil }
        return ("p\(index+1)", [Double((bounds.minX-page.minX)/page.width*1000),
            Double((bounds.minY-page.minY)/page.height*1000), Double(bounds.width/page.width*1000), Double(bounds.height/page.height*1000)])
    }

    static func strokeRuns(_ strokes: [PKStroke]) -> [[PKStroke]]? {
        guard (1...1200).contains(strokes.count), Set(strokes.map(\.id)).count == strokes.count else { return nil }
        let rects = strokes.map(\.renderBounds)
        let locations = rects.compactMap(pageLocation)
        guard locations.count == rects.count else { return nil }
        let heights = rects.map(\.height).filter { $0 >= 4 }.sorted()
        guard !heights.isEmpty else { return nil }
        let height = heights[heights.count/2]
        guard (4...80).contains(height) else { return nil }
        var parent = Array(strokes.indices)
        func root(_ i: Int) -> Int { var j = i; while parent[j] != j { j = parent[j] }; return j }
        for i in strokes.indices {
            for j in strokes.indices where j < i {
                let a = rects[i], b = rects[j]
                guard locations[i].page == locations[j].page else { continue }
                let dx = max(0, max(a.minX,b.minX)-min(a.maxX,b.maxX))
                let dy = max(0, max(a.minY,b.minY)-min(a.maxY,b.maxY))
                if dx <= height * 2 && dy <= height * 0.2 { parent[root(i)] = root(j) }
            }
        }
        var grouped: [Int: [PKStroke]] = [:]
        for i in strokes.indices { grouped[root(i), default: []].append(strokes[i]) }
        let runs = grouped.values.sorted {
            let a = PKDrawing(strokes:$0).bounds, b = PKDrawing(strokes:$1).bounds
            return a.minY == b.minY ? a.minX < b.minX : a.minY < b.minY
        }
        // A vertical connector/diagram must not turn several rows into one line.
        guard (1...32).contains(runs.count), runs.allSatisfy({ PKDrawing(strokes:$0).bounds.height <= height*2.5 }) else { return nil }
        return runs
    }
}
