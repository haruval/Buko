import CoreGraphics
import Foundation

@main
struct PageGeometryChecks {
    static func main() {
        let portrait = CGSize(width: 1_032, height: 1_376)
        let fit = PageGeometry.fitScale(for: portrait)
        precondition(abs(fit - 1.032) < 0.0001)
        let initialOffset = CGPoint(x: 1_000 * fit, y: 0)
        let page = PageGeometry.pageRect(viewport: portrait, scale: fit, offset: initialOffset)
        let screen = PageGeometry.screenRect(page, scale: fit, offset: initialOffset)
        precondition(abs(screen.width - portrait.width) < 0.001)
        precondition(abs(screen.height - portrait.height) < 0.001)
        precondition(abs(screen.minX) < 0.001 && abs(screen.minY) < 0.001)
        precondition(PageGeometry.shouldSnap(scale: fit * 0.95, fitScale: fit))
        precondition(PageGeometry.shouldSnap(scale: fit * 1.05, fitScale: fit))
        precondition(!PageGeometry.shouldSnap(scale: fit * 0.8, fitScale: fit))
        precondition(!PageGeometry.shouldSnap(scale: fit * 1.2, fitScale: fit))
        precondition(!PageGeometry.shouldSnap(scale: 1, fitScale: 0))
        let scrolled = PageGeometry.pageRect(viewport: portrait, scale: fit, offset: CGPoint(x: initialOffset.x, y: 4_000))
        precondition(abs(scrolled.minY - 4_000 / fit) < 0.001)
        let landscape = CGSize(width: 1_376, height: 1_032)
        let landscapeFit = PageGeometry.fitScale(for: landscape)
        let landscapePage = PageGeometry.pageRect(viewport: landscape, scale: landscapeFit, offset: .zero)
        precondition(abs(landscapePage.height * landscapeFit - landscape.height) < 0.001)
        let zoomedOut = PageGeometry.screenRect(page, scale: fit / 2, offset: .zero)
        precondition(abs(zoomedOut.width - portrait.width / 2) < 0.001)
        print("Page geometry checks passed: fit, corner projection, scroll position, rotation, and snap thresholds.")
    }
}
