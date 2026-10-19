import SwiftUI
import UniformTypeIdentifiers
import PDFKit

struct LecturePDFDestination: Identifiable {
    let url: URL
    let page: Int
    var quote = ""
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
                    Text("Attach lecture PDFs to **\(noteTitle)**. Autofill searches these sources first and shows the pages behind each answer.")
                        .font(.subheadline)
                    Button { importing = true } label: { Label("Import lecture PDF", systemImage: "square.and.arrow.down") }
                        .accessibilityIdentifier("importLecturePDF")
                        .disabled(busy)
                    if let sample = matchingSample {
                        Button { importSample(sample) } label: { Label("Add matching sample PDF", systemImage: "doc.badge.plus") }
                            .accessibilityIdentifier("importMatchingLecture")
                            .disabled(busy)
                    }
                    Menu("Sample lecture PDFs", systemImage: "books.vertical") {
                        ForEach(SampleLecture.allCases) { sample in
                            Button(sample.title.replacingOccurrences(of: "Test ", with: "")) { importSample(sample) }
                        }
                    }.disabled(busy)
                } footer: {
                    Text("Stored and searched on this device. Sources apply only to this notebook. English retrieval and OCR; up to 12 PDFs, 150 pages and 40 MB each.")
                }
                if busy {
                    Section {
                        HStack { ProgressView(); Text("Reading and indexing PDF…") }
                        Button("Cancel import", role: .cancel) { operation?.cancel() }
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("lectureImportError") }
                }
                Section("Attached sources · \(documents.count)") {
                    if documents.isEmpty && !busy { Text("No PDFs attached yet.").foregroundStyle(.secondary) }
                    ForEach(documents) { document in
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                operation = Task {
                                    do { preview = LecturePDFDestination(url: try await library.pdfURL(noteID: noteID, documentID: document.id),
                                                                        page: document.textDisagreementPages?.first ?? 1) }
                                    catch { self.error = error.localizedDescription }
                                }
                            } label: {
                                Label(document.title, systemImage: "doc.richtext").font(.headline)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("lectureDocument")
                            Text("\(document.pageCount) pages · \(document.passages.count) passages")
                                .font(.caption).foregroundStyle(.secondary)
                            if document.passages.contains(where: \.usedOCR) {
                                Text("Includes on-device OCR; check scanned text against the original.").font(.caption)
                            }
                            if !document.skippedPages.isEmpty {
                                Text("No readable text on pages: \(document.skippedPages.map(String.init).joined(separator: ", "))").font(.caption)
                            }
                            if let pages = document.textDisagreementPages, !pages.isEmpty {
                                Label("Searchable text and visible OCR disagree on pages: \(pages.map(String.init).joined(separator: ", ")). Lecture answers are paused for this notebook. Inspect the PDF, then replace or remove this source. OCR may be mistaken.",
                                      systemImage: "exclamationmark.triangle")
                                    .font(.caption).accessibilityIdentifier("lectureTextDisagreement")
                            }
                            Button("Remove source", role: .destructive) { removing = document }
                                .buttonStyle(.borderless).font(.caption).disabled(busy)
                        }.padding(.vertical, 4)
                    }
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
            .sheet(item: $preview) { LecturePDFView(destination: $0) }
            .confirmationDialog("Remove this PDF from the notebook?", isPresented: Binding(
                get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                if let removing {
                    Button("Remove source", role: .destructive) {
                        operation = Task {
                            busy = true
                            defer { busy = false; self.removing = nil }
                            do { try await library.remove(documentID: removing.id, noteID: noteID); await refresh() }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                }
            } message: { Text("The imported copy and its index will be removed. Your original file and handwritten notes stay intact.") }
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

struct LecturePDFView: View {
    let destination: LecturePDFDestination
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            PDFPageView(destination: destination)
                .navigationTitle("Source · page \(destination.page)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("closeLecturePDF")
                } }
        }
    }
}

private struct PDFPageView: UIViewRepresentable {
    let destination: LecturePDFDestination
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true; view.displayMode = .singlePageContinuous
        view.document = PDFDocument(url: destination.url)
        if let page = view.document?.page(at: destination.page - 1) { view.go(to: page) }
        if !destination.quote.isEmpty {
            let selections = view.document?.findString(destination.quote, withOptions: .caseInsensitive)
                .filter { $0.pages.contains { view.document?.index(for: $0) == destination.page - 1 } } ?? []
            for selection in selections { selection.color = .systemYellow.withAlphaComponent(0.35) }
            view.highlightedSelections = selections
        }
        return view
    }
    func updateUIView(_ uiView: PDFView, context: Context) { }
}
