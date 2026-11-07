import SwiftUI
import PDFKit

extension LectureLibrary {
    /// The library actor keeps PDF decoding off the PencilKit/UI actor. Only a
    /// bounded cover image crosses back to the view; original PDFs are untouched.
    func coverThumbnail(noteID: UUID, documentID: String) throws -> Data {
        try Task.checkCancellation()
        let url = try pdfURL(noteID: noteID, documentID: documentID)
        let data: Data? = autoreleasepool {
            guard let pdf = PDFDocument(url: url), let page = pdf.page(at: 0) else { return nil }
            return page.thumbnail(of: CGSize(width: 440, height: 580), for: .cropBox).pngData()
        }
        try Task.checkCancellation()
        guard let data else { throw LibraryError.unreadablePDF }
        return data
    }
}

struct LectureSourceCard: View {
    let document: LectureDocument
    let noteID: UUID
    let library: LectureLibrary
    let busy: Bool
    let open: () -> Void
    let delete: () -> Void
    var openBeside: (() -> Void)? = nil
    @State private var thumbnail: UIImage?
    @State private var thumbnailFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14).fill(.white)
                        if let thumbnail {
                            Image(uiImage: thumbnail).resizable().scaledToFit().padding(8)
                        } else if thumbnailFailed {
                            Image(systemName: "doc.richtext").font(.largeTitle).foregroundStyle(.gray)
                        } else { ProgressView().tint(.gray) }
                    }
                    .aspectRatio(0.76, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 14))
                    .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.08), lineWidth: 1) }
                    Text(document.title).font(.subheadline.weight(.medium)).lineLimit(2)
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
                    Text("\(document.pageCount) \(document.pageCount == 1 ? "page" : "pages")")
                        .font(.caption).foregroundStyle(.secondary)
                }.contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(document.title), \(document.pageCount) pages")
            .accessibilityHint("Opens the PDF.")
            .accessibilityIdentifier("lectureDocument")
            .contextMenu {
                if let openBeside { Button("Open beside note", systemImage: "rectangle.split.2x1", action: openBeside) }
                Button("Delete", systemImage: "trash", role: .destructive, action: delete).disabled(busy)
            }
            if let pages = document.textDisagreementPages, !pages.isEmpty {
                Label("Text needs review on pages \(pages.map(String.init).joined(separator: ", ")). Autofill is paused for this notebook.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("lectureTextDisagreement")
            } else if !document.skippedPages.isEmpty {
                Text("No readable text on pages \(document.skippedPages.map(String.init).joined(separator: ", ")).")
                    .font(.caption).foregroundStyle(.secondary)
            } else if document.passages.contains(where: \.usedOCR) {
                Text("Scanned PDF · OCR text").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .topLeading)
        .bukoGlass(cornerRadius: 28)
        .task(id: document.id) {
            do {
                let data = try await library.coverThumbnail(noteID: noteID, documentID: document.id)
                try Task.checkCancellation()
                thumbnail = UIImage(data: data); thumbnailFailed = thumbnail == nil
            } catch is CancellationError { }
            catch { thumbnailFailed = true }
        }
    }
}
