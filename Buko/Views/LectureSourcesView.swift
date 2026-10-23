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
    let noteTitle: String
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

    private var matchingSample: SampleLecture? {
        SampleLecture.allCases.first { UserDefaults.standard.string(forKey: $0.storageKey) == noteID.uuidString }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Attach lecture PDFs to **\(noteTitle)**. Autofill uses these sources and shows the exact passages behind each answer.")
                        .font(.subheadline)
                    Button { importing = true } label: { Label("Import lecture PDF", systemImage: "square.and.arrow.down") }
                        .accessibilityIdentifier("importLecturePDF")
                        .disabled(busy)
                    if let sample = matchingSample {
                        Button { importSample(sample) } label: { Label("Add matching sample PDF", systemImage: "doc.badge.plus") }
                            .accessibilityIdentifier("importMatchingLecture")
                            .disabled(busy)
                    }
                    Menu {
                        ForEach(SampleLecture.allCases) { sample in
                            Button(sample.title.replacingOccurrences(of: "Test ", with: "")) { importSample(sample) }
                                .accessibilityIdentifier("importSample.\(sample.rawValue)")
                        }
                    } label: {
                        Label("Sample lecture PDFs", systemImage: "books.vertical")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.borderless)
                    .disabled(busy).accessibilityIdentifier("sampleLectureMenu")
                } footer: {
                    Text("Stored and searched on this device. Sources apply only to this notebook. English retrieval and OCR; up to 12 PDFs, 150 pages and 40 MB each.")
                }
                if busy {
                    Section {
                        HStack { ProgressView(); Text(deleting ? "Deleting source…" : "Reading and indexing PDF…") }
                        if !deleting { Button("Cancel import", role: .cancel) { operation?.cancel() } }
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("lectureImportError") }
                }
                Section {
                    if documents.isEmpty && !busy { Text("No PDFs attached yet.").foregroundStyle(.secondary) }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)], alignment: .leading, spacing: 24) {
                        ForEach(documents) { document in
                            LectureSourceCard(document: document, noteID: noteID, library: library, busy: busy,
                                open: { open(document) }, delete: { removing = document })
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 12, trailing: 0))
                } header: {
                    Text("\(documents.count) attached \(documents.count == 1 ? "source" : "sources")")
                        .textCase(nil).accessibilityIdentifier("attachedSourcesCount")
                }

            }
            .navigationTitle("Lecture sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.accessibilityIdentifier("closeLectureSources")
            } }
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

    private func importSample(_ sample: SampleLecture) {
        guard let url = Bundle.main.url(forResource: sample.rawValue, withExtension: "pdf") else {
            error = "The bundled sample PDF is missing."; return
        }
        beginImport(url)
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
