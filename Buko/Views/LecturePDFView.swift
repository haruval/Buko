import SwiftUI
import PDFKit

struct LecturePDFView: View {
    let destination: LecturePDFDestination
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            Button {
                dismiss()
            } label: {
                Label("Close PDF preview", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color(uiColor: .label))
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("closeLecturePDF")
            LecturePDFCard(destination: destination)
        }
        .padding([.horizontal, .bottom], 16)
        .background(Color("CanvasBackground"))
    }
}

struct LecturePDFCard: View {
    let destination: LecturePDFDestination
    var isVisible = true
    @State private var currentPage = 1
    @State private var pageCount = 0
    @State private var loadError = false
    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(destination.title.isEmpty ? "PDF" : destination.title, systemImage: "doc.text")
                        .font(.headline).lineLimit(2)
                    Spacer()
                    if pageCount > 0 { Text("\(currentPage) / \(pageCount)").font(.caption).monospacedDigit().foregroundStyle(.secondary) }
                }.padding(.horizontal, 8).accessibilityIdentifier("lecturePDFTitle")
                PDFPageView(destination: destination, isVisible: isVisible, currentPage: $currentPage, pageCount: $pageCount, loadError: $loadError)
                    .clipShape(.rect(cornerRadius: 20))
                    .accessibilityIdentifier("lecturePDFContent")
                    .overlay {
                        if loadError { ContentUnavailableView("Couldn’t open this PDF", systemImage: "doc.questionmark", description: Text("Try attaching the source again.")) }
                    }
            }
            .padding(14).bukoGlass(cornerRadius: 32)
        }
        .id(destination.id)
    }
}

private struct PDFPageView: UIViewRepresentable {
    let destination: LecturePDFDestination
    let isVisible: Bool
    @Binding var currentPage: Int
    @Binding var pageCount: Int
    @Binding var loadError: Bool

    func makeUIView(context: Context) -> SourcePDFView {
        let view = SourcePDFView()
        view.isHidden = !isVisible
        view.accessibilityElementsHidden = !isVisible
        view.backgroundColor = .secondarySystemBackground
        view.autoScales = true; view.displayMode = .singlePageContinuous; view.displayDirection = .vertical
        view.document = PDFDocument(url: destination.url)
        let coordinator = context.coordinator
        coordinator.view = view
        NotificationCenter.default.addObserver(coordinator, selector: #selector(Coordinator.pageChanged), name: .PDFViewPageChanged, object: view)
        view.firstLayout = { [weak view] in
            guard let view, let document = view.document, document.pageCount > 0 else {
                DispatchQueue.main.async { loadError = true }; return
            }
            let index = min(max(0, destination.page - 1), document.pageCount - 1)
            if let page = document.page(at: index) {
                let bounds = page.bounds(for: .cropBox)
                view.layoutDocumentView()
                view.go(to: PDFDestination(page: page, at: CGPoint(x: bounds.minX, y: bounds.maxY)))
            }
            if !destination.quote.isEmpty {
                let selections = document.findString(destination.quote, withOptions: .caseInsensitive)
                    .filter { $0.pages.contains { document.index(for: $0) == index } }
                for selection in selections { selection.color = .systemYellow.withAlphaComponent(0.35) }
                view.highlightedSelections = selections
            }
            coordinator.pageChanged()
        }
        return view
    }
    func updateUIView(_ view: SourcePDFView, context: Context) {
        view.isHidden = !isVisible
        view.accessibilityElementsHidden = !isVisible
    }
    func makeCoordinator() -> Coordinator { Coordinator(currentPage: $currentPage, pageCount: $pageCount) }
    static func dismantleUIView(_ view: SourcePDFView, coordinator: Coordinator) { NotificationCenter.default.removeObserver(coordinator) }

    final class Coordinator: NSObject {
        weak var view: PDFView?
        let currentPage: Binding<Int>
        let pageCount: Binding<Int>
        init(currentPage: Binding<Int>, pageCount: Binding<Int>) { self.currentPage = currentPage; self.pageCount = pageCount }
        @objc func pageChanged() {
            guard let view, let document = view.document, let page = view.currentPage else { return }
            let index = document.index(for: page), count = document.pageCount
            DispatchQueue.main.async { [weak self] in
                self?.currentPage.wrappedValue = index + 1; self?.pageCount.wrappedValue = count
            }
        }
    }
}

private final class SourcePDFView: PDFView {
    var firstLayout: (() -> Void)?
    private var fittedSize = CGSize.zero
    private var fitScale: CGFloat = 0
    private var updatingFit = false
    private weak var observedPinch: UIPinchGestureRecognizer?
    private weak var documentScroll: UIScrollView?
    private var pinchStartScale: CGFloat = 1
    private var pinchStartGestureScale: CGFloat = 1
    private var pinchAnchor: CGPoint?

