import Foundation
import CoreGraphics

@main struct CirclePopupPlacementChecks {
    static func main() {
        let viewport = CGSize(width: 1032, height: 1376), card = CGSize(width: 390, height: 600)
        let leftBlob = CGRect(x: 80, y: 400, width: 300, height: 80)
        let right = CirclePopupPlacement.place(size: card, viewport: viewport, region: leftBlob, pinned: nil)
        precondition(right.minX >= leftBlob.maxX + 16 && right.minY == leftBlob.minY)
        let rightBlob = CGRect(x: 650, y: 400, width: 300, height: 80)
        let left = CirclePopupPlacement.place(size: card, viewport: viewport, region: rightBlob, pinned: nil)
        precondition(left.maxX <= rightBlob.minX - 16)
        let scrolled = CirclePopupPlacement.place(size: card, viewport: viewport,
            region: leftBlob.offsetBy(dx: 0, dy: -800), pinned: right.origin)
        precondition(scrolled == right, "Scrolling must not move the popup")
        let resized = CirclePopupPlacement.place(size: card, viewport: CGSize(width: 700, height: 850), region: rightBlob, pinned: right.origin)
        precondition(resized.minX >= 16 && resized.maxX <= 684 && resized.minY >= 100 && resized.maxY <= 754)
        let wideBlob = CGRect(x: 100, y: 900, width: 830, height: 80)
        let above = CirclePopupPlacement.place(size: card, viewport: viewport, region: wideBlob, pinned: nil)
        precondition(above.maxY <= wideBlob.minY - 16)
        print("Popup placement checks passed: adjacent placement, viewport pinning, resize clamping, and vertical fallback.")
    }
}
