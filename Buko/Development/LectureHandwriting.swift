import PencilKit

/// Shared synthetic hand-lettering for editable development fixtures only.
enum LectureHandwriting {
    static func drawing(pages: [[String]]) -> PKDrawing {
        var strokes: [PKStroke] = []
        var serial = 0
        for (page, lines) in pages.enumerated() {
            for (line, text) in lines.enumerated() {
                let origin = CGPoint(x: PageGeometry.pageOriginX + 78,
                                     y: NotebookPaging.rect(for: page).minY + 145 + CGFloat(line) * 48)
                var x = origin.x
                for (column, character) in text.enumerated() {
                    let key = String(character).lowercased()
                    let glyph = HandwrittenFont.letters[key] ?? HandwrittenFont.letters["?"]!
                    let capital = character.isUppercase
                    let height: CGFloat = capital ? 24 : 20
                    let width: CGFloat = character == " " ? 8 : 12
                    let baseline = origin.y + CGFloat(sin(Double(column) * 1.9 + Double(line))) * 0.7
                    for segment in glyph.split(separator: "|") {
                        let coords = segment.split(separator: " ").compactMap { pair -> CGPoint? in
                            let numbers = pair.split(separator: ",").compactMap { Double($0) }
                            guard numbers.count == 2 else { return nil }
                            return CGPoint(x: numbers[0], y: numbers[1])
                        }
                        guard coords.count >= 2 else { continue }
                        // Sample each pen movement, preserving separate pen lifts.
                        var samples: [PKStrokePoint] = []
                        for (a, b) in zip(coords, coords.dropFirst()) {
                            let steps = max(2, Int(hypot(b.x - a.x, b.y - a.y) * 12))
                            for i in 0..<steps {
                                let t = CGFloat(i) / CGFloat(steps)
                                let px = a.x + (b.x - a.x) * t
                                let py = a.y + (b.y - a.y) * t
                                let jitter = sin(Double(serial + samples.count) * 0.61) * 0.12
                                let location = CGPoint(x: x + px * width + (1 - py) * 1.1 + jitter,
                                                       y: baseline + py * height - (capital ? 4 : 0))
                                samples.append(PKStrokePoint(location: location, timeOffset: Double(samples.count) * 0.012,
                                    size: CGSize(width: 4, height: 4), opacity: 1,
                                    force: 1, azimuth: 0, altitude: .pi / 2))
                            }
                        }
                        let last = coords.last!
                        samples.append(PKStrokePoint(location: CGPoint(x: x + last.x * width + (1 - last.y) * 1.1,
                            y: baseline + last.y * height - (capital ? 4 : 0)), timeOffset: Double(samples.count) * 0.012,
                            size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2))
                        strokes.append(PKStroke(ink: PKInk(.pen, color: .black),
                            path: PKStrokePath(controlPoints: samples, creationDate: Date(timeIntervalSince1970: Double(serial)))))
                        serial += 1
                    }
                    x += width + 3
                }
            }
        }
        return PKDrawing(strokes: strokes)
    }

}
