import PencilKit
import SwiftUI

/// Bounded bitmap work stays off the writing actor. The source is never edited.
actor LibraryThumbnailRenderer {
    static let shared = LibraryThumbnailRenderer()

    func render(data: Data, dark: Bool) throws -> Data? {
        try Task.checkCancellation()
        guard data.count <= 24_000_000 else { return nil }
        let drawing = data.isEmpty ? PKDrawing() : try PKDrawing(data: data)
        let page = NotebookPaging.rect(for: 0)
        let ink = MonochromeInk.recolor(PKDrawing(strokes: drawing.strokes.filter { $0.renderBounds.intersects(page) }),
                                       to: dark ? .white : .black)
        try Task.checkCancellation()
        var result: Data?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            result = ink.image(from: page, scale: 0.32).pngData()
        }
        return result
    }
}

struct LibraryThumbnail: View {
    let note: Note
    @Environment(\.colorScheme) private var colorScheme
    @State private var image: UIImage?
    @State private var unreadable = false

    var body: some View {
        ZStack {
            Color("CanvasBackground")
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            if unreadable { Image(systemName: "doc.questionmark").foregroundStyle(.secondary) }
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 18))
        .accessibilityHidden(true)
        .task(id: "\(note.id)-\(note.updatedAt.timeIntervalSince1970)-\(colorScheme)") {
            do {
                try await Task.sleep(for: .milliseconds(300))
                let bytes = try await LibraryThumbnailRenderer.shared.render(data: note.drawingData, dark: colorScheme == .dark)
                try Task.checkCancellation()
                image = bytes.flatMap { UIImage(data: $0) }
                unreadable = bytes == nil
            } catch is CancellationError { }
            catch { image = nil; unreadable = true }
        }
    }
}
