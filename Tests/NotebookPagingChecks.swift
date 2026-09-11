import CoreGraphics
import Foundation

@main
struct NotebookPagingChecks {
    static func main() {
        precondition(abs(NotebookPaging.pageHeight / PageGeometry.pageWidth - 1376 / 1032) < 0.0001)
        precondition(NotebookPaging.rect(for: 1).minY == NotebookPaging.rect(for: 0).maxY)
        precondition(NotebookPaging.inferredPageCount(drawingMaxY: 0, savedCount: 1) == 1)
        precondition(NotebookPaging.inferredPageCount(drawingMaxY: 0, savedCount: 4) == 4)
        precondition(NotebookPaging.inferredPageCount(drawingMaxY: NotebookPaging.pageHeight + 1, savedCount: 1) == 2)
        precondition(NotebookPaging.action(pull: 87, index: 0, count: 1) == .none)
        precondition(NotebookPaging.action(pull: 88, index: 0, count: 1) == .append)
        precondition(NotebookPaging.action(pull: 100, index: 0, count: 2) == .none)
        precondition(NotebookPaging.action(pull: -100, index: 1, count: 2) == .none)
        precondition(NotebookPaging.action(pull: -100, index: 0, count: 2) == .none)
        precondition(NotebookPaging.signedPull(offset: -70, minimum: -20, maximum: 80) == -50)
        precondition(NotebookPaging.signedPull(offset: 150, minimum: -20, maximum: 80) == 70)
        precondition(NotebookPaging.signedPull(offset: 0, minimum: -20, maximum: 80) == 0)
        // Pointer rubber-banding may stop at ~24 pt even after a long gesture.
        let longPull = NotebookPaging.gesturePull(startOffset: 0, translation: -300, minimum: 0, maximum: 0, viewportHeight: 1376)
        precondition(NotebookPaging.action(pull: longPull, index: 0, count: 1) == .append)
        precondition(NotebookPaging.gesturePull(startOffset: 0, translation: -300, minimum: 0, maximum: 800, viewportHeight: 1032) == 0)
        let reversedPull = NotebookPaging.gesturePull(startOffset: 0, translation: -40, minimum: 0, maximum: 0, viewportHeight: 1376)
        precondition(NotebookPaging.action(pull: reversedPull, index: 0, count: 1) == .none)
        // Crossing an internal page boundary is ordinary scrolling, not an append.
        precondition(NotebookPaging.gesturePull(startOffset: 0, translation: -1500,
            minimum: 0, maximum: 2800, viewportHeight: 1376) == 0)
        precondition(NotebookPaging.action(pull: 100, index: 2, count: 3) == .append)
        precondition(NotebookPaging.action(pull: -300, index: 2, count: 3) == .none)
        let viewport = CGSize(width: 1_376, height: 1_032)
        let portrait = CGSize(width: 1032, height: 1376)
        precondition(abs(NotebookPaging.pageHeight * NotebookPaging.fitScale(viewport: portrait) - portrait.height) < 0.001)
        precondition(NotebookPaging.pageHeight * NotebookPaging.fitScale(viewport: viewport) > viewport.height)
        let page = NotebookPaging.rect(for: 2)
        let focus = NotebookPaging.focusedRect(center: CGPoint(x: page.midX, y: page.minY), viewport: viewport, index: 2)
        precondition(focus.minY == page.minY && focus.maxY <= page.maxY)
        let bottomFocus = NotebookPaging.focusedRect(center: CGPoint(x: page.midX, y: page.maxY), viewport: viewport, index: 2)
        precondition(bottomFocus.maxY == page.maxY)
        print("Notebook paging checks passed: portrait iPad size, pull threshold/cancellation, last-page-only append, legacy bounds, blank pages, and focus clamping.")
    }
}
