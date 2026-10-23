import SwiftUI
import PDFKit

struct LecturePDFView: View {
    let destination: LecturePDFDestination
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 1
    @State private var pageCount = 0
    @State private var loadError = false

    var body: some View {
        GeometryReader { geometry in
            card
                .background(.background)
                .clipShape(.rect(cornerRadius: 28))
                .padding(.horizontal, min(24, geometry.size.width * 0.025))
                .padding(.vertical, 12)
        }
        .presentationBackground(.black.opacity(0.32))
        .accessibilityIdentifier("lecturePDFPreview")
    }

    private var card: some View {
        NavigationStack {
            PDFPageView(destination: destination, currentPage: $currentPage, pageCount: $pageCount, loadError: $loadError)
                .accessibilityIdentifier("lecturePDFContent")
                .overlay {
                    if loadError { ContentUnavailableView("Couldn’t open this PDF", systemImage: "doc.questionmark", description: Text("Close this preview and try attaching the source again.")) }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                            .accessibilityLabel("Close PDF preview").accessibilityIdentifier("closeLecturePDF")
                    }
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 3) {
                            Text(destination.title.isEmpty ? "Lecture PDF" : destination.title).font(.headline).lineLimit(1)
                            if pageCount > 0 { Text("Page \(currentPage) of \(pageCount)").font(.caption).foregroundStyle(.secondary) }
                        }.accessibilityIdentifier("lecturePDFTitle")
                    }
                }
        }
    }
}

private struct PDFPageView: UIViewRepresentable {
    let destination: LecturePDFDestination
    @Binding var currentPage: Int
    @Binding var pageCount: Int
    @Binding var loadError: Bool

    func makeUIView(context: Context) -> SourcePDFView {
        let view = SourcePDFView()
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
    func updateUIView(_ view: SourcePDFView, context: Context) { }
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
    override func layoutSubviews() {
        super.layoutSubviews()
        guard window != nil, bounds.width > 0, bounds.height > 0, let action = firstLayout else { return }
        firstLayout = nil
        // Presentation can resize the representable during its initial layout.
        // Anchor the page's top after that layout has reached the window.
        DispatchQueue.main.async(execute: action)
    }
}
