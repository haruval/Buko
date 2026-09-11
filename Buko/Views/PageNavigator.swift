import PencilKit
import SwiftUI

struct PageNavigator: View {
    let note: Note
    let session: CanvasSession
    let availableHeight: CGFloat
    @Binding var isExpanded: Bool
    let rename: (NotebookPage, Int) -> Void
    let trash: (NotebookPage) -> Void
    let trashSelection: (Set<UUID>) -> Bool
    let opening: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var thumbnailDrawing = PKDrawing()
    @State private var selectedIDs = Set<UUID>()

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
                        Text(selectedIDs.isEmpty ? "Pages" : "\(selectedIDs.count) selected")
                            .font(.title3.weight(.semibold))
                        Spacer()
                        ShelfButton(title: "Close pages", symbol: "xmark", action: toggle)
                    }
                    if !selectedIDs.isEmpty {
                        HStack {
                            Text("Hold a circle to delete together")
                                .font(.caption2).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Button("Clear") { selectedIDs.removeAll() }
                                .font(.caption.weight(.medium))
                        }
                    }
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 18) {
                                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                                    Button {
                                        if selectedIDs.isEmpty {
                                            session.navigate(to: index)
                                            toggle()
                                        } else { toggleSelection(page.id) }
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
                                        .background(selectedIDs.contains(page.id) ? Color.accentColor.opacity(0.22)
                                                    : index + 1 == current ? Color.accentColor.opacity(0.12) : .clear,
                                                    in: .rect(cornerRadius: 18))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(page.title.isEmpty ? "Page \(index + 1)" : "\(page.title), page \(index + 1)")
                                    .accessibilityIdentifier("pageThumbnail")
                                    .accessibilityAddTraits(index + 1 == current ? [.isSelected] : [])
                                    .contextMenu {
                                        if selectedIDs.contains(page.id) {
                                            selectionActions(ids: selectedIDs)
                                        } else {
                                            Button("Rename page", systemImage: "pencil") { rename(page, index) }
                                            Button("Delete page", systemImage: "trash", role: .destructive) { trash(page) }
                                        }
                                    }
                                    .overlay(alignment: .topTrailing) {
                                        // A sibling button, never a button nested in the
                                        // navigation label, so tapping won't jump pages.
                                        Button { toggleSelection(page.id) } label: {
                                            Image(systemName: selectedIDs.contains(page.id) ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 21, weight: .regular))
                                                .frame(width: 44, height: 44)
                                                .contentShape(.circle)
                                        }
                                        .buttonStyle(.plain)
                                        .bukoGlass(cornerRadius: 22, interactive: true)
                                        .accessibilityLabel("Select page \(index + 1)")
                                        .accessibilityValue(selectedIDs.contains(page.id) ? "Selected" : "Not selected")
                                        .accessibilityIdentifier("selectPage-\(index + 1)")
                                        .contextMenu {
                                            selectionActions(ids: selectedIDs.contains(page.id) ? selectedIDs : [page.id])
                                        }
                                        .padding(16)
                                    }
                                    .id(page.id)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        .accessibilityIdentifier("pageThumbnailList")
                        .onAppear {
                            if let page = pages.indices.contains(current - 1) ? pages[current - 1] : nil {
                                proxy.scrollTo(page.id, anchor: .center)
                            }
                        }
                    }
                }
                .padding(16)
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
        .onChange(of: isExpanded) { _, expanded in if !expanded { selectedIDs.removeAll() } }
        .onChange(of: note.id) { _, _ in selectedIDs.removeAll(); thumbnailDrawing = PKDrawing() }
        .onChange(of: pages.map(\.id)) { _, ids in selectedIDs.formIntersection(ids) }
        .task(id: isExpanded ? note.updatedAt : .distantPast) {
            guard isExpanded else { return }
            if let drawing = try? NotebookEdits.drawing(note.drawingData) { thumbnailDrawing = drawing }
        }
    }

    private func toggleSelection(_ id: UUID) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.75)) {
            if !selectedIDs.insert(id).inserted { selectedIDs.remove(id) }
        }
    }

    @ViewBuilder
    private func selectionActions(ids: Set<UUID>) -> some View {
        Button(ids.count == 1 ? "Delete selected page" : "Delete \(ids.count) selected pages",
               systemImage: "trash", role: .destructive) {
            if trashSelection(ids) { selectedIDs.subtract(ids) }
        }
        Button("Clear selection", systemImage: "circle") { selectedIDs.removeAll() }
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
