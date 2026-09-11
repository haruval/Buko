import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @State private var selectedID: UUID?
    @State private var sidebarVisible = true
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
                Color(uiColor: .systemBackground).ignoresSafeArea()
                if let note = selectedNote {
                    NoteCanvas(note: note, session: session) { data in
                        note.drawingData = data
                        note.updatedAt = .now
                        scheduleSave()
                    }
                    .id(note.id)
                    .ignoresSafeArea()
                }

                GlassEffectContainer(spacing: 20) {
                    if sidebarVisible {
                        NotesSidebar(
                            notes: notes, selectedID: selectedNote?.id,
                            select: select, create: createNote, hide: toggleSidebar,
                            rename: { note in
                                newTitle = note.title
                                renamingNote = note
                            }
                        )
                        .frame(height: max(240, min(640, geometry.size.height - 120)))
                        .glassEffectID("library", in: glassNamespace)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    } else {
                        Button(action: toggleSidebar) {
                            Image(systemName: "sidebar.left")
                                .font(.system(size: 20))
                                .frame(width: 52, height: 52)
                        }
                        .buttonStyle(.glass)
                        .glassEffectID("library", in: glassNamespace)
                        .accessibilityLabel("Show notes")
                        .accessibilityIdentifier("showNotes")
                    }
                }
                .padding(20)
            }
            .overlay(alignment: .bottom) {
                ToolShelf(session: session)
                    .padding(.bottom, 16)
            }
        }
        .tint(.accentColor)
        .task {
            if notes.isEmpty { createNote() }
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
        }
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
