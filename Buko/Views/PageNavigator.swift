import PencilKit
import SwiftUI

struct PageNavigator: View {
    let note: Note
    let session: CanvasSession
    let availableHeight: CGFloat
    @Binding var isExpanded: Bool
    let rename: (NotebookPage, Int) -> Void
    let trash: (NotebookPage) -> Void
    let opening: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var thumbnailDrawing = PKDrawing()

    private var pages: [NotebookPage] { note.activePages }
    private var current: Int { pages.isEmpty ? 0 : min(pages.count, session.pagePull.pageIndex + 1) }

    private func toggle() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.68)) {
            isExpanded.toggle()
            if isExpanded { opening() }
        }
    }

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            ExpandingGlassPanel(isExpanded: isExpanded,
                size: CGSize(width: 252, height: max(240, min(620, availableHeight - 180))),
                alignment: .trailing, anchor: .trailing, compactSize: CGSize(width: 56, height: 172)) {
                VStack(spacing: 14) {
                    HStack {
                        Text("Pages").font(.title3.weight(.semibold))
                        Spacer()
                        ShelfButton(title: "Close pages", symbol: "xmark", action: toggle)
                    }
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 18) {
                                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                                    Button {
                                        session.navigate(to: index)
                                        toggle()
                                    } label: {
                                        VStack(alignment: .leading, spacing: 8) {
                                            PageThumbnail(drawing: thumbnailDrawing, index: index,
                                                          revision: note.updatedAt, colorScheme: colorScheme)
                                            HStack {
                                                Text(page.title.isEmpty ? "Page \(index + 1)" : page.title)
                                                    .lineLimit(2)
                                                Spacer(minLength: 4)
                                                Text("\(index + 1)").foregroundStyle(.secondary)
                                            }
                                            .font(.caption.weight(.medium))
                                        }
                                        .padding(10)
                                        .background(index + 1 == current ? Color.accentColor.opacity(0.12) : .clear,
                                                    in: .rect(cornerRadius: 18))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(page.title.isEmpty ? "Page \(index + 1)" : "\(page.title), page \(index + 1)")
                                    .accessibilityIdentifier("pageThumbnail")
                                    .accessibilityAddTraits(index + 1 == current ? [.isSelected] : [])
                                    .contextMenu {
                                        Button("Rename page", systemImage: "pencil") { rename(page, index) }
                                        Button("Delete page", systemImage: "trash", role: .destructive) { trash(page) }
                                    }
                                    .id(page.id)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        .onAppear {
                            if let page = pages.indices.contains(current - 1) ? pages[current - 1] : nil {
                                proxy.scrollTo(page.id, anchor: .center)
                            }
                        }
                    }
                }
                .padding(16)
                .transition(.opacity)
            } compact: {
                Button(action: toggle) {
                    VStack(spacing: 14) {
                        ZStack(alignment: .top) {
                            Capsule().fill(.primary.opacity(0.15)).frame(width: 4, height: 104)
                            Capsule().fill(.primary.opacity(0.8)).frame(width: 4, height: 18)
                                .offset(y: session.pagePull.scrollProgress * 86)
                        }
                        Text("\(current)/\(pages.count)")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                    }
                    .frame(width: 56, height: 172)
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Page navigator")
                .accessibilityValue("\(current) of \(pages.count)")
                .accessibilityIdentifier("pageNavigator")
            }
        }
        .task(id: isExpanded ? note.updatedAt : .distantPast) {
            guard isExpanded else { return }
            if let drawing = try? NotebookEdits.drawing(note.drawingData) { thumbnailDrawing = drawing }
        }
    }
}

private struct PageThumbnail: View {
    let drawing: PKDrawing
    let index: Int
    let revision: Date
    let colorScheme: ColorScheme
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color("CanvasBackground")
            if let image { Image(uiImage: image).resizable().scaledToFit() }
        }
        .aspectRatio(1032.0 / 1376, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(.primary.opacity(0.12), lineWidth: 0.5) }
        .accessibilityHidden(true)
        .task(id: "\(revision.timeIntervalSince1970)-\(drawing.strokes.count)-\(colorScheme)") {
            let ink = MonochromeInk.recolor(drawing, to: colorScheme == .dark ? .white : .black)
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                image = ink.image(from: NotebookPaging.rect(for: index), scale: 0.24)
            }
        }
    }
}