    // Keep PDFKit's own recognizer, pan coordination and text interaction. On
    // iPadOS 27 it can report a growing pinch without updating its zoom scale;
    // apply that recognizer's ratio through PDFView's public scaling API.
    private func observeDocumentPinch() {
        var ancestor = documentView?.superview
        while let view = ancestor, view !== self {
            if let scroll = view as? UIScrollView, let pinch = scroll.pinchGestureRecognizer {
                guard pinch !== observedPinch else { return }
                observedPinch?.removeTarget(self, action: #selector(documentPinched(_:)))
                documentScroll = scroll; observedPinch = pinch
                pinch.addTarget(self, action: #selector(documentPinched(_:)))
                return
            }
            ancestor = view.superview
        }
    }

    @objc private func documentPinched(_ recognizer: UIPinchGestureRecognizer) {
        guard let content = documentView, let scroll = documentScroll else { return }
        switch recognizer.state {
        case .began:
            pinchStartScale = scaleFactor
            pinchStartGestureScale = max(0.001, recognizer.scale)
            pinchAnchor = content.convert(recognizer.location(in: self), from: self)
        case .changed:
            guard let anchor = pinchAnchor else { return }
            let requested = pinchStartScale * recognizer.scale / pinchStartGestureScale
            guard requested.isFinite else { return }
            let target = min(maxScaleFactor, max(minScaleFactor, requested))
            if abs(scaleFactor - target) > 0.0001 { scaleFactor = target }
            // Keep the same spot in the PDF underneath the moving fingers.
            let actual = content.convert(anchor, to: scroll)
            let desired = recognizer.location(in: scroll)
            let inset = scroll.adjustedContentInset
            let maximum = CGPoint(x: max(-inset.left, scroll.contentSize.width - scroll.bounds.width + inset.right),
                                  y: max(-inset.top, scroll.contentSize.height - scroll.bounds.height + inset.bottom))
            scroll.contentOffset = CGPoint(
                x: min(maximum.x, max(-inset.left, scroll.contentOffset.x + actual.x - desired.x)),
                y: min(maximum.y, max(-inset.top, scroll.contentOffset.y + actual.y - desired.y)))
        case .ended, .cancelled, .failed:
            pinchAnchor = nil
        default: break
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        observeDocumentPinch()
        if !updatingFit, document != nil, bounds.width > 0, bounds.height > 0, bounds.size != fittedSize {
            updatingFit = true
            let relativeZoom = fitScale > 0 ? max(1, scaleFactor / fitScale) : 1
            let fit = scaleFactorForSizeToFit
            if fit.isFinite, fit > 0 {
                fittedSize = bounds.size; fitScale = fit
                // This is the same default fit-width scale PDFKit uses for a
                // continuous document. It is also the zoom-out floor.
                maxScaleFactor = fit * 6
                minScaleFactor = fit
                scaleFactor = min(maxScaleFactor, fit * relativeZoom)
            }
            updatingFit = false
        }
        guard window != nil, bounds.width > 0, bounds.height > 0, let action = firstLayout else { return }
        firstLayout = nil
        // Presentation can resize the representable during its initial layout.
        // Anchor the page's top after that layout has reached the window.
        DispatchQueue.main.async(execute: action)
    }
}
