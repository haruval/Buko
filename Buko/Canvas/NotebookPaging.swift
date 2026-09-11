import CoreGraphics
import Foundation

/// Portrait 13-inch iPad Pro proportions (1032 × 1376 points) in stable document coordinates. Existing ink is never
/// translated or rescaled when switching between pages and the experimental canvas.
enum NotebookPaging {
    static let pageHeight: CGFloat = 1_000 * 1376 / 1032
    // Public UIKit exposes no physical display corner radius. This reference
    // radius is tuned for the 13-inch display and scales with the paper.
    static let cornerRadius: CGFloat = 24 * 1_000 / 1032
    static let pageGap: CGFloat = 24
    static let pageStride = pageHeight + pageGap

    static func documentHeight(count: Int) -> CGFloat {
        max(0, CGFloat(count) * pageStride - (count > 0 ? pageGap : 0))
    }

    static let pullThreshold: CGFloat = 88

    enum Action: Equatable { case none, previous, next, append }

    static func rect(for index: Int) -> CGRect {
        CGRect(x: PageGeometry.pageOriginX, y: CGFloat(max(0, index)) * pageStride,
               width: PageGeometry.pageWidth, height: pageHeight)
    }

    static func fitScale(viewport: CGSize) -> CGFloat {
        max(1, viewport.width) / PageGeometry.pageWidth
    }

    static func focusedRect(center: CGPoint, viewport: CGSize, index: Int) -> CGRect {
        let page = rect(for: index)
        let visibleHeight = min(page.height, viewport.height / fitScale(viewport: viewport))
        let top = min(max(page.minY, center.y - visibleHeight / 2), page.maxY - visibleHeight)
        return CGRect(x: page.minX, y: top, width: page.width, height: visibleHeight)
    }

    static func inferredPageCount(drawingMaxY: CGFloat, savedCount: Int) -> Int {
        max(1, savedCount, Int(ceil((max(0, drawingMaxY) + pageGap) / pageStride)))
    }

    static func signedPull(offset: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        if offset < minimum { return offset - minimum }
        if offset > maximum { return offset - maximum }
        return 0
    }

    /// Use the gesture's travel beyond the edge, not the scroll view's elastic
    /// offset: PencilKit/pointer scrolling can cap that offset below our detent.
    static func gesturePull(startOffset: CGFloat, translation: CGFloat, minimum: CGFloat,
                            maximum: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        let travel = signedPull(offset: startOffset - translation, minimum: minimum, maximum: maximum)
        let distance = max(1, viewportHeight)
        return travel * 0.55 / (1 + abs(travel) * 0.55 / distance)
    }

    static func action(pull: CGFloat, index: Int, count: Int) -> Action {
        // Pull is measured beyond the entire notebook, never an individual sheet.
        pull >= pullThreshold && index == count - 1 ? .append : .none
    }
}
