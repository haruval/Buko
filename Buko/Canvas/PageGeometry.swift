import CoreGraphics
import Foundation

/// Pure document/viewport math shared by pinch feedback and page-fit snapping.
struct PageGeometry {
    static let pageWidth: CGFloat = 1_000
    static let pageOriginX: CGFloat = 1_000
    static let workspaceWidth: CGFloat = 3_000

    /// A short pinch travel progressively prepares the bezel before committing.
    static func zoomPreparation(relativeScale: CGFloat) -> CGFloat {
        min(1, max(0, (1 - relativeScale) / 0.12))
    }

    static func overviewScale(fitScale: CGFloat, viewport: CGSize, pageHeight: CGFloat) -> CGFloat {
        fitScale * max(0.3, min(0.64, viewport.height / (pageHeight * fitScale) * 0.84))
    }

    static func shouldSnap(scale: CGFloat, fitScale: CGFloat) -> Bool {
        guard scale > 0, fitScale > 0 else { return false }
        return abs(scale / fitScale - 1) <= 0.28
    }

    static func isOverview(scale: CGFloat, fitScale: CGFloat) -> Bool {
        scale < fitScale * 0.995
    }

    static func documentPoint(_ point: CGPoint, scale: CGFloat, offset: CGPoint) -> CGPoint {
        CGPoint(x: (point.x + offset.x) / scale, y: (point.y + offset.y) / scale)
    }

    static func screenRect(_ documentRect: CGRect, scale: CGFloat, offset: CGPoint) -> CGRect {
        CGRect(x: documentRect.minX * scale - offset.x,
               y: documentRect.minY * scale - offset.y,
               width: documentRect.width * scale, height: documentRect.height * scale)
    }
}
