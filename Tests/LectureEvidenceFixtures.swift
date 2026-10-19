import Foundation
import CoreGraphics
import CoreText

/// Generated PDFs exercise the real extraction/chunking path in isolated stores.
enum LectureEvidenceFixtures {
    static let seven = "The fictional Luma sample has exactly seven chambers."
    static let nine = "The fictional Luma sample has exactly nine chambers."

    static func conflictText() -> String {
        let filler = "The teaching handout describes a fictional specimen used for classroom discussion. Laboratory observations are recorded during a single exercise. Its exterior has a smooth surface with a thin protective covering. Students should compare descriptions carefully because the material is invented for practice."
        return [seven, nine].map { fact in
            Array((fact + " " + String(repeating: filler + " ", count: 5)).split(whereSeparator: \.isWhitespace).prefix(140))
                .joined(separator: " ")
        }.joined(separator: "\n\n")
    }

    static func conflictPDF(at url: URL) {
        pdf(at: url) { context in
            let attributes: [NSAttributedString.Key: Any] = [.font: CTFontCreateWithName("Helvetica" as CFString, 12, nil),
                                                            .foregroundColor: CGColor(gray: 0, alpha: 1)]
            let setter = CTFramesetterCreateWithAttributedString(NSAttributedString(string: conflictText(), attributes: attributes))
            CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0),
                CGPath(rect: CGRect(x: 36, y: 36, width: 540, height: 720), transform: nil), nil), context)
        }
    }

    static func layeredPDF(at url: URL, native: String = seven, visible: String = nine) {
        pdf(at: url) { context in
            context.saveGState()
            context.setTextDrawingMode(.invisible)
            draw(native, in: context, at: CGPoint(x: 36, y: 691.25), size: 16.2)
            context.restoreGState()
            let bitmap = CGContext(data: nil, width: 1200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            bitmap.setFillColor(CGColor(gray: 1, alpha: 1)); bitmap.fill(CGRect(x: 0, y: 0, width: 1200, height: 100))
            draw(visible, in: bitmap, at: CGPoint(x: 0, y: 25), size: 36)
            context.draw(bitmap.makeImage()!, in: CGRect(x: 36, y: 680, width: 540, height: 45))
        }
    }

    private static func pdf(at url: URL, content: (CGContext) -> Void) {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = CGContext(url as CFURL, mediaBox: &box, nil)!
        context.beginPDFPage(nil); content(context); context.endPDFPage(); context.closePDF()
    }

    private static func draw(_ text: String, in context: CGContext, at point: CGPoint, size: CGFloat) {
        context.textPosition = point
        let attributes: [NSAttributedString.Key: Any] = [.font: CTFontCreateWithName("Helvetica" as CFString, size, nil),
                                                        .foregroundColor: CGColor(gray: 0, alpha: 1)]
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)), context)
    }
}
