import CoreGraphics
import Foundation

@main enum WorkspaceGeometryChecks {
    static func main() {
        for size in [CGSize(width: 1366, height: 1024), CGSize(width: 1024, height: 1366), CGSize(width: 800, height: 720)] {
            let g = WorkspaceGeometry(size: size, division: nil, compact: false)
            precondition(g.canSplit && !g.vertical)
            precondition(g.first.width == g.second.width && g.first.maxX < g.second.minX)
            precondition(g.second.maxX == size.width && g.second.maxY == size.height)
        }
        for compact in [true, false] {
            let g = WorkspaceGeometry(size: CGSize(width: 390, height: 800), division: nil, compact: compact)
            precondition(!g.canSplit, "Narrow windows must retain one readable editor")
        }
        let bookFold = CGRect(x: 380, y: 0, width: 40, height: 720)
        let book = WorkspaceGeometry(size: CGSize(width: 800, height: 720), division: bookFold, compact: false)
        precondition(book.canSplit && !book.vertical)
        precondition(book.first.maxX == bookFold.minX + 10 && book.second.minX == bookFold.maxX - 10)
        precondition(book.divider.width == 20 && book.divider.midX == bookFold.midX)
        for width: CGFloat in [6, 12, 16, 24, 60] {
            let fold = CGRect(x: 400 - width / 2, y: 0, width: width, height: 720)
            let geometry = WorkspaceGeometry(size: book.size, division: fold, compact: false)
            let gap = geometry.second.minX - geometry.first.maxX
            precondition(gap >= min(12, width) && width - gap <= 20)
            precondition(geometry.first.width == geometry.second.width)
        }
        let tableFold = CGRect(x: 0, y: 380, width: 720, height: 40)
        let table = WorkspaceGeometry(size: CGSize(width: 720, height: 800), division: tableFold, compact: false)
        precondition(table.canSplit && table.vertical)
        precondition(table.first.maxY == tableFold.minY && table.second.minY == tableFold.maxY)
        precondition(table.first.height == table.second.height)
        print("Workspace geometry: equal panes, narrow collapse, book and tabletop fold exclusion passed")
    }
}
