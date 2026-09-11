import CoreGraphics
import Foundation

/// Pure document/viewport math shared by pinch feedback and page-fit snapping.
struct PageGeometry {
    static let pageWidth: CGFloat = 1_000
    static let pageOriginX: CGFloat = 1_000
    static let workspaceWidth: CGFloat = 3_000

    static func fitScale(for viewport: CGSize) -> CGFloat {
        max(viewport.width, 1) / pageWidth
    }

    static func shouldSnap(scale: CGFloat, fitScale: CGFloat) -> Bool {
        guard scale > 0, fitScale > 0 else { return false }
        return abs(scale / fitScale - 1) <= 0.28
    }

    /// Center the screen-sized guide on the current vertical reading position.
    static func pageRect(viewport: CGSize, scale: CGFloat, offset: CGPoint) -> CGRect {
        let height = viewport.height / fitScale(for: viewport)
        let centerY = (offset.y + viewport.height / 2) / max(scale, 0.001)
        return CGRect(x: pageOriginX, y: max(0, centerY - height / 2), width: pageWidth, height: height)
    }

    static func minimumScale(viewport: CGSize, document: CGSize) -> CGFloat {
        max(viewport.width / document.width, viewport.height / document.height)
    }

    static func isOverview(scale: CGFloat, fitScale: CGFloat) -> Bool {
        scale < fitScale * 0.995
    }

    static func documentPoint(_ point: CGPoint, scale: CGFloat, offset: CGPoint) -> CGPoint {
        CGPoint(x: (point.x + offset.x) / scale, y: (point.y + offset.y) / scale)
    }

    static func focusedRect(center: CGPoint, viewport: CGSize, document: CGSize) -> CGRect {
        let size = CGSize(width: pageWidth, height: viewport.height / fitScale(for: viewport))
        return CGRect(x: min(max(0, center.x - size.width / 2), max(0, document.width - size.width)),
                      y: min(max(0, center.y - size.height / 2), max(0, document.height - size.height)),
                      width: size.width, height: size.height)
    }

    static func screenRect(_ documentRect: CGRect, scale: CGFloat, offset: CGPoint) -> CGRect {
        CGRect(x: documentRect.minX * scale - offset.x,
               y: documentRect.minY * scale - offset.y,
               width: documentRect.width * scale, height: documentRect.height * scale)
    }
}
