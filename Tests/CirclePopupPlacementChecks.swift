import Foundation
import CoreGraphics

@main struct CirclePopupPlacementChecks {
    static func main() {
        let viewport = CGSize(width: 1032, height: 1376), card = CGSize(width: 390, height: 600)
        let leftBlob = CGRect(x: 80, y: 400, width: 300, height: 80)
        let right = CirclePopupPlacement.place(size: card, viewport: viewport, region: leftBlob)
        precondition(right.minX >= leftBlob.maxX + 16 && right.minY == leftBlob.minY)
        let rightBlob = CGRect(x: 650, y: 400, width: 300, height: 80)
        let left = CirclePopupPlacement.place(size: card, viewport: viewport, region: rightBlob)
        precondition(left.maxX <= rightBlob.minX - 16)
        let scrolled = CirclePopupPlacement.projected(anchor: right.origin, size: card,
            projection: CGAffineTransform(translationX: -30, y: -800))
        precondition(scrolled.minX == right.minX - 30 && scrolled.minY == right.minY - 800,
                     "Popup must move with the page, even offscreen")
        let zoom = CGAffineTransform(a: 0.5, b: 0, c: 0, d: 0.5, tx: 20, ty: -60)
        let zoomed = CirclePopupPlacement.projected(anchor: right.origin, size: card, projection: zoom)
        precondition(zoomed.origin == right.origin.applying(zoom) && zoomed.size == card)
        let resized = CirclePopupPlacement.projected(anchor: right.origin, size: CGSize(width: 320, height: 500), projection: zoom)
        precondition(resized.origin == zoomed.origin, "Resizing must preserve the page anchor")
        let middleBlob = CGRect(x: 340, y: 420, width: 370, height: 90)
        let narrowWidth = CirclePopupPlacement.preferredWidth(viewport: viewport, region: middleBlob)
        precondition(narrowWidth >= 260 && narrowWidth < 390)
        let adjacent = CirclePopupPlacement.place(size: CGSize(width: narrowWidth, height: 600), viewport: viewport, region: middleBlob)
        precondition(adjacent.maxX <= middleBlob.minX - 16 || adjacent.minX >= middleBlob.maxX + 16)
        let wideBlob = CGRect(x: 100, y: 900, width: 830, height: 80)
        let above = CirclePopupPlacement.place(size: card, viewport: viewport, region: wideBlob)
        precondition(above.maxY <= wideBlob.minY - 16)
        print("Popup placement checks passed: adjacent placement, page anchoring through scrolling/zooming, stable resize origin, and vertical fallback.")
    }
}
