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
                    let glyph = letters[key] ?? letters["?"]!
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

    // Normalized hand-printed lowercase alphabet. Separate paths are pen lifts.
    private static let letters: [String: String] = [
        " ": "", "a": "0.85,0.35 0.55,0.28 0.15,0.4 0.02,0.7 0.1,0.93 0.4,1 0.8,0.78|0.85,0.3 0.8,1 1,0.95",
        "b": "0.08,0 0.08,1|0.1,0.5 0.4,0.3 0.7,0.3 0.95,0.5 0.95,0.75 0.7,0.98 0.4,1 0.1,0.8",
        "c": "0.95,0.4 0.7,0.3 0.35,0.3 0.08,0.5 0.02,0.75 0.2,0.95 0.55,1 0.9,0.86",
        "d": "0.85,0.4 0.6,0.3 0.25,0.35 0.05,0.55 0.05,0.8 0.3,1 0.6,0.95 0.85,0.75|0.9,0 0.85,1 1,0.95",
        "e": "0.05,0.65 0.9,0.6 0.85,0.38 0.5,0.3 0.15,0.4 0.02,0.68 0.15,0.9 0.5,1 0.9,0.88",
        "f": "0.85,0.08 0.55,0 0.35,0.2 0.3,1.1|0,0.4 0.75,0.4",
        "g": "0.9,0.4 0.65,0.3 0.3,0.33 0.05,0.55 0.08,0.8 0.3,0.95 0.6,0.92 0.85,0.72|0.9,0.3 0.85,1.2 0.65,1.4 0.3,1.4 0.05,1.25",
        "h": "0.1,0 0.1,1|0.1,0.6 0.4,0.32 0.65,0.3 0.88,0.47 0.88,1",
        "i": "0.4,0.35 0.4,0.95 0.65,1|0.4,0.06 0.42,0.09",
        "j": "0.65,0.35 0.65,1.17 0.4,1.4 0.1,1.3|0.65,0.06 0.67,0.09",
        "k": "0.1,0 0.1,1|0.9,0.3 0.15,0.7 0.5,0.65 0.95,1",
        "l": "0.3,0 0.3,0.9 0.5,1 0.75,0.95",
        "m": "0.05,1 0.05,0.3 0.05,0.6 0.25,0.33 0.42,0.35 0.48,0.55 0.48,1|0.48,0.55 0.7,0.32 0.9,0.4 0.95,1",
        "n": "0.08,1 0.08,0.3 0.08,0.6 0.4,0.33 0.7,0.33 0.9,0.52 0.9,1",
        "o": "0.5,0.3 0.2,0.36 0.05,0.57 0.08,0.82 0.35,1 0.68,0.96 0.92,0.75 0.9,0.5 0.65,0.32 0.5,0.3",
        "p": "0.1,0.3 0.1,1.4|0.1,0.5 0.4,0.32 0.75,0.35 0.95,0.55 0.9,0.8 0.6,0.95 0.3,0.9 0.1,0.75",
        "q": "0.9,0.4 0.6,0.3 0.25,0.35 0.05,0.6 0.15,0.9 0.4,1 0.85,0.75|0.9,0.3 0.85,1.4",
        "r": "0.1,1 0.1,0.32 0.1,0.6 0.4,0.35 0.75,0.35 0.9,0.45",
        "s": "0.9,0.4 0.6,0.3 0.25,0.35 0.1,0.5 0.35,0.65 0.75,0.73 0.9,0.85 0.7,1 0.3,1 0.05,0.9",
        "t": "0.4,0.05 0.35,0.85 0.5,1 0.8,0.95|0.05,0.35 0.85,0.35",
        "u": "0.1,0.3 0.08,0.8 0.25,1 0.55,0.95 0.85,0.7|0.88,0.3 0.85,1 1,0.95",
        "v": "0.05,0.3 0.45,1 0.95,0.3",
        "w": "0.02,0.3 0.25,1 0.5,0.5 0.72,1 1,0.3",
        "x": "0.05,0.3 0.95,1|0.9,0.3 0.05,1",
        "y": "0.05,0.3 0.45,0.95|0.95,0.3 0.4,1.3 0.15,1.4",
        "z": "0.05,0.35 0.9,0.35 0.1,1 0.95,1",
        "[": "0.8,0 0.2,0 0.2,1.1 0.8,1.1",
        "]": "0.2,0 0.8,0 0.8,1.1 0.2,1.1",
        "/": "0.9,0 0.1,1",
        "6": "0.85,0.05 0.4,0 0.1,0.4 0.1,0.8 0.35,1 0.7,0.95 0.9,0.7 0.75,0.5 0.4,0.48 0.1,0.7",
        "7": "0.05,0.05 0.95,0.05 0.4,1",
        "8": "0.5,0 0.15,0.12 0.15,0.35 0.5,0.5 0.9,0.75 0.8,0.95 0.4,1 0.05,0.8 0.1,0.6 0.5,0.5 0.85,0.3 0.8,0.1 0.5,0",
        "9": "0.85,0.5 0.55,0.6 0.15,0.45 0.08,0.2 0.35,0 0.7,0.05 0.9,0.3 0.8,0.8 0.5,1 0.1,0.95",
        "0": "0.5,0 0.15,0.1 0.05,0.5 0.2,0.9 0.5,1 0.85,0.85 0.95,0.4 0.75,0.05 0.5,0",
        "1": "0.2,0.25 0.55,0 0.55,1|0.2,1 0.9,1",
        "2": "0.05,0.2 0.35,0 0.7,0.03 0.95,0.25 0.8,0.5 0.1,1 0.95,1",
        "3": "0.1,0.1 0.5,0 0.85,0.15 0.8,0.35 0.5,0.5 0.8,0.55 0.95,0.8 0.7,1 0.25,1 0.05,0.85",
        "4": "0.65,0 0.05,0.65 0.95,0.65|0.75,0 0.75,1",
        "5": "0.9,0 0.15,0 0.1,0.5 0.5,0.4 0.9,0.6 0.9,0.85 0.6,1 0.15,0.9",
        ":": "0.4,0.45 0.42,0.48|0.4,0.9 0.42,0.93", ".": "0.4,0.95 0.44,0.98",
        ",": "0.5,0.95 0.35,1.18", ";": "0.4,0.45 0.42,0.48|0.5,0.95 0.35,1.18",
        "-": "0.05,0.6 0.95,0.6", "=": "0.05,0.4 0.95,0.4|0.05,0.75 0.95,0.75",
        "+": "0.05,0.6 0.95,0.6|0.5,0.2 0.5,1", ">": "0.1,0.2 0.9,0.6 0.1,1",
        "(": "0.75,0 0.35,0.2 0.2,0.55 0.35,0.9 0.75,1.15",
        ")": "0.2,0 0.6,0.2 0.75,0.55 0.6,0.9 0.2,1.15",
        "?": "0.1,0.2 0.4,0 0.75,0.1 0.9,0.35 0.5,0.55 0.5,0.72|0.5,0.95 0.53,0.98",
        "|": "0.5,0 0.5,1", "*": "0.5,0.1 0.5,0.8|0.1,0.25 0.9,0.65|0.1,0.65 0.9,0.25"
    ]
}
