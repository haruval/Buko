import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(filter: #Predicate<Note> { $0.deletedAt == nil }, sort: \Note.updatedAt, order: .reverse)
    private var notes: [Note]
    @Query(filter: #Predicate<Note> { $0.deletedAt != nil }, sort: \Note.deletedAt, order: .reverse)
    private var trashedNotes: [Note]
    @AppStorage("canvasGridEnabled") private var showsGrid = false
    @AppStorage("infiniteCanvasEnabled") private var infiniteCanvasEnabled = false
    @State private var selection: Note?
    @State private var sidebarVisible = true
    @State private var settingsVisible = false
    @State private var showsTrash = false
    @State private var session = CanvasSession()
    @State private var renamingNote: Note?
    @State private var renamePresented = false
    @State private var newTitle = ""
    @State private var persistenceError: String?
    @State private var saveTask: Task<Void, Never>?
    @Namespace private var glassNamespace

    private var selectedNote: Note? {
        selection.flatMap { $0.deletedAt == nil ? $0 : nil } ?? notes.first { $0.deletedAt == nil }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color("CanvasBackground").ignoresSafeArea()
                if let note = selectedNote {
                    NoteCanvas(note: note, session: session, showsGrid: showsGrid,
                               infiniteCanvasEnabled: infiniteCanvasEnabled,
                               onPageChange: { count, index in
                        if count > note.pageCount { note.updatedAt = .now }
                        note.pageCount = count
                        note.currentPageIndex = index
                        scheduleSave()
                    }) { data in
                        note.drawingData = data
                        note.updatedAt = .now
                        scheduleSave()
                    }
                    .id(note.id)
                    .ignoresSafeArea()
                }

                if !infiniteCanvasEnabled {
                    PagePullIndicator(state: session.pagePull)
                        .ignoresSafeArea()
                }

                floatingPanels(in: geometry.size)
                    .environment(\.colorScheme, session.pagePull.topOverBlack ? .dark : colorScheme)
                    .padding(20)
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 12) {
                    ToolShelf(session: session)
                        .disabled(selectedNote == nil)
                }
                .environment(\.colorScheme, session.pagePull.bottomOverBlack ? .dark : colorScheme)
                .padding(.bottom, 16)
            }
        }
        .tint(.accentColor)
        .task {
            normalizeDuplicateTitles()
            if notes.isEmpty && trashedNotes.isEmpty { createNote() }
            else if selection == nil { selection = notes.first }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveNow() }
        }
        .alert("Rename note", isPresented: $renamePresented, presenting: renamingNote) { note in
            TextField("Note name", text: $newTitle)
            Button("Cancel", role: .cancel) { renamingNote = nil }
            Button("Save") {
                let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                note.title = availableTitle(trimmed.isEmpty ? "Untitled" : trimmed, excluding: note.id)
                note.updatedAt = .now
                saveNow()
                renamingNote = nil
            }
            .keyboardShortcut(.defaultAction)
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

    private func panelAnimation(opening: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return .spring(response: opening ? 0.55 : 0.42, dampingFraction: opening ? 0.62 : 0.82)
    }

    private func toggleSidebar() {
        withAnimation(panelAnimation(opening: !sidebarVisible)) {
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
                            renamePresented = true
                        }, trash: moveToTrash
                    )
                } compact: {
                    ShelfButton(title: "Show notes", symbol: "sidebar.left", action: toggleSidebar)
                        .accessibilityIdentifier("showNotes")
                }
                .glassEffectID("library", in: glassNamespace)

                if !sidebarVisible, let note = selectedNote {
                    Text(note.title)
                        .font(.headline)
                        .lineLimit(1)
                        .padding(.horizontal, 20)
                        .frame(height: 52)
                        .frame(maxWidth: settingsVisible ? max(0, size.width - 440) : min(340, size.width - 176))
                        .bukoGlass(cornerRadius: 26)
                        .glassEffectID("note-title", in: glassNamespace)
                        .accessibilityIdentifier("currentNoteTitle")
                        .transition(.scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
                }

                Spacer(minLength: 12)

                ExpandingGlassPanel(
                    isExpanded: settingsVisible,
                    size: CGSize(width: min(300, size.width - 104),
                                 height: showsTrash ? max(220, min(440, size.height - 120)) : 316),
                    alignment: .topTrailing, anchor: .topTrailing
                ) {
                    SettingsPanel(
                        trashedNotes: trashedNotes, showsTrash: $showsTrash, showsGrid: $showsGrid, infiniteCanvasEnabled: $infiniteCanvasEnabled,
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
        withAnimation(panelAnimation(opening: !settingsVisible)) {
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
            selection = notes.first { $0.id != note.id && $0.deletedAt == nil }
            session = CanvasSession()
        }
        saveNow()
    }

    private func restore(_ note: Note) {
        note.deletedAt = nil
        note.updatedAt = .now
        saveNow()
        session = CanvasSession()
        selection = note
    }

    private func select(_ note: Note) {
        guard note.id != selectedNote?.id else { return }
        saveNow()
        session = CanvasSession()
        selection = note
    }

    private func createNote() {
        saveNow()
        let note = Note(title: availableTitle("Untitled"))
        modelContext.insert(note)
        session = CanvasSession()
        selection = note
        saveNow()
    }

    private func availableTitle(_ title: String, excluding id: UUID? = nil) -> String {
        // Fetch includes pending inserts; @Query may still be delivering its update.
        let all = (try? modelContext.fetch(FetchDescriptor<Note>())) ?? (notes + trashedNotes)
        return Note.uniqueTitle(title, occupied: Set(all.filter { $0.id != id }.map(\.title)))
    }

    private func normalizeDuplicateTitles() {
        let all = ((try? modelContext.fetch(FetchDescriptor<Note>())) ?? (notes + trashedNotes))
            .sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
        var occupied = Set(all.map(\.title))
        var seen = Set<String>()
        for note in all {
            if !seen.insert(note.title).inserted {
                note.title = Note.uniqueTitle(note.title, occupied: occupied)
                occupied.insert(note.title)
            }
        }
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
