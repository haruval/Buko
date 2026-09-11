import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(filter: #Predicate<Note> { $0.deletedAt == nil }, sort: \Note.createdAt, order: .reverse)
    private var notes: [Note]
    @Query(filter: #Predicate<Note> { $0.deletedAt != nil }, sort: \Note.deletedAt, order: .reverse)
    private var trashedNotes: [Note]
    @State private var selectedID: UUID?
    @State private var sidebarVisible = true
    @State private var settingsVisible = false
    @State private var showsTrash = false
    @State private var session = CanvasSession()
    @State private var renamingNote: Note?
    @State private var newTitle = ""
    @State private var persistenceError: String?
    @State private var saveTask: Task<Void, Never>?
    @Namespace private var glassNamespace

    private var selectedNote: Note? {
        notes.first { $0.id == selectedID } ?? notes.first
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color("CanvasBackground").ignoresSafeArea()
                if let note = selectedNote {
                    NoteCanvas(note: note, session: session) { data in
                        note.drawingData = data
                        note.updatedAt = .now
                        scheduleSave()
                    }
                    .id(note.id)
                    .ignoresSafeArea()
                }

                floatingPanels(in: geometry.size)
                    .padding(20)
            }
            .overlay(alignment: .bottom) {
                ToolShelf(session: session)
                    .disabled(selectedNote == nil)
                    .padding(.bottom, 16)
            }
        }
        .tint(.accentColor)
        .task {
            if notes.isEmpty && trashedNotes.isEmpty { createNote() }
            else if selectedID == nil { selectedID = notes.first?.id }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveNow() }
        }
        .alert("Rename note", isPresented: Binding(
            get: { renamingNote != nil },
            set: { if !$0 { renamingNote = nil } }
        )) {
            TextField("Note name", text: $newTitle)
            Button("Cancel", role: .cancel) { renamingNote = nil }
            Button("Save") {
                let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                renamingNote?.title = trimmed.isEmpty ? "Untitled" : trimmed
                renamingNote?.updatedAt = .now
                saveNow()
                renamingNote = nil
            }
        }
        .alert("Notes couldn’t be saved", isPresented: Binding(
            get: { persistenceError != nil },
            set: { if !$0 { persistenceError = nil } }
        )) {
            Button("Retry") { saveNow() }
            Button("Dismiss", role: .cancel) { }
        } message: {
            Text(persistenceError ?? "")
        }
        .alert("Drawing couldn’t be opened", isPresented: Binding(
            get: { session.loadError != nil },
            set: { if !$0 { session.loadError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(session.loadError ?? "")
        }
    }

    private func toggleSidebar() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82)) {
            sidebarVisible.toggle()
            if sidebarVisible && horizontalSizeClass == .compact { settingsVisible = false }
        }
    }

    private func floatingPanels(in size: CGSize) -> some View {
        GlassEffectContainer(spacing: 20) {
            HStack(alignment: .top) {
                ExpandingGlassPanel(
                    isExpanded: sidebarVisible,
                    size: CGSize(width: min(272, size.width - 104), height: max(220, min(640, size.height - 120))),
                    alignment: .topLeading, anchor: .topLeading
                ) {
                    NotesSidebar(
                        notes: notes, selectedID: selectedNote?.id,
                        select: select, create: createNote, hide: toggleSidebar,
                        rename: { note in
                            newTitle = note.title
                            renamingNote = note
                        }, trash: moveToTrash
                    )
                } compact: {
                    ShelfButton(title: "Show notes", symbol: "sidebar.left", action: toggleSidebar)
                        .accessibilityIdentifier("showNotes")
                }
                .glassEffectID("library", in: glassNamespace)

                Spacer(minLength: 12)

                ExpandingGlassPanel(
                    isExpanded: settingsVisible,
                    size: CGSize(width: min(300, size.width - 104),
                                 height: showsTrash ? max(220, min(440, size.height - 120)) : 168),
                    alignment: .topTrailing, anchor: .topTrailing
                ) {
                    SettingsPanel(
                        trashedNotes: trashedNotes, showsTrash: $showsTrash,
                        close: toggleSettings, restore: restore
                    )
                } compact: {
                    ShelfButton(title: "Settings", symbol: "gearshape", action: toggleSettings)
                        .accessibilityIdentifier("openSettings")
                }
                .glassEffectID("settings", in: glassNamespace)
                .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82), value: showsTrash)
            }
        }
    }

    private func toggleSettings() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82)) {
            settingsVisible.toggle()
            if settingsVisible {
                showsTrash = false
                if horizontalSizeClass == .compact { sidebarVisible = false }
            }
        }
    }

    private func moveToTrash(_ note: Note) {
        let wasSelected = selectedNote?.id == note.id
        note.deletedAt = .now
        if wasSelected {
            selectedID = notes.first { $0.id != note.id && $0.deletedAt == nil }?.id
            session = CanvasSession()
        }
        saveNow()
    }

    private func restore(_ note: Note) {
        note.deletedAt = nil
        note.updatedAt = .now
        saveNow()
        session = CanvasSession()
        selectedID = note.id
    }

    private func select(_ note: Note) {
        guard note.id != selectedNote?.id else { return }
        saveNow()
        session = CanvasSession()
        selectedID = note.id
    }

    private func createNote() {
        saveNow()
        let note = Note()
        modelContext.insert(note)
        session = CanvasSession()
        selectedID = note.id
        saveNow()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(500)) }
            catch { return }
            saveNow()
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        do {
            try modelContext.save()
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
        }
    }
}

#Preview("Blank canvas") {
    ContentView()
        .modelContainer(for: Note.self, inMemory: true)
}
