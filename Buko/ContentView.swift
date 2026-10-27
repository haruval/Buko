import PencilKit
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
    @Query(sort: \TrashedPage.deletedAt, order: .reverse) private var trashedPages: [TrashedPage]
    @Query(sort: \NoteFolder.createdAt, order: .reverse) private var folders: [NoteFolder]
    @AppStorage("canvasGridEnabled") private var showsGrid = false
    @AppStorage("pplTestNoteID") private var pplTestNoteID = ""
    @AppStorage("testPPLLectureTitleMigrated") private var testPPLLectureTitleMigrated = false
    @State private var showsDevelopment = false
    @State private var showsHandwritingPreview = false
    @State private var lectureSourceNote: Note?
    @State private var canvasRevision = UUID()
    @State private var pagesVisible = false
    @State private var renamingPage: NotebookPage?
    @State private var renamePagePresented = false
    @State private var pageTitle = ""
    @State private var emptyTrashPresented = false
    @State private var emptyNoteIDs = Set<UUID>()
    @State private var emptyPageIDs = Set<UUID>()
    @State private var selection: Note?
    @State private var sidebarVisible = true
    @State private var settingsVisible = false
    @State private var showsTrash = false
    @State private var session = CanvasSession()
    @State private var handwriting = HandwritingPreparation()
    @State private var renamingNote: Note?
    @State private var renamePresented = false
    @State private var newTitle = ""
    @State private var persistenceError: String?
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var titleFocused: Bool
    @Namespace private var glassNamespace

    private var selectedNote: Note? {
        selection.flatMap { $0.deletedAt == nil ? $0 : nil }
    }

    var body: some View {
        configuredWorkspace
        .alert("Rename note", isPresented: $renamePresented, presenting: renamingNote) { note in
            TextField("Note name", text: $newTitle)
            Button("Cancel", role: .cancel) { renamingNote = nil }
            Button("Save") {
                renameNote(note, to: newTitle)
                renamingNote = nil
            }
            .keyboardShortcut(.defaultAction)
        }
        .alert("Rename page", isPresented: $renamePagePresented, presenting: renamingPage) { page in
            TextField("Page name", text: $pageTitle)
            Button("Cancel", role: .cancel) { renamingPage = nil }
            Button("Save") {
                guard let note = selectedNote else { return }
                performEdit(notes: [note]) { try NotebookEdits.rename(page.id, in: note, to: pageTitle) }
                renamingPage = nil
            }
            .keyboardShortcut(.defaultAction)
        }
        .alert("Empty Trash?", isPresented: $emptyTrashPresented) {
            Button("Cancel", role: .cancel) { }
            Button("Delete permanently", role: .destructive) {
                let owners = Set(trashedPages.filter { emptyPageIDs.contains($0.id) }.map(\.noteID))
                performEdit(notes: (notes + trashedNotes).filter { owners.contains($0.id) }) {
                    try NotebookEdits.emptyTrash(noteIDs: emptyNoteIDs, pageIDs: emptyPageIDs, context: modelContext)
                }
            }
        } message: {
            Text("Permanently delete \(emptyNoteIDs.count) notes and \(emptyPageIDs.count) pages from Trash? This cannot be undone.")
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

    private var configuredWorkspace: some View {
        let handwritingStamps = notes.map { HandwritingPreparation.Stamp($0) }
        return workspace
        .ignoresSafeArea(.keyboard)
        .tint(.accentColor)
        .task {
            normalizeDuplicateTitles()
            migrateTestLectureTitle()
            if pplTestNoteID.isEmpty { recreateTestNote(.programmingLanguages) }
            if selection == nil {
                if notes.isEmpty && trashedNotes.isEmpty { createNote() }
                else if let note = notes.first { select(note) }
            }
            for lecture in [SampleLecture.operatingSystems, .linearAlgebra, .biology101] {
                if UserDefaults.standard.string(forKey: lecture.storageKey) == nil {
                    recreateTestNote(lecture, selectCreated: false)
                }
            }
        }
        .onAppear { refreshHandwriting() }
        .onChange(of: handwritingStamps) { _, _ in refreshHandwriting() }
        .onChange(of: selectedNote?.id) { _, _ in refreshHandwriting() }
        .onChange(of: session.host?.circleIntent.phase) { _, _ in refreshHandwriting() }
        .onDisappear { handwriting.setPaused(true) }
        .sheet(item: $lectureSourceNote) { note in
            LectureSourcesView(noteID: note.id, noteTitle: note.title)
        }
        .sheet(isPresented: $showsHandwritingPreview) {
            HandwritingPreviewView(preparation: handwriting, noteID: selectedNote?.id)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                session.host?.circleIntent.cancel(); saveNow()
            }
            refreshHandwriting()
        }
        .onChange(of: sidebarVisible) { _, _ in titleFocused = false }
        .onChange(of: settingsVisible) { _, _ in titleFocused = false }
        .onChange(of: pagesVisible) { _, _ in titleFocused = false }
        .onChange(of: session.isDrawing) { _, drawing in
            if drawing { titleFocused = false }
            refreshHandwriting()
        }
    }

    private var workspace: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color("CanvasBackground").ignoresSafeArea()
                if let note = selectedNote, note.pageCount > 0 {
                    drawingCanvas(for: note, revision: canvasRevision)
                }

                if let note = selectedNote, note.pageCount == 0 {
                    ContentUnavailableView {
                        Label("No pages", systemImage: "doc")
                    } description: {
                        Text("Restore a page from Trash or start a new one.")
                    } actions: {
                        Button("Add page") { addBlankPage(to: note) }
                            .buttonStyle(.glass)
                    }
                }

                PagePullIndicator(state: session.pagePull)
                    .ignoresSafeArea()

                if settingsVisible {
                    Color.clear.contentShape(.rect).ignoresSafeArea()
                        .onTapGesture { toggleSettings() }
                        .accessibilityLabel("Dismiss settings")
                        .accessibilityIdentifier("dismissSettingsBackdrop")
                }

                floatingPanels(in: geometry.size)
                    .environment(\.colorScheme, session.pagePull.topOverBlack ? .dark : colorScheme)
                    .padding(.horizontal, 20)
                    .padding(.top, WorkspaceChrome.topPadding)
                    .padding(.bottom, 20)
            }
            .overlay(alignment: .trailing) {
                if let note = selectedNote {
                    pageNavigation(for: note, height: geometry.size.height)
                }
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 12) {
                    ToolShelf(session: session) {
                        session.host?.circleIntent.cancel()
                        lectureSourceNote = selectedNote
                    }
                        .simultaneousGesture(TapGesture().onEnded {
                            if settingsVisible { toggleSettings() }
                        })
                        .disabled(selectedNote == nil || selectedNote?.pageCount == 0)
                }
                .environment(\.colorScheme, session.pagePull.bottomOverBlack ? .dark : colorScheme)
                .padding(.bottom, 16)
            }
        }
    }

    private func drawingCanvas(for note: Note, revision: UUID) -> some View {
        NoteCanvas(note: note, session: session, showsGrid: showsGrid,
                   onPageChange: { (count: Int, index: Int) in
            recordPosition(note: note, count: count, index: index, revision: revision)
        }, onDrawingChange: { (data: Data) in
            guard revision == canvasRevision else { return }
            note.drawingData = data
            note.updatedAt = .now
            handwriting.invalidate(noteID: note.id)
            refreshHandwriting()
            scheduleSave()
        }, preparedHandwriting: { proposal in
            handwriting.prepared(for: proposal)
        }, onAutofillCommit: { before, after in
            guard revision == canvasRevision, selectedNote?.id == note.id,
                  note.deletedAt == nil, !session.isDrawing,
                  before.matches(AutofillDocument(note)) else { throw AutofillEditError.stale }
            guard saveNow() else { throw AutofillEditError.unavailable }
            do {
                try NotebookEdits.commit(in: modelContext, notes: [note]) { after.apply(to: note) }
                handwriting.invalidate(noteID: note.id)
                refreshHandwriting()
            } catch {
                persistenceError = error.localizedDescription
                throw error
            }
        })
        .id("\(note.id)-\(revision)")
        .ignoresSafeArea()
    }

    private func recordPosition(note: Note, count: Int, index: Int, revision: UUID) {
        guard revision == canvasRevision else { return }
        if count > note.pageCount {
            do { try NotebookEdits.appendMetadata(to: note, count: count) }
            catch { persistenceError = error.localizedDescription; return }
            note.updatedAt = .now
        }
        note.currentPageIndex = index
        scheduleSave()
    }

    private func pageNavigation(for note: Note, height: CGFloat) -> some View {
        PageNavigator(note: note, session: session, availableHeight: height,
                      isExpanded: $pagesVisible,
                      rename: { (page: NotebookPage, _: Int) in
            renamingPage = page
            pageTitle = page.title
            renamePagePresented = true
        }, trash: { (page: NotebookPage) in
            trashPage(page, from: note)
        }, trashSelection: { ids in
            trashPages(ids, from: note)
        }, opening: { settingsVisible = false })
        .environment(\.colorScheme, session.pagePull.rightOverBlack ? .dark : colorScheme)
        .padding(.trailing, 20)
    }

    private func panelAnimation(opening: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return .spring(response: opening ? 0.55 : 0.42, dampingFraction: opening ? 0.62 : 0.82)
    }

    private func toggleSidebar() {
        withAnimation(panelAnimation(opening: !sidebarVisible)) {
            sidebarVisible.toggle()
            settingsVisible = false
        }
    }

    private func floatingPanels(in size: CGSize) -> some View {
        GlassEffectContainer(spacing: 20) {
            HStack(alignment: .top) {
                ExpandingGlassPanel(
                    isExpanded: sidebarVisible,
                    size: CGSize(width: min(max(320, size.width / 3), size.width - 84), height: max(220, size.height - 124)),
                    alignment: .topLeading, anchor: .topLeading,
                    expandedBackingOpacity: 0.5
                ) {
                    NotesSidebar(
                        notes: notes, folders: folders, selectedID: selectedNote?.id,
                        select: select, create: { createNote(in: $0) }, hide: toggleSidebar,
                        rename: { note in
                            newTitle = note.title
                            renamingNote = note
                            renamePresented = true
                        }, trash: moveToTrash,
                        group: { source, target in
                            guard source.id != target.id else { return false }
                            return organize { try LibraryOrganization.group(source, with: target, in: modelContext) }
                        }, move: { note, folder in
                            organize { try LibraryOrganization.move(note, to: folder, in: modelContext) }
                        }, renameFolder: { folder, title in
                            _ = organize { try LibraryOrganization.rename(folder, to: title, in: modelContext) }
                        }, ungroup: { folder in
                            _ = organize { try LibraryOrganization.ungroup(folder, in: modelContext) }
                        }
                    )
                } compact: {
                    ShelfButton(title: "Show notes", symbol: "sidebar.left", action: toggleSidebar)
                        .accessibilityIdentifier("showNotes")
                }
                .glassEffectID("library", in: glassNamespace)

                if !sidebarVisible, let note = selectedNote {
                    NoteTitlePill(title: note.title, width: min(420, max(100, size.width - 440)), focus: $titleFocused) { title in
                        renameNote(note, to: title)
                    }
                    .id(note.id)
                        .glassEffectID("note-title", in: glassNamespace)
                        .transition(.scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
                }

                Spacer(minLength: 12)

                ExpandingGlassPanel(
                    isExpanded: settingsVisible,
                    size: CGSize(width: min(showsTrash ? 300 : showsDevelopment ? 320 : 224, size.width - 104),
                                 height: showsTrash ? max(220, min(440, size.height - 120)) : showsDevelopment ? min(390, size.height - 120) : 208),
                    alignment: .topTrailing, anchor: .topTrailing
                ) {
                    SettingsPanel(
                        trashedNotes: trashedNotes, trashedPages: trashedPages, showsTrash: $showsTrash,
                        showsDevelopment: $showsDevelopment, showsGrid: $showsGrid,
                        previewHandwriting: {
                            session.host?.circleIntent.cancel()
                            showsHandwritingPreview = true
                        }, recreateTestNote: { lecture in
                            recreateTestNote(lecture)
                            if settingsVisible { toggleSettings() }
                        }, restore: restore, restorePage: restorePage,
                        emptyTrash: {
                            emptyNoteIDs = Set(trashedNotes.map(\.id))
                            emptyPageIDs = Set(trashedPages.map(\.id))
                            emptyTrashPresented = true
                        }
                    )
                } compact: {
                    ShelfButton(title: "Settings", symbol: "ellipsis", action: toggleSettings)
                        .accessibilityIdentifier("openSettings")
                }
                .glassEffectID("settings", in: glassNamespace)
                .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82), value: showsTrash)
                .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82), value: showsDevelopment)
            }
        }
    }

    private func toggleSettings() {
        withAnimation(reduceMotion ? nil : .spring(response: settingsVisible ? 0.42 : 0.6, dampingFraction: settingsVisible ? 0.82 : 0.52)) {
            settingsVisible.toggle()
            if settingsVisible {
                showsTrash = false
                showsDevelopment = false
                pagesVisible = false
                if horizontalSizeClass == .compact { sidebarVisible = false }
            }
        }
    }

    private func moveToTrash(_ note: Note) {
        guard flushDrawing() else { return }
        let wasSelected = selectedNote?.id == note.id
        guard performEdit(notes: [note], { note.deletedAt = .now }) else { return }
        if wasSelected {
            selection = nil
            resetCanvas()
            if let next = notes.first(where: { $0.id != note.id && $0.deletedAt == nil }) { select(next) }
        }
    }

    private func restore(_ note: Note) {
        guard performEdit(notes: [note], {
            try NotebookEdits.prepare(note)
            note.deletedAt = nil
            note.updatedAt = .now
        }) else { return }
        resetCanvas()
        selection = note
    }

    private func select(_ note: Note) {
        if settingsVisible { toggleSettings() }
        guard note.id != selectedNote?.id, flushDrawing() else { return }
        guard performEdit(notes: [note], { try NotebookEdits.prepare(note) }) else { return }
        resetCanvas()
        selection = note
    }

    private func migrateTestLectureTitle() {
        guard !testPPLLectureTitleMigrated else { return }
        do {
            let all = try modelContext.fetch(FetchDescriptor<Note>())
            if let note = all.first(where: { $0.id.uuidString == pplTestNoteID }) {
                let title = Note.uniqueTitle(SampleLecture.programmingLanguages.title, occupied: Set(all.filter { $0.id != note.id }.map(\.title)))
                guard performEdit(notes: [note], { note.title = title }) else { return }
            }
            testPPLLectureTitleMigrated = true
        } catch { persistenceError = error.localizedDescription }
    }

    private func recreateTestNote(_ lecture: SampleLecture, selectCreated: Bool = true) {
        guard flushDrawing() else { return }
        do {
            let all = try modelContext.fetch(FetchDescriptor<Note>())
            let previousID = UserDefaults.standard.string(forKey: lecture.storageKey)
            // Identity, never a title match, scopes reset to this fixture only.
            let previous = all.first { $0.id.uuidString == previousID }
            let note = Note(title: Note.uniqueTitle(lecture.title, occupied: Set(all.map(\.title))))
            note.drawingData = lecture.drawing().dataRepresentation()
            note.pageLayoutVersion = 2
            guard performEdit(notes: previous.map { [$0] } ?? [], {
                if let previous, previous.deletedAt == nil { previous.deletedAt = .now }
                try note.setPages(lecture.pages.map { _ in NotebookPage() })
                modelContext.insert(note)
                try NotebookEdits.prepare(note)
            }) else { return }
            UserDefaults.standard.set(note.id.uuidString, forKey: lecture.storageKey)
            if selectCreated {
                resetCanvas()
                selection = note
                sidebarVisible = false
            }
        } catch { persistenceError = error.localizedDescription }
    }

    private func createNote(in folderID: UUID? = nil) {
        if settingsVisible { toggleSettings() }
        guard flushDrawing() else { return }
        let note = Note(title: availableTitle("Untitled"))
        note.folderID = folderID
        guard performEdit({
            modelContext.insert(note)
            try NotebookEdits.prepare(note)
        }) else { return }
        resetCanvas()
        selection = note
    }

    private func resetCanvas() {
        canvasRevision = UUID() // Invalidate writers before stopping UIKit animations.
        session.host?.stopAnimations()
        session = CanvasSession()
    }

    private func flushDrawing() -> Bool {
        guard !session.isDrawing else {
            persistenceError = "Finish the current Pencil stroke before changing pages or notes."
            return false
        }
        if let canvas = session.canvas, let note = selectedNote {
            note.drawingData = (session.host?.canonicalDrawing ?? MonochromeInk.canonical(canvas.drawing)).dataRepresentation()
        }
        return saveNow()
    }

    @discardableResult
    private func performEdit(notes affectedNotes: [Note] = [], _ action: () throws -> Void) -> Bool {
        guard saveNow() else { return false }
        do {
            try NotebookEdits.commit(in: modelContext, notes: affectedNotes, action)
            return true
        } catch {
            persistenceError = error.localizedDescription
            return false
        }
    }

    private func trashPage(_ page: NotebookPage, from note: Note) {
        trashPages([page.id], from: note)
    }

    @discardableResult
    private func trashPages(_ ids: Set<UUID>, from note: Note) -> Bool {
        guard flushDrawing(), performEdit(notes: [note], {
            try NotebookEdits.trashPages(ids, in: note, context: modelContext)
        }) else { return false }
        resetCanvas()
        return true
    }

    private func restorePage(_ page: TrashedPage) {
        guard flushDrawing() else { return }
        var restored: Note?
        guard performEdit(notes: (notes + trashedNotes).filter { $0.id == page.noteID }, { restored = try NotebookEdits.restore(page, context: modelContext) }) else { return }
        resetCanvas()
        selection = restored
    }

    private func addBlankPage(to note: Note) {
        guard performEdit(notes: [note], {
            try NotebookEdits.appendMetadata(to: note, count: note.pageCount + 1)
            note.currentPageIndex = note.pageCount - 1
            note.updatedAt = .now
        }) else { return }
        resetCanvas()
    }

    @discardableResult
    private func renameNote(_ note: Note, to title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = availableTitle(trimmed.isEmpty ? "Untitled" : trimmed, excluding: note.id)
        guard name != note.title else { return note.title }
        performEdit(notes: [note]) {
            note.title = name
            note.updatedAt = .now
        }
        return note.title
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

    private func organize(_ edit: () throws -> Void) -> Bool {
        guard flushDrawing() else { return false }
        do { try edit(); return true }
        catch { persistenceError = error.localizedDescription; return false }
    }

    private func refreshHandwriting() {
        var available = notes
        if let selectedNote, !available.contains(where: { $0.id == selectedNote.id }) { available.insert(selectedNote, at: 0) }
        handwriting.setPaused(scenePhase != .active || session.isDrawing || (session.host?.circleIntent.phase ?? .idle) != .idle)
        handwriting.update(notes: available, preferredID: selectedNote?.id)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(500)) }
            catch { return }
            saveNow()
        }
    }

    @discardableResult
    private func saveNow() -> Bool {
        saveTask?.cancel()
        saveTask = nil
        do {
            try modelContext.save()
            persistenceError = nil
            return true
        } catch {
            persistenceError = error.localizedDescription
            return false
        }
    }
}

#Preview("Blank canvas") {
    ContentView()
        .modelContainer(for: [Note.self, TrashedPage.self, NoteFolder.self, BulletinItem.self], inMemory: true)
}
