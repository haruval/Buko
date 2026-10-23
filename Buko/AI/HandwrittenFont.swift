import PencilKit
import CoreText

/// Buko's own hand-printed paths, shared with the development notes. No downloaded
/// font or third-party renderer. System font outlines cover additional characters.
nonisolated enum HandwrittenFont {
    static func sample(_ character: String) -> HandwritingSample? {
        guard character.count == 1 else { return nil }
        if let glyph = letters[character] {
            var strokes: [PKStroke] = []
            for segment in glyph.split(separator: "|") {
                let points = segment.split(separator: " ").compactMap { pair -> CGPoint? in
                    let n = pair.split(separator: ",").compactMap { Double($0) }
                    guard n.count == 2 else { return nil }
                    return CGPoint(x: 12 + n[0] * 43.2 + (1 - n[1]) * 3.6, y: 54 + n[1] * 72)
                }
                strokes += paths([points], width: 9)
            }
            return try? HandwritingSample(drawing: PKDrawing(strokes: strokes))
        }
        return systemSample(character)
    }

    private static func paths(_ contours: [[CGPoint]], width: CGFloat) -> [PKStroke] {
        contours.filter { $0.count >= 2 }.map { contour in
            var points: [CGPoint] = []
            for (a, b) in zip(contour, contour.dropFirst()) {
                let steps = max(1, Int(ceil(hypot(b.x - a.x, b.y - a.y) / 2)))
                for i in 0..<steps {
                    let t = CGFloat(i) / CGFloat(steps)
                    points.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                }
            }
            points.append(contour.last!)
            let path = PKStrokePath(controlPoints: points.enumerated().map { i, point in
                PKStrokePoint(location: point, timeOffset: Double(i) * 0.01,
                    size: CGSize(width: width, height: width), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }, creationDate: Date(timeIntervalSince1970: 0))
            return PKStroke(ink: PKInk(.pen, color: .black), path: path)
        }
    }

    private static func systemSample(_ text: String) -> HandwritingSample? {
        let base = CTFontCreateWithName("ChalkboardSE-Regular" as CFString, 100, nil)
        let font = CTFontCreateForString(base, text as CFString, CFRange(location: 0, length: (text as NSString).length))
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
        var contours: [[CGPoint]] = []
        let scale = 72 / max(1, CTFontGetCapHeight(base))
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let runFont = attributes[kCTFontAttributeName] else { return nil }
            let actualFont = runFont as! CTFont
            var glyphs = [CGGlyph](repeating: 0, count: CTRunGetGlyphCount(run))
            var positions = [CGPoint](repeating: .zero, count: glyphs.count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            for (glyph, position) in zip(glyphs, positions) {
                guard glyph != 0, let path = CTFontCreatePathForGlyph(actualFont, glyph, nil) else { return nil }
                var current: [CGPoint] = []
                var cursor = CGPoint.zero, start = CGPoint.zero
                func mapped(_ p: CGPoint) -> CGPoint {
                    CGPoint(x: 12 + (p.x + position.x) * scale, y: 126 - (p.y + position.y) * scale)
                }
                path.applyWithBlock { pointer in
                    let e = pointer.pointee
                    switch e.type {
                    case .moveToPoint:
                        if !current.isEmpty { contours.append(current) }
                        cursor = e.points[0]; start = cursor; current = [mapped(cursor)]
                    case .addLineToPoint: cursor = e.points[0]; current.append(mapped(cursor))
                    case .addQuadCurveToPoint:
                        let a = cursor, b = e.points[0], c = e.points[1]
                        for i in 1...16 {
                            let t = CGFloat(i) / 16, u = 1 - t
                            current.append(mapped(CGPoint(x: u*u*a.x + 2*u*t*b.x + t*t*c.x,
                                                         y: u*u*a.y + 2*u*t*b.y + t*t*c.y)))
                        }
                        cursor = c
                    case .addCurveToPoint:
                        let a = cursor, b = e.points[0], c = e.points[1], d = e.points[2]
                        for i in 1...24 {
                            let t = CGFloat(i) / 24, u = 1 - t
                            current.append(mapped(CGPoint(x: u*u*u*a.x + 3*u*u*t*b.x + 3*u*t*t*c.x + t*t*t*d.x,
                                                         y: u*u*u*a.y + 3*u*u*t*b.y + 3*u*t*t*c.y + t*t*t*d.y)))
                        }
                        cursor = d
                    case .closeSubpath:
                        current.append(mapped(start)); contours.append(current); current = []; cursor = start
                    @unknown default: break
                    }
                }
                if !current.isEmpty { contours.append(current) }
            }
        }
        return try? HandwritingSample(drawing: PKDrawing(strokes: paths(contours, width: 2.5)))
    }

    // Normalized hand-printed lowercase alphabet. Separate paths are pen lifts.
    static let letters: [String: String] = [
        "A": "0,1 0.48,0 1,1|0.2,0.64 0.8,0.64",
        "B": "0.08,1 0.08,0 0.6,0 0.9,0.18 0.85,0.36 0.6,0.48 0.08,0.48|0.6,0.48 0.95,0.66 0.9,0.87 0.6,1 0.08,1",
        "C": "0.96,0.18 0.7,0 0.3,0.04 0.06,0.3 0.04,0.7 0.3,0.96 0.7,1 0.96,0.82",
        "D": "0.08,1 0.08,0 0.5,0 0.86,0.2 0.98,0.52 0.84,0.82 0.5,1 0.08,1",
        "E": "0.95,0 0.08,0 0.08,1 0.95,1|0.08,0.48 0.78,0.48",
        "F": "0.08,1 0.08,0 0.95,0|0.08,0.48 0.78,0.48",
        "G": "0.95,0.18 0.7,0 0.3,0.04 0.06,0.3 0.04,0.7 0.3,0.96 0.7,1 0.95,0.8 0.95,0.55 0.58,0.55",
        "H": "0.08,0 0.08,1|0.92,0 0.92,1|0.08,0.5 0.92,0.5",
        "I": "0.12,0 0.9,0|0.5,0 0.5,1|0.12,1 0.9,1",
        "J": "0.15,0 0.9,0|0.75,0 0.75,0.76 0.55,1 0.25,0.98 0.05,0.78",
        "K": "0.08,0 0.08,1|0.92,0 0.08,0.55 0.92,1",
        "L": "0.08,0 0.08,1 0.95,1",
        "M": "0.05,1 0.05,0 0.5,0.6 0.95,0 0.95,1",
        "N": "0.08,1 0.08,0 0.92,1 0.92,0",
        "O": "0.5,0 0.18,0.1 0.02,0.5 0.18,0.9 0.5,1 0.82,0.9 0.98,0.5 0.82,0.1 0.5,0",
        "P": "0.08,1 0.08,0 0.6,0 0.92,0.18 0.9,0.4 0.6,0.55 0.08,0.55",
        "Q": "0.5,0 0.18,0.1 0.02,0.5 0.18,0.9 0.5,1 0.82,0.9 0.98,0.5 0.82,0.1 0.5,0|0.6,0.7 1,1.12",
        "R": "0.08,1 0.08,0 0.6,0 0.92,0.18 0.9,0.4 0.6,0.55 0.08,0.55|0.5,0.55 0.96,1",
        "S": "0.94,0.18 0.68,0 0.3,0.02 0.06,0.22 0.15,0.42 0.7,0.58 0.94,0.78 0.75,0.98 0.3,1 0.06,0.84",
        "T": "0.02,0 0.98,0|0.5,0 0.5,1",
        "U": "0.08,0 0.08,0.75 0.3,1 0.65,1 0.92,0.75 0.92,0",
        "V": "0.02,0 0.5,1 0.98,0",
        "W": "0.02,0 0.23,1 0.5,0.35 0.77,1 0.98,0",
        "X": "0.04,0 0.96,1|0.96,0 0.04,1",
        "Y": "0.02,0 0.5,0.5 0.98,0|0.5,0.5 0.5,1",
        "Z": "0.04,0 0.96,0 0.04,1 0.96,1",
        "'": "0.5,0 0.4,0.22", "!": "0.5,0 0.5,0.72|0.5,0.95 0.52,0.98",
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
