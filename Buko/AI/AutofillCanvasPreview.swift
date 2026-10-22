import PencilKit
import UIKit

/// Separate, read-only presentation. Preview ink never enters the editor's drawing,
/// undo stack, save callbacks or recognition snapshot.
final class AutofillCanvasPreview: UIView {
    private let canvas = PKCanvasView()
    private let backdrop = CanvasBackdrop()
    private var labels: [UILabel] = []
    private var result: AutofillLayout.Result?
    private var style = UIUserInterfaceStyle.light

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        canvas.isUserInteractionEnabled = false; canvas.backgroundColor = .clear; canvas.isOpaque = false
        canvas.overrideUserInterfaceStyle = .light
        canvas.minimumZoomScale = 0.01; canvas.maximumZoomScale = 8
        canvas.contentInsetAdjustmentBehavior = .never
        addSubview(backdrop)
        addSubview(canvas)
        isHidden = true
        accessibilityElementsHidden = true
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func show(_ result: AutofillLayout.Result?, style: UIUserInterfaceStyle) {
        self.result = result; self.style = style
        backdrop.overrideUserInterfaceStyle = style
        labels.forEach { $0.removeFromSuperview() }; labels = []
        isHidden = result == nil
        guard let result else { canvas.drawing = PKDrawing(); return }
        let green = Self.green(style)
        // Refresh render IDs because PencilKit can cache off-screen color tiles.
        var presentation = InkPresentation()
        let existing = presentation.refresh(result.existing, to: style == .dark ? .white : .black)
        let inserted = presentation.refresh(result.inserted, to: green)
        canvas.drawing = PKDrawing(strokes: existing.strokes + inserted.strokes)
        if !result.missing.isEmpty {
            for line in result.lines {
                let label = UILabel()
                label.text = line.text; label.textColor = green
                label.numberOfLines = 1; label.adjustsFontSizeToFitWidth = true; label.minimumScaleFactor = 0.5
                addSubview(label); labels.append(label)
            }
        }
    }

    static func green(_ style: UIUserInterfaceStyle) -> UIColor {
        // Muted but readable on both paper appearances; not opacity applied to the
        // whole canvas, which would also fade the user's existing handwriting.
        style == .dark ? UIColor(red: 0.49, green: 0.85, blue: 0.59, alpha: 0.85)
            : UIColor(red: 0.12, green: 0.42, blue: 0.23, alpha: 0.80)
    }

    func project(from editor: PKCanvasView, style: UIUserInterfaceStyle, showsGrid: Bool) {
        guard let result else { return }
        if self.style != style { show(result, style: style) }
        backdrop.frame = bounds
        backdrop.showsGrid = showsGrid
        backdrop.update(scale: editor.zoomScale, offset: editor.contentOffset,
                        document: CGSize(width: PageGeometry.workspaceWidth,
                                         height: NotebookPaging.documentHeight(count: result.pageCount)))
        canvas.frame = bounds
        canvas.zoomScale = editor.zoomScale
        canvas.contentSize = editor.contentSize
        canvas.contentInset = editor.contentInset
        canvas.contentOffset = editor.contentOffset
        for (line, label) in zip(result.lines, labels) {
            label.frame = PageGeometry.screenRect(line.frame, scale: editor.zoomScale, offset: editor.contentOffset)
            label.font = .systemFont(ofSize: result.letterHeight * editor.zoomScale)
        }
    }
}
