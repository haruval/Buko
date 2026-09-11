import Foundation
import CoreGraphics

/// The popup is screen-pinned; the source jelly continues to use document space.
nonisolated enum CirclePopupPlacement {
    static func place(size: CGSize, viewport: CGSize, region: CGRect, pinned: CGPoint?) -> CGRect {
        let minX: CGFloat = 16, minY: CGFloat = 100, gap: CGFloat = 16
        let maxX = max(minX, viewport.width - size.width - 16)
        let maxY = max(minY, viewport.height - size.height - 96)
        func clamped(_ origin: CGPoint) -> CGRect {
            CGRect(x: min(maxX, max(minX, origin.x)), y: min(maxY, max(minY, origin.y)),
                   width: size.width, height: size.height)
        }
        if let pinned { return clamped(pinned) }
        // Prefer either side over placing a large card beneath the selection.
        if region.maxX + gap <= maxX {
            return clamped(CGPoint(x: region.maxX + gap, y: region.minY))
        }
        if region.minX - gap - size.width >= minX {
            return clamped(CGPoint(x: region.minX - gap - size.width, y: region.minY))
        }
        let below = viewport.height - 96 - region.maxY - gap
        let above = region.minY - gap - minY
        let y = below >= size.height || below >= above ? region.maxY + gap : region.minY - gap - size.height
        return clamped(CGPoint(x: region.midX - size.width / 2, y: y))
    }
}
