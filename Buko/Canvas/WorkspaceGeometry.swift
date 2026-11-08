import CoreGraphics
import Foundation

/// The system describes the fold in this view's coordinates. No device model,
/// screen dimensions, or hinge angle is used to make layout decisions.
struct WorkspaceGeometry {
    let size: CGSize
    let division: CGRect?
    let compact: Bool
    var vertical: Bool { division.map { $0.width > $0.height } ?? false }
    var canSplit: Bool { !compact && (vertical ? size.height >= 560 : size.width >= 620) }
    // Let book paper extend toward the crease while retaining a visible gutter.
    // Use the original system division for pose detection and native arrangement.
    var bookPageExtension: CGFloat {
        guard canSplit, !vertical, let division else { return 0 }
        return min(10, max(0, (division.width - 12) / 2))
    }
    var first: CGRect {
        if vertical {
            return CGRect(x: 0, y: 0, width: size.width, height: division?.minY ?? (size.height - 10) / 2)
        }
        return CGRect(x: 0, y: 0, width: division.map { $0.minX + bookPageExtension } ?? (size.width - 10) / 2, height: size.height)
    }
    var second: CGRect {
        if vertical {
            let top = division?.maxY ?? (size.height + 10) / 2
            return CGRect(x: 0, y: top, width: size.width, height: max(0, size.height - top))
        }
        let left = division.map { $0.maxX - bookPageExtension } ?? (size.width + 10) / 2
        return CGRect(x: left, y: 0, width: max(0, size.width - left), height: size.height)
    }
    var divider: CGRect {
        if vertical { return CGRect(x: 0, y: first.maxY, width: size.width, height: max(10, second.minY - first.maxY)) }
        return CGRect(x: first.maxX, y: 0, width: max(10, second.minX - first.maxX), height: size.height)
    }
}
