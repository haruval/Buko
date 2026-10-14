import Foundation
import CoreGraphics

/// Choose placement once, then project the page anchor with the source jelly.
nonisolated enum CirclePopupPlacement {
    /// Keep the card readable at a fixed size while its origin follows the page.
    /// Never clamp during scrolling: the popup must leave the viewport with its source.
    static func projected(anchor: CGPoint, size: CGSize, projection: CGAffineTransform) -> CGRect {
        CGRect(origin: anchor.applying(projection), size: size)
    }

    static func preferredWidth(viewport: CGSize, region: CGRect) -> CGFloat {
        let available = max(region.minX - 32, viewport.width - region.maxX - 32)
        let ideal = min(390, viewport.width - 32)
        return available >= 260 ? min(ideal, available) : ideal
    }

    static func place(size: CGSize, viewport: CGSize, region: CGRect) -> CGRect {
        let minX: CGFloat = 16, minY: CGFloat = 100, gap: CGFloat = 16
        let maxX = max(minX, viewport.width - size.width - 16)
        let maxY = max(minY, viewport.height - size.height - 96)
        func clamped(_ origin: CGPoint) -> CGRect {
            CGRect(x: min(maxX, max(minX, origin.x)), y: min(maxY, max(minY, origin.y)),
                   width: size.width, height: size.height)
        }
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
