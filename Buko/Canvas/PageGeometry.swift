import CoreGraphics
import Foundation

/// Pure document/viewport math shared by pinch feedback and page-fit snapping.
struct PageGeometry {
    static let pageWidth: CGFloat = 1_000
    static let pageOriginX: CGFloat = 1_000
    static let workspaceWidth: CGFloat = 3_000

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
