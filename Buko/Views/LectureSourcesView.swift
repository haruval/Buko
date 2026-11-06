import SwiftUI
import UniformTypeIdentifiers
import PDFKit

struct LecturePDFDestination: Identifiable {
    let url: URL
    let page: Int
    var quote = ""
    var title = ""
    var id: String { url.path + ":\(page)" }
}

struct LectureSourcesView: View {
    let noteID: UUID
    var close: (() -> Void)? = nil
    var dragging: (Bool) -> Void = { _ in }
    var split: ((SourceDragReference) -> Void)? = nil
    var library: LectureLibrary = .shared
    @Environment(\.dismiss) private var dismiss
    @State private var documents: [LectureDocument] = []
    @State private var importing = false
    @State private var busy = false
    @State private var deleting = false
    @State private var error: String?
    @State private var operation: Task<Void, Never>?
    @State private var removing: LectureDocument?
    @State private var preview: LecturePDFDestination?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sources").font(.headline)
                Spacer()
                Button("Done", systemImage: "checkmark") { if let close { close() } else { dismiss() } }
                    .labelStyle(.iconOnly).buttonStyle(.glass).controlSize(.large)
                    .accessibilityIdentifier("closeLectureSources")
            }.padding(.horizontal, 20).padding(.top, 16)
            ScrollView {
                GlassEffectContainer(spacing: 18) {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .center, spacing: 12) {
                            Text("\(documents.count) attached \(documents.count == 1 ? "source" : "sources")")
                                .font(.subheadline.weight(.medium))
                                .accessibilityIdentifier("attachedSourcesCount")
                            Spacer(minLength: 0)
                            importButton
                        }
                        if busy {
                            HStack {
                                ProgressView()
                                Text(deleting ? "Deleting source…" : "Reading PDF…")
                                if !deleting { Button("Cancel", role: .cancel) { operation?.cancel() }.buttonStyle(.glass) }
                            }.padding(16).bukoGlass(cornerRadius: 24)
                        }
                        if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("lectureImportError") }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], alignment: .leading, spacing: 16) {
                            ForEach(documents) { document in
                                LectureSourceCard(document: document, noteID: noteID, library: library, busy: busy,
                                    open: { open(document) }, delete: { removing = document },
                                    split: split.map { action in { action(SourceDragReference(noteID: noteID, documentID: document.id)) } })
                                    .draggable(SourceDragReference(noteID: noteID, documentID: document.id))
                                    .onDragSessionUpdated { session in
                                        switch session.phase {
                                        case .active: dragging(true)
                                        case .ended, .dataTransferCompleted: dragging(false)
                                        default: break
                                        }
                                    }
                            }
                        }
                    }.padding(20)
                }
            }
            .task { await refresh() }
            .onDisappear { operation?.cancel() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { result in
                switch result {
                case .success(let url): beginImport(url)
                case .failure(let failure): error = failure.localizedDescription
                }
            }
            .fullScreenCover(item: $preview) { LecturePDFView(destination: $0) }
            .confirmationDialog("Delete this source from the notebook?", isPresented: Binding(
                get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                if let removing {
                    Button("Delete source", role: .destructive) {
                        operation = Task {
                            busy = true; deleting = true
                            defer { busy = false; deleting = false; self.removing = nil }
                            do { try await library.remove(documentID: removing.id, noteID: noteID); await refresh() }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                }
            } message: { Text("The imported copy and its index will be removed. Your original file and handwritten notes stay intact.") }
        }
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private var importButton: some View {
        Button { importing = true } label: {
            Label("Import .pdf", systemImage: "square.and.arrow.down")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 18).frame(minHeight: 46)
        }
            .buttonStyle(.plain)
            .labelStyle(.titleAndIcon)
            .glassEffect(.clear.interactive(), in: .capsule)
            .disabled(busy).fixedSize()
            .accessibilityIdentifier("importLecturePDF")
    }

    private func open(_ document: LectureDocument) {
        Task {
            do {
                let url = try await library.pdfURL(noteID: noteID, documentID: document.id)
                try Task.checkCancellation()
                preview = LecturePDFDestination(url: url, page: document.textDisagreementPages?.first ?? 1, title: document.title)
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }

    private func refresh() async {
        do { documents = try await library.documents(noteID: noteID) }
        catch { self.error = error.localizedDescription }
    }

    private func beginImport(_ url: URL) {
        guard !busy else { return }
        error = nil; busy = true
        operation = Task {
            defer { busy = false }
            do { try await library.importPDF(from: url, noteID: noteID); await refresh() }
            catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}
