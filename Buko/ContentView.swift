import PencilKit
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Query(filter: #Predicate<Note> { $0.deletedAt == nil }, sort: \Note.updatedAt, order: .reverse)
    private var notes: [Note]
    @Query(filter: #Predicate<Note> { $0.deletedAt != nil }, sort: \Note.deletedAt, order: .reverse)
    private var trashedNotes: [Note]
    @Query(sort: \TrashedPage.deletedAt, order: .reverse) private var trashedPages: [TrashedPage]
    @Query(sort: \NoteFolder.createdAt, order: .reverse) private var folders: [NoteFolder]
    @AppStorage("canvasGridEnabled") private var showsGrid = false
    @State private var showsDevelopment = false
    @State private var showsHandwritingPreview = false
    @State private var showsPersonalAlphabet = false
    @State private var lectureSourceNote: Note?
    @State private var canvasRevision = UUID()
    @State private var pagesVisible = false
    @State private var secondPagesVisible = false
    @State private var renamingPage: NotebookPage?
    @State private var renamePagePresented = false
    @State private var pageTitle = ""
    @State private var emptyTrashPresented = false
    @State private var emptyNoteIDs = Set<UUID>()
    @State private var emptyPageIDs = Set<UUID>()
    @State private var selection: Note?
    @State private var primaryPDF: LecturePDFDestination?
    @State private var secondContent: WorkspaceContent?
    @State private var secondSession = CanvasSession()
    @State private var secondRevision = UUID()
    @State private var secondFocused = false
    @State private var sourceDragging = false
    @State private var dropSide: Int?
    @State private var sourceOpenTask: Task<Void, Never>?
    private var activeNote: Note? { secondFocused ? (secondContent?.note ?? selectedNote) : selectedNote }
    private var activeSession: CanvasSession { secondFocused && secondContent?.note != nil ? secondSession : session }

    @State private var sidebarVisible = true
    @State private var settingsVisible = false
    private enum SettingsDestination { case handwriting, alphabet, emptyTrash }
    @State private var pendingSettingsDestination: SettingsDestination?
    @State private var showsTrash = false
    @State private var session = CanvasSession()
    @State private var handwriting = HandwritingPreparation()
    @State private var renamingNote: Note?
    @State private var renamePresented = false
    @State private var newTitle = ""
    @State private var cleanupError: String?
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
                guard let note = activeNote else { return }
                performEdit(notes: [note]) { try NotebookEdits.rename(page.id, in: note, to: pageTitle) }
                renamingPage = nil
            }
            .keyboardShortcut(.defaultAction)
        }
        .alert("Empty Trash?", isPresented: $emptyTrashPresented) {
            Button("Cancel", role: .cancel) { }
            Button("Delete permanently", role: .destructive) {
                let owners = Set(trashedPages.filter { emptyPageIDs.contains($0.id) }.map(\.noteID))
                if performEdit(notes: (notes + trashedNotes).filter { owners.contains($0.id) }, {
                    try NotebookEdits.emptyTrash(noteIDs: emptyNoteIDs, pageIDs: emptyPageIDs, context: modelContext)
                }) {
                    Task { await cleanRetainedData() }
                }
            }
        } message: {
            Text("Permanently delete \(emptyNoteIDs.count) notes and \(emptyPageIDs.count) pages from Trash? This cannot be undone.")
        }
        .alert("Data cleanup couldn’t finish", isPresented: Binding(
            get: { cleanupError != nil }, set: { if !$0 { cleanupError = nil } }
        )) {
            Button("Retry") { Task { await cleanRetainedData() } }
            Button("Dismiss", role: .cancel) { }
        } message: {
            Text("Some old autofill metadata or deleted-note files may remain in this app. Cleanup will retry on the next launch.\n\n" + (cleanupError ?? ""))
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
            await cleanRetainedData()
            normalizeDuplicateTitles()
            if selection == nil {
                if notes.isEmpty && trashedNotes.isEmpty { createNote() }
                else if let note = notes.first { select(note) }
            }
        }
        .onAppear { refreshHandwriting() }
        .onChange(of: handwritingStamps) { _, _ in refreshHandwriting() }
        .onChange(of: selectedNote?.id) { _, _ in refreshHandwriting() }
        .onChange(of: session.host?.circleIntent.phase) { _, _ in refreshHandwriting() }
        .onChange(of: secondSession.host?.circleIntent.phase) { _, _ in refreshHandwriting() }
        .onDisappear { handwriting.setPaused(true); sourceOpenTask?.cancel() }
        .sheet(isPresented: $showsHandwritingPreview) {
            HandwritingPreviewView(preparation: handwriting, noteID: activeNote?.id)
        }
        .fullScreenCover(isPresented: $showsPersonalAlphabet) {
            PersonalAlphabetView(preparation: handwriting, noteID: activeNote?.id)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                session.host?.circleIntent.cancel(); secondSession.host?.circleIntent.cancel(); saveNow()
            }
            refreshHandwriting()
        }
        .onChange(of: sidebarVisible) { _, _ in titleFocused = false }
        .onChange(of: settingsVisible) { _, _ in titleFocused = false }
        .onChange(of: pagesVisible) { _, _ in titleFocused = false }
        .onChange(of: secondSession.isDrawing) { _, _ in refreshHandwriting() }
        .onChange(of: session.isDrawing) { _, drawing in
            if drawing { titleFocused = false }
            refreshHandwriting()
        }
    }

    private var workspace: some View {
        GeometryReader { outer in
            let divisions = outer.reservedRegions(kind: .division, options: .includeInactive)
            let fold = divisions.first(where: \.isActive)?.frame
            let nativeChrome = horizontalSizeClass == .compact || fold != nil || secondContent != nil
            let nativeTools = nativeChrome || !divisions.isEmpty
            let layout = WorkspaceGeometry(size: outer.size, division: fold,
                compact: horizontalSizeClass == .compact || verticalSizeClass == .compact)
            let bookLibrary = fold != nil && !layout.vertical && layout.canSplit
            let separatedLibrary = fold != nil && layout.canSplit && (bookLibrary || secondContent == nil)
            let sideBySideNotes = !separatedLibrary && layout.canSplit && !layout.vertical && primaryPDF == nil && secondContent?.note != nil
            let progressNote = secondFocused && secondContent != nil ? secondContent?.note : (primaryPDF == nil ? selectedNote : nil)
            NavigationStack {
                WorkspaceToolbarAxis { verticalToolbar in
                    let settingsPopover = verticalToolbar
                    let combinesHistory = bookLibrary || (verticalToolbar && horizontalSizeClass == .compact)
                    GeometryReader { safeGeometry in
                        // Both children stay alive across display changes. The native
                        // overlay arrangement owns displacement and transition timing.
                        ArrangementView {
                            editorWorkspace(nativeChrome: nativeChrome, nativeTools: nativeTools,
                                            verticalToolbar: verticalToolbar, bookLibrary: bookLibrary,
                                            separatedLibrary: separatedLibrary, settingsPopover: settingsPopover,
                                            safeFrame: safeGeometry.frame(in: .global))
                                .overlayArrangementEdge(HorizontalEdge.trailing)
                                .overlayArrangementEdge(VerticalEdge.bottom)
                        } secondary: {
                            GeometryReader { libraryGeometry in
                                ZStack {
                                    (bookLibrary ? Color.black : Color("CanvasBackground"))
                                        .accessibilityIdentifier("bookLibraryBackground")
                                    GlassEffectContainer {
                                        libraryPanel(size: CGSize(width: max(0, libraryGeometry.size.width - 24),
                                                                  height: max(0, libraryGeometry.size.height - 24)),
                                                     expanded: true, canCollapse: false)
                                    }
                                    .environment(\.colorScheme, bookLibrary ? .dark : colorScheme)
                                    .padding(12)
                                    .accessibilityElement(children: separatedLibrary ? .contain : .ignore)
                                    .accessibilityIdentifier("bookLibraryPanel")
                                    .accessibilityHidden(!separatedLibrary)
                                }
                            }
                            .allowsHitTesting(separatedLibrary)
                            .accessibilityHidden(!separatedLibrary)
                        }
                        .arrangementViewStyle(.overlay.axes(secondContent == nil ? Axis.Set.horizontal.union(.vertical) : .horizontal))
                        .background(.black)
                        // The canvas owns the home-indicator area too. Leaving
                        // it outside the canvas exposes a paper-colored strip
                        // when the notebook scrolls or zooms over black.
                        .ignoresSafeArea(.container, edges: nativeTools ? .all : .vertical)
                    }
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        if nativeTools {
                            NotebookToolbar(session: activeSession, notes: toggleSidebar, settings: toggleSettings, settingsPresented: $settingsVisible,
                                settingsDismissed: finishSettingsPopoverDismissal,
                                showsNotes: nativeChrome && !separatedLibrary, showsSettings: nativeChrome || verticalToolbar,
                                settingsInDrawingBar: verticalToolbar, settingsPopoverEnabled: settingsPopover,
                                combinesHistory: combinesHistory,
                                sources: { showSources(activeNote) },
                                switchPane: secondContent == nil ? nil : { secondFocused.toggle() },
                                showsPageProgress: verticalToolbar && !sideBySideNotes && progressNote != nil) {
                                    if let note = progressNote {
                                        PageNavigator(note: note, session: activeSession, availableHeight: outer.size.height, circular: true,
                                            isExpanded: secondFocused ? $secondPagesVisible : $pagesVisible,
                                            rename: { page, _ in renamingPage = page; pageTitle = page.title; renamePagePresented = true },
                                            trash: { trashPage($0, from: note) }, trashSelection: { trashPages($0, from: note) },
                                            opening: { settingsVisible = false })
                                    }
                                } settingsContent: {
                                    let size = settingsPanelSize(in: outer.size, combinesHistory: combinesHistory)
                                    settingsPanel(combinesHistory: combinesHistory, presentedInPopover: true)
                                        .frame(width: size.width, height: size.height)
                                }
                        }
                    }
                    .toolbarVisibility(nativeChrome ? .automatic : .hidden, for: .navigationBar)
                    .toolbarBackgroundVisibility(.hidden, for: .navigationBar, .bottomBar)
                }
            }
        }
    }

    private func editorWorkspace(nativeChrome: Bool, nativeTools: Bool, verticalToolbar: Bool,
                                 bookLibrary: Bool, separatedLibrary: Bool, settingsPopover: Bool, safeFrame: CGRect) -> some View {
        GeometryReader { geometry in
            let activeFold = geometry.reservedRegions(kind: .division).first?.frame
            let paperFrame = geometry.frame(in: .global)
            let visibleSafeFrame = safeFrame.intersection(paperFrame)
            let controlsFrame = visibleSafeFrame.offsetBy(dx: -paperFrame.minX, dy: -paperFrame.minY)
            let editorFrame = CGRect(origin: CGPoint.zero, size: geometry.size)
            let layout = WorkspaceGeometry(size: geometry.size, division: separatedLibrary ? nil : activeFold,
                compact: bookLibrary || horizontalSizeClass == .compact || verticalSizeClass == .compact)
            let editorLayout = layout
            let showsBothPanes = secondContent != nil && editorLayout.canSplit
            let sideBySideNotes = showsBothPanes && !editorLayout.vertical && primaryPDF == nil && secondContent?.note != nil
            let firstFrame = showsBothPanes ? editorLayout.first : editorFrame
            let secondFrame = showsBothPanes ? editorLayout.second : editorFrame
            let panelFrame = (showsBothPanes ? (secondFocused ? secondFrame : firstFrame) : editorFrame).intersection(controlsFrame)
            let dropLayout = editorLayout
            ZStack(alignment: .topLeading) {
                Color("CanvasBackground").ignoresSafeArea()
                ArrangementView {
                    workspacePane(second: false, nativeTools: nativeTools, showsPageNavigator: !sideBySideNotes && !verticalToolbar, visible: !(secondContent != nil && !editorLayout.canSplit && secondFocused),
                                  controlInsets: controlInsets(for: firstFrame, within: controlsFrame))
                        .opacity(secondContent != nil && !editorLayout.canSplit && secondFocused ? 0 : 1)
                        .allowsHitTesting(!(secondContent != nil && !editorLayout.canSplit && secondFocused))
                        .accessibilityHidden(secondContent != nil && !editorLayout.canSplit && secondFocused)
                } secondary: {
                    workspacePane(second: true, nativeTools: nativeTools, showsPageNavigator: !sideBySideNotes && !verticalToolbar, visible: secondContent != nil && (editorLayout.canSplit || secondFocused),
                                  controlInsets: controlInsets(for: secondFrame, within: controlsFrame))
                        .opacity(secondContent != nil && (editorLayout.canSplit || secondFocused) ? 1 : 0)
                        .allowsHitTesting(secondContent != nil && (editorLayout.canSplit || secondFocused))
                        .accessibilityHidden(secondContent == nil || (!editorLayout.canSplit && !secondFocused))
                }
                .arrangementViewStyle(NotebookArrangementStyle(
                    geometry: editorLayout,
                    split: secondContent != nil, activePane: secondContent != nil && secondFocused ? 1 : 0))
                .frame(width: editorFrame.width, height: editorFrame.height)
                .clipped().contentShape(.rect)
                .offset(x: editorFrame.minX, y: editorFrame.minY)
                .onDrop(of: [.bukoNote, .bukoSource], delegate: WorkspaceDropDelegate(
                    geometry: dropLayout, side: $dropSide, note: openDroppedNote, source: openDroppedSource))

                if secondContent != nil && editorLayout.canSplit {
                    WorkspaceDivider(vertical: editorLayout.vertical,
                                     handleOffset: activeFold == nil ? 0 : -(editorLayout.vertical ? editorLayout.divider.height : editorLayout.divider.width) / 2 - 22,
                                     keepFirst: { closeSplit(keepingSecond: false) },
                                     keepSecond: { closeSplit(keepingSecond: true) })
                        .frame(width: editorLayout.divider.width, height: editorLayout.divider.height)
                        .position(x: editorFrame.minX + editorLayout.divider.midX, y: editorFrame.minY + editorLayout.divider.midY)
                }
                if let dropSide {
                    WorkspaceDropIndicator(title: dropLayout.vertical ? "Open above" : "Open on left", targeted: dropSide == 0)
                        .frame(width: dropLayout.first.width, height: dropLayout.first.height)
                        .position(x: editorFrame.minX + dropLayout.first.midX, y: editorFrame.minY + dropLayout.first.midY)
                    WorkspaceDropIndicator(title: dropLayout.vertical ? "Open below" : "Open on right", targeted: dropSide == 1)
                        .frame(width: dropLayout.second.width, height: dropLayout.second.height)
                        .position(x: editorFrame.minX + dropLayout.second.midX, y: editorFrame.minY + dropLayout.second.midY)
                }
                if settingsVisible && !settingsPopover {
                    Color.clear.contentShape(.rect)
                        .onTapGesture { toggleSettings() }.accessibilityIdentifier("dismissSettingsBackdrop")
                }
                floatingPanels(in: controlsFrame.size, nativeChrome: nativeChrome, showsLibrary: !separatedLibrary, showsTitle: verticalToolbar,
                               nativeSettings: nativeChrome || verticalToolbar, settingsPopover: settingsPopover,
                               combinesHistory: bookLibrary || (verticalToolbar && horizontalSizeClass == .compact),
                               libraryCanCollapse: !(verticalToolbar && horizontalSizeClass == .compact),
                               librarySize: !separatedLibrary && sidebarVisible && activeFold != nil && layout.canSplit ? layout.first.intersection(controlsFrame).size : nil)
                    .padding(.horizontal, nativeChrome ? 12 : 20)
                    .padding(.top, nativeChrome ? 8 : WorkspaceChrome.topPadding)
                    .padding(.bottom, 20)
                    .frame(width: controlsFrame.width, height: controlsFrame.height, alignment: .topLeading)
                    .position(x: controlsFrame.midX, y: controlsFrame.midY)
                if let note = lectureSourceNote {
                    LectureSourcesView(noteID: note.id,
                        close: { showSources(nil) }, dragging: { sourceDragging = $0 },
                        split: { openDroppedSource($0, 1) })
                        .frame(width: min(560, max(220, panelFrame.width - 24)),
                               height: max(160, panelFrame.height - 32))
                        .clipShape(.rect(cornerRadius: 32))
                        .shadow(color: .black.opacity(0.12), radius: 24, y: 8)
                        .position(x: panelFrame.midX, y: panelFrame.midY)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.15, anchor: .trailing).combined(with: .opacity))
                        .opacity(sourceDragging ? 0.08 : 1)
                        .allowsHitTesting(!sourceDragging)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("sourcesPanel")
                }
            }
        }
    }

    private func controlInsets(for pane: CGRect, within safeFrame: CGRect) -> EdgeInsets {
        EdgeInsets(top: max(0, safeFrame.minY - pane.minY),
                   leading: max(0, safeFrame.minX - pane.minX),
                   bottom: max(0, pane.maxY - safeFrame.maxY),
                   trailing: max(0, pane.maxX - safeFrame.maxX))
    }

    @ViewBuilder private func workspacePane(second: Bool, nativeTools: Bool, showsPageNavigator: Bool, visible: Bool, controlInsets: EdgeInsets = EdgeInsets(), foldHandleClearance: CGFloat = 0) -> some View {
        let note = second ? secondContent?.note : (primaryPDF == nil ? selectedNote : nil)
        let paneSession = second ? secondSession : session
        GeometryReader { geometry in
            let controlsHeight = max(0, geometry.size.height - controlInsets.top - controlInsets.bottom)
            ZStack {
                Color("CanvasBackground")
                if let note, note.pageCount > 0 {
                    drawingCanvas(for: note, revision: second ? secondRevision : canvasRevision, second: second, visible: visible)
                    PagePullIndicator(state: paneSession.pagePull).allowsHitTesting(false)
                } else if let note {
                    ContentUnavailableView {
                        Label("No pages", systemImage: "doc")
                    } description: { Text("Restore a page from Trash or start a new one.") }
                    actions: { Button("Add page") { addBlankPage(to: note) }.buttonStyle(.glass) }
                } else if second, case .pdf(let destination) = secondContent {
                    LecturePDFCard(destination: destination, isVisible: visible)
                        .padding(12).padding(.top, secondContent == nil ? 0 : 56).padding(controlInsets)
                } else if !second, let primaryPDF {
                    LecturePDFCard(destination: primaryPDF, isVisible: visible)
                        .padding(12).padding(.top, secondContent == nil ? 0 : 56).padding(controlInsets)
                }
            }
            .contentShape(.rect)
            .simultaneousGesture(TapGesture().onEnded { secondFocused = second })
            .overlay(alignment: .top) {
                if secondContent != nil {
                    HStack(spacing: 8) {
                        if second { Spacer(minLength: 0) }
                        Button { secondFocused = second } label: {
                            Text(note?.title ?? (second ? secondContent?.title : primaryPDF?.title) ?? "")
                                .font(.subheadline.weight(.semibold)).lineLimit(1)
                        }.buttonStyle(.glass)
                            .accessibilityIdentifier(second ? "secondPaneTitle" : "firstPaneTitle")
                        Button("Full screen", systemImage: "arrow.up.left.and.arrow.down.right") { closeSplit(keepingSecond: second) }
                            .labelStyle(.iconOnly).buttonStyle(.glass)
                            .accessibilityIdentifier(second ? "fullscreenSecondPane" : "fullscreenFirstPane")
                        if !second { Spacer(minLength: 0) }
                    }.padding(12).padding(.top, controlInsets.top)
                        .padding(.leading, controlInsets.leading).padding(.trailing, controlInsets.trailing)
                }
            }
            .overlay(alignment: .trailing) {
                if showsPageNavigator, let note {
                    if second {
                        PageNavigator(note: note, session: paneSession, availableHeight: controlsHeight,
                            isExpanded: $secondPagesVisible, rename: { page, _ in
                                secondFocused = true; renamingPage = page; pageTitle = page.title; renamePagePresented = true
                            }, trash: { trashPage($0, from: note) }, trashSelection: { trashPages($0, from: note) }, opening: { settingsVisible = false })
                            .padding(.trailing, 12 + controlInsets.trailing)
                            .padding(.top, controlInsets.top).padding(.bottom, controlInsets.bottom)
                    } else {
                        pageNavigation(for: note, height: controlsHeight)
                            .padding(.trailing, foldHandleClearance + controlInsets.trailing)
                            .padding(.top, controlInsets.top).padding(.bottom, controlInsets.bottom)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if !nativeTools, let note, note.pageCount > 0 {
                    ToolShelf(session: paneSession) { showSources(note) }
                        .padding(.bottom, 16 + controlInsets.bottom)
                }
            }
            .clipped()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(second ? "workspaceSecondPane" : "workspaceFirstPane")
        }
    }

    private func drawingCanvas(for note: Note, revision: UUID, second: Bool = false, visible: Bool = true) -> some View {
        let paneSession = second ? secondSession : session
        return NoteCanvas(note: note, session: paneSession, showsGrid: showsGrid,
                   onPageChange: { (count: Int, index: Int) in
            recordPosition(note: note, count: count, index: index, revision: revision, second: second)
        }, onDrawingChange: { (data: Data) in
            guard revision == (second ? secondRevision : canvasRevision) else { return }
            note.drawingData = data
            note.updatedAt = .now
            handwriting.invalidate(noteID: note.id)
            refreshHandwriting()
            scheduleSave()
        }, onWritingBegan: { secondFocused = second }, isVisible: visible, preparedHandwriting: { proposal in
            try await handwriting.preparedForPreview(proposal)
        }, onAutofillCommit: { before, after in
            guard revision == (second ? secondRevision : canvasRevision),
                  (second ? secondContent?.note?.id : selectedNote?.id) == note.id,
                  note.deletedAt == nil, !paneSession.isDrawing,
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
    }

    private func recordPosition(note: Note, count: Int, index: Int, revision: UUID, second: Bool = false) {
        guard revision == (second ? secondRevision : canvasRevision) else { return }
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
            secondFocused = false
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

    private func showSources(_ note: Note?) {
        withAnimation(panelAnimation(opening: note != nil)) {
            lectureSourceNote = note
        }
    }

    private func floatingPanels(in size: CGSize, nativeChrome: Bool = false, showsLibrary: Bool = true, showsTitle: Bool = false,
                                nativeSettings: Bool = false, settingsPopover: Bool = false, combinesHistory: Bool = false,
                                libraryCanCollapse: Bool = true, librarySize: CGSize? = nil) -> some View {
        let libraryExpanded = sidebarVisible || librarySize != nil
        return GlassEffectContainer(spacing: 20) {
            HStack(alignment: .top) {
                if showsLibrary && (!nativeChrome || libraryExpanded) {
                libraryPanel(size: CGSize(width: max(220, librarySize.map { $0.width - 24 } ?? min(max(280, size.width / 3), size.width - 84)), height: max(180, (librarySize?.height ?? size.height) - (nativeChrome ? 36 : 124))), expanded: libraryExpanded, canCollapse: libraryCanCollapse)
                }

                if (!nativeChrome || showsTitle), (!sidebarVisible || !showsLibrary),
                   (!nativeSettings || settingsPopover || !settingsVisible), secondContent == nil, primaryPDF == nil, let note = selectedNote {
                    NoteTitlePill(title: note.title, width: min(420, max(100, size.width - (nativeChrome ? 36 : 440))), focus: $titleFocused) { title in
                        renameNote(note, to: title)
                    }
                    .id(note.id)
                        .glassEffectID("note-title", in: glassNamespace)
                        .transition(.scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
                }

                Spacer(minLength: 12)

                if !settingsPopover && (!nativeSettings || settingsVisible) {
                ExpandingGlassPanel(
                    isExpanded: settingsVisible,
                    size: settingsPanelSize(in: size, combinesHistory: combinesHistory),
                    alignment: .topTrailing, anchor: .topTrailing
                ) {
                    settingsPanel(combinesHistory: combinesHistory)
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
    }


    private func settingsPanelSize(in size: CGSize, combinesHistory: Bool) -> CGSize {
        CGSize(width: min(showsTrash ? 300 : showsDevelopment ? 320 : 224, size.width - 104),
               height: showsTrash ? max(220, min(440, size.height - 120))
                   : showsDevelopment ? min(390, size.height - 120) : (combinesHistory ? 333 : 208))
    }

    private func settingsPanel(combinesHistory: Bool, presentedInPopover: Bool = false) -> some View {
        SettingsPanel(
            trashedNotes: trashedNotes, trashedPages: trashedPages, showsTrash: $showsTrash,
            showsDevelopment: $showsDevelopment, showsGrid: $showsGrid,
            previewHandwriting: {
                session.host?.circleIntent.cancel()
                presentSettingsDestination(.handwriting, afterPopover: presentedInPopover)
            }, writeAlphabet: {
                session.host?.circleIntent.cancel()
                presentSettingsDestination(.alphabet, afterPopover: presentedInPopover)
            }, scanHandwriting: {
                session.host?.circleIntent.cancel()
                saveNow()
                refreshHandwriting()
                handwriting.rebuild()
            }, handwritingStatus: handwriting.status, restore: restore, restorePage: restorePage,
            emptyTrash: {
                emptyNoteIDs = Set(trashedNotes.map(\.id))
                emptyPageIDs = Set(trashedPages.map(\.id))
                presentSettingsDestination(.emptyTrash, afterPopover: presentedInPopover)
            }, historySession: combinesHistory ? activeSession : nil
        )
    }

    private func presentSettingsDestination(_ destination: SettingsDestination, afterPopover: Bool) {
        if afterPopover {
            // Wait for native dismissal before presenting another modal from the
            // editor; otherwise it competes with the toolbar's popover presenter.
            pendingSettingsDestination = destination
            settingsVisible = false
        } else {
            switch destination {
            case .handwriting: showsHandwritingPreview = true
            case .alphabet: showsPersonalAlphabet = true
            case .emptyTrash: emptyTrashPresented = true
            }
        }
    }

    private func finishSettingsPopoverDismissal() {
        guard let destination = pendingSettingsDestination else { return }
        pendingSettingsDestination = nil
        presentSettingsDestination(destination, afterPopover: false)
    }

    private func libraryPanel(size: CGSize, expanded: Bool, canCollapse: Bool = true) -> some View {
        ExpandingGlassPanel(
            isExpanded: expanded,
            size: size,
            alignment: .topLeading, anchor: .topLeading,
            expandedBackingOpacity: 0.5
        ) {
            NotesSidebar(
                notes: notes, folders: folders, selectedID: activeNote?.id, canCollapse: canCollapse,
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
                }, openBeside: { note in openDroppedNote(NoteDragReference(id: note.id), 1) }, ungroup: { folder in
                    _ = organize { try LibraryOrganization.ungroup(folder, in: modelContext) }
                }
            )
        } compact: {
            ShelfButton(title: "Show notes", symbol: "sidebar.left", action: toggleSidebar)
                .accessibilityIdentifier("showNotes")
        }
        .glassEffectID("library", in: glassNamespace)
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
        if secondContent?.note?.id == note.id { closeSplit(keepingSecond: false) }
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
        if secondContent?.note?.id == note.id { secondFocused = true; sidebarVisible = false; return }
        secondFocused = false; primaryPDF = nil
        if horizontalSizeClass == .compact { sidebarVisible = false }
        if settingsVisible { toggleSettings() }
        guard note.id != selectedNote?.id, flushDrawing() else { return }
        guard performEdit(notes: [note], { try NotebookEdits.prepare(note) }) else { return }
        resetCanvas()
        selection = note
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
        primaryPDF = nil; secondFocused = false
        selection = note
    }

    private func resetSecondCanvas() {
        secondRevision = UUID()
        secondSession.host?.circleIntent.cancel()
        secondSession.host?.stopAnimations()
        secondSession = CanvasSession()
    }

    private func openDroppedNote(_ reference: NoteDragReference, _ side: Int) {
        guard let note = notes.first(where: { $0.id == reference.id }), flushDrawing() else { return }
        guard (primaryPDF != nil || note.id != selectedNote?.id), note.id != secondContent?.note?.id else {
            secondFocused = note.id == secondContent?.note?.id
            sidebarVisible = false; dropSide = nil; return
        }
        guard performEdit(notes: [note], { try NotebookEdits.prepare(note) }) else { return }
        place(.note(note), side: side)
    }

    private func openDroppedSource(_ reference: SourceDragReference, _ side: Int) {
        sourceOpenTask?.cancel()
        sourceOpenTask = Task { @MainActor in
            do {
                let documents = try await LectureLibrary.shared.documents(noteID: reference.noteID)
                guard let document = documents.first(where: { $0.id == reference.documentID }) else { return }
                let url = try await LectureLibrary.shared.pdfURL(noteID: reference.noteID, documentID: reference.documentID)
                try Task.checkCancellation()
                guard flushDrawing() else { return }
                place(.pdf(LecturePDFDestination(url: url, page: 1, title: document.title)), side: side)
            } catch is CancellationError { }
            catch { persistenceError = error.localizedDescription }
        }
    }

    private func place(_ content: WorkspaceContent, side: Int) {
        guard flushDrawing() else { return }
        if side == 0 {
            if secondContent == nil {
                secondContent = primaryPDF.map(WorkspaceContent.pdf) ?? selectedNote.map(WorkspaceContent.note)
                resetSecondCanvas()
            }
            resetCanvas()
            switch content {
            case .note(let note): selection = note; primaryPDF = nil
            case .pdf(let pdf): primaryPDF = pdf
            }
            secondFocused = false
        } else {
            resetSecondCanvas(); secondContent = content; secondFocused = true
        }
        sidebarVisible = false; showSources(nil); sourceDragging = false; dropSide = nil
    }

    private func closeSplit(keepingSecond: Bool) {
        guard flushDrawing() else { return }
        if keepingSecond, let secondContent {
            resetCanvas()
            switch secondContent {
            case .note(let note): selection = note; primaryPDF = nil
            case .pdf(let pdf): primaryPDF = pdf
            }
        }
        resetSecondCanvas(); secondContent = nil; secondFocused = false
    }

    private func resetCanvas() {
        canvasRevision = UUID() // Invalidate writers before stopping UIKit animations.
        session.host?.stopAnimations()
        session = CanvasSession()
    }

    private func flushDrawing() -> Bool {
        guard !session.isDrawing, !secondSession.isDrawing else {
            persistenceError = "Finish the current Pencil stroke before changing pages or notes."
            return false
        }
        if let canvas = session.canvas, let note = selectedNote {
            note.drawingData = (session.host?.canonicalDrawing ?? MonochromeInk.canonical(canvas.drawing)).dataRepresentation()
        }
        if let canvas = secondSession.canvas, let note = secondContent?.note {
            note.drawingData = (secondSession.host?.canonicalDrawing ?? MonochromeInk.canonical(canvas.drawing)).dataRepresentation()
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
        if secondContent?.note?.id == note.id { resetSecondCanvas() } else { resetCanvas() }
        return true
    }

    private func restorePage(_ page: TrashedPage) {
        guard flushDrawing() else { return }
        var restored: Note?
        guard performEdit(notes: (notes + trashedNotes).filter { $0.id == page.noteID }, { restored = try NotebookEdits.restore(page, context: modelContext) }) else { return }
        if let restored, secondContent?.note?.id == restored.id { resetSecondCanvas() }
        else { resetCanvas(); primaryPDF = nil; selection = restored }
    }

    private func addBlankPage(to note: Note) {
        guard performEdit(notes: [note], {
            try NotebookEdits.appendMetadata(to: note, count: note.pageCount + 1)
            note.currentPageIndex = note.pageCount - 1
            note.updatedAt = .now
        }) else { return }
        if secondContent?.note?.id == note.id { resetSecondCanvas() } else { resetCanvas() }
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
        handwriting.setPaused(scenePhase != .active || session.isDrawing || secondSession.isDrawing || (session.host?.circleIntent.phase ?? .idle) != .idle || (secondSession.host?.circleIntent.phase ?? .idle) != .idle)
        handwriting.update(notes: available, preferredID: selectedNote?.id)
    }

    private func cleanRetainedData() async {
        do {
            guard saveNow() else { throw NotebookEdits.EditError.unsavedWork }
            try NotebookEdits.minimizeAutofillHistory(in: modelContext)
            // Enumerate first, then read current owners. A note created while
            // enumeration awaits cannot be mistaken for an old orphan.
            let pdfIDs = try await LectureLibrary.shared.storedNoteIDs()
            let sampleIDs = try await handwriting.storedNoteIDs()
            let retained = try NotebookEdits.retainedNoteIDs(in: modelContext)
            let orphaned = pdfIDs.union(sampleIDs).subtracting(retained)
            try await LectureLibrary.shared.removeNotes(orphaned)
            try await handwriting.removeCaches(for: orphaned)
            cleanupError = nil
            refreshHandwriting()
        } catch { cleanupError = error.localizedDescription }
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
