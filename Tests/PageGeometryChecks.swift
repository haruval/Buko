import CoreGraphics
import Foundation

@main
struct PageGeometryChecks {
    static func main() {
        let portrait = CGSize(width: 1_032, height: 1_376)
        let fit = NotebookPaging.fitScale(viewport: portrait)
        precondition(abs(fit - 1.032) < 0.0001)
        let initialOffset = CGPoint(x: 1_000 * fit, y: 0)
        let page = NotebookPaging.rect(for: 0)
        let screen = PageGeometry.screenRect(page, scale: fit, offset: initialOffset)
        precondition(abs(screen.width - portrait.width) < 0.001)
        precondition(abs(screen.height - portrait.height) < 0.001)
        precondition(abs(screen.minX) < 0.001 && abs(screen.minY) < 0.001)
        precondition(PageGeometry.shouldSnap(scale: fit * 0.95, fitScale: fit))
        precondition(PageGeometry.shouldSnap(scale: fit * 1.05, fitScale: fit))
        precondition(!PageGeometry.shouldSnap(scale: fit * 0.7, fitScale: fit))
        precondition(!PageGeometry.shouldSnap(scale: fit * 1.3, fitScale: fit))
        precondition(!PageGeometry.shouldSnap(scale: 1, fitScale: 0))
        precondition(PageGeometry.shouldSnap(scale: fit * 0.75, fitScale: fit))
        precondition(PageGeometry.shouldSnap(scale: fit * 1.25, fitScale: fit))
        precondition(PageGeometry.isOverview(scale: fit * 0.7, fitScale: fit))
        precondition(!PageGeometry.isOverview(scale: fit, fitScale: fit))
        let tapped = PageGeometry.documentPoint(CGPoint(x: 100, y: 200), scale: 0.5, offset: CGPoint(x: 500, y: 600))
        precondition(tapped == CGPoint(x: 1_200, y: 1_600))
        let scrolled = PageGeometry.screenRect(NotebookPaging.rect(for: 2), scale: fit,
            offset: CGPoint(x: initialOffset.x, y: NotebookPaging.pageStride * 2 * fit))
        precondition(abs(scrolled.minY) < 0.001)
        let zoomedOut = PageGeometry.screenRect(page, scale: fit / 2, offset: .zero)
        precondition(abs(zoomedOut.width - portrait.width / 2) < 0.001)
        print("Page geometry checks passed: fit, corner projection, scroll position, rotation, and snap thresholds.")
    }
}
