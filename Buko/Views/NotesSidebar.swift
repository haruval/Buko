import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
    static let bukoNote = UTType(exportedAs: "dev.buko.note-reference")
}

struct NoteDragReference: Codable, Transferable {
    let id: UUID
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .bukoNote)
    }
}

struct NotesSidebar: View {
    let notes: [Note]
    let folders: [NoteFolder]
    let selectedID: UUID?
    var canCollapse = true
    let select: (Note) -> Void
    let create: (UUID?) -> Void
    let hide: () -> Void
    let rename: (Note) -> Void
    let trash: (Note) -> Void
    let group: (Note, Note) -> Bool
    let move: (Note, NoteFolder?) -> Bool
    let renameFolder: (NoteFolder, String) -> Void
    var openBeside: ((Note) -> Void)? = nil
    let ungroup: (NoteFolder) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var openFolderID: UUID?
    @State private var folderTitle = ""
    @FocusState private var editingTitle: Bool

    private var openFolder: NoteFolder? { folders.first { $0.id == openFolderID } }
    private var visibleNotes: [Note] {
        notes.filter { note in
            if let openFolder { return note.folderID == openFolder.id }
            return note.folderID == nil || !folders.contains { $0.id == note.folderID }
        }
    }
    private var entries: [LibraryEntry] {
        (openFolder == nil ? folders.map(LibraryEntry.folder) : []) + visibleNotes.map(LibraryEntry.note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 4) {
                Text("buko")
                    .font(.system(size: 30, weight: .semibold, design: .rounded)).tracking(-1.5)
                Spacer(minLength: 0)
                if canCollapse {
                    ShelfButton(title: "Hide notes", symbol: "sidebar.left", action: hide)
                        .accessibilityIdentifier("hideNotes")
                }
            }
            libraryContents
        }
        .padding(16)
        .onChange(of: editingTitle) { _, focused in
            if !focused, let folder = openFolder { renameFolder(folder, folderTitle) }
        }
        .onChange(of: folders.map(\.id)) { _, ids in
            if let openFolderID, !ids.contains(openFolderID) { self.openFolderID = nil }
        }
    }

    @ViewBuilder private var libraryContents: some View {
        if let folder = openFolder {
            VStack(alignment: .leading, spacing: 8) {
                Button { closeFolder() } label: { Label("Notes", systemImage: "chevron.left") }
                    .font(.subheadline.weight(.medium)).buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("folderBack")
                    .modifier(NoteDropTarget { refs in receive(refs) { move($0, nil) } })
                TextField("Folder name", text: $folderTitle)
                    .font(.title2.weight(.semibold)).textFieldStyle(.plain)
                    .focused($editingTitle)
                    .submitLabel(.done)
                    .onSubmit { renameFolder(folder, folderTitle); editingTitle = false }
                    .accessibilityIdentifier("folderTitle")
            }
        } else {
            Text("Notes").font(.title2.weight(.semibold)).padding(.horizontal, 4)
        }
        ScrollView {
            GlassEffectContainer(spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    column(parity: 0)
                    column(parity: 1).padding(.top, entries.count > 1 ? 34 : 0)
                }
                .padding(.horizontal, 2).padding(.vertical, 6)
            }
            if entries.isEmpty {
                Text("New notes will appear here.")
                    .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 28)
            }
        }
        .scrollIndicators(.hidden)
        Button { create(openFolder?.id) } label: {
            Label("New note", systemImage: "plus")
                .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 46)
        }
        .buttonStyle(.plain).bukoGlass(interactive: true)
        .accessibilityIdentifier("newNote")
    }

    private func column(parity: Int) -> some View {
        LazyVStack(spacing: 14) {
            ForEach(Array(entries.enumerated()).filter { $0.offset % 2 == parity }.map(\.element)) { entry in
                switch entry {
                case .note(let note): noteCard(note)
                case .folder(let folder): folderCard(folder)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func noteCard(_ note: Note) -> some View {
        LibraryCard(action: { select(note) }) {
            Text(note.title).font(.subheadline.weight(.semibold)).lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            LibraryThumbnail(note: note)
        }
        .accessibilityLabel(note.title)
        .accessibilityIdentifier("noteRow")
        .accessibilityAddTraits(note.id == selectedID ? [.isSelected] : [])
        .draggable(NoteDragReference(id: note.id))
        .modifier(NoteDropTarget { refs in receive(refs) { group($0, note) } })
        .contextMenu {
            if let openBeside { Button("Open beside current note", systemImage: "rectangle.split.2x1") { openBeside(note) } }
            Button("Rename", systemImage: "pencil") { rename(note) }
            Menu("Move to", systemImage: "folder") {
                if note.folderID != nil { Button("Notes") { _ = move(note, nil) } }
                ForEach(folders.filter { $0.id != note.folderID }) { folder in
                    Button(folder.title) { _ = move(note, folder) }
                }
            }
            Button("Delete", systemImage: "trash", role: .destructive) { trash(note) }
        }
    }

    private func folderCard(_ folder: NoteFolder) -> some View {
        let children = notes.filter { $0.folderID == folder.id }
        return LibraryCard(action: {
            withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82)) {
                folderTitle = folder.title; openFolderID = folder.id
            }
        }) {
            Label(folder.title, systemImage: "folder")
                .font(.subheadline.weight(.semibold)).lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            if children.isEmpty {
                Image(systemName: "folder").font(.largeTitle).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5)], spacing: 5) {
                    ForEach(Array(children.prefix(4))) { LibraryThumbnail(note: $0) }
                }
            }
            Text("\(children.count) \(children.count == 1 ? "note" : "notes")")
                .font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityLabel("\(folder.title), folder, \(children.count) notes")
        .accessibilityIdentifier("folderCard")
        .modifier(NoteDropTarget { refs in receive(refs) { move($0, folder) } })
        .contextMenu { Button("Ungroup notes", systemImage: "folder.badge.minus") { ungroup(folder) } }
    }

    private func closeFolder() {
        if let folder = openFolder { renameFolder(folder, folderTitle) }
        editingTitle = false
        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82)) { openFolderID = nil }
    }

    private func receive(_ refs: [NoteDragReference], action: (Note) -> Bool) -> Bool {
        guard refs.count == 1, let note = notes.first(where: { $0.id == refs[0].id }) else { return false }
        return action(note)
    }
}

private enum LibraryEntry: Identifiable {
    case note(Note), folder(NoteFolder)
    var id: UUID { switch self { case .note(let n): n.id; case .folder(let f): f.id } }
}

private struct LibraryCard<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10, content: content)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect(cornerRadius: 28))
        }
        .buttonStyle(LibraryPressStyle())
        .contentShape(.contextMenuPreview, .rect(cornerRadius: 28))
        .contentShape(.dragPreview, .rect(cornerRadius: 28))
    }
}

private struct LibraryPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .bukoGlass(cornerRadius: 28)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 1.055 : 1)
            .animation(reduceMotion ? nil : (configuration.isPressed ? .easeIn(duration: 0.45) : .spring(response: 0.24, dampingFraction: 0.8)), value: configuration.isPressed)
    }
}

private struct NoteDropTarget: ViewModifier {
    let receive: ([NoteDragReference]) -> Bool
    @State private var targeted = false
    func body(content: Content) -> some View {
        content
            .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(targeted ? Color.accentColor : .clear, lineWidth: 3).allowsHitTesting(false) }
            .dropDestination(for: NoteDragReference.self, action: { refs, _ in
                return receive(refs)
            }, isTargeted: { targeted = $0 })
    }
}
