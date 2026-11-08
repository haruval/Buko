import SwiftUI

enum WorkspaceContent {
    case note(Note)
    case pdf(LecturePDFDestination)

    var note: Note? { if case .note(let note) = self { note } else { nil } }
    var title: String {
        switch self { case .note(let note): note.title; case .pdf(let pdf): pdf.title }
    }
}

/// An ArrangementView style retains both editors during resize/collapse. The
/// custom layout supplies the requested equal halves and detented divider, while
/// using Apple's reserved regions for book and tabletop poses.
struct NotebookArrangementStyle: ArrangementViewStyle {
    let geometry: WorkspaceGeometry
    let split: Bool
    let activePane: Int
    func makeBody(configuration: Configuration) -> some View {
        NotebookPaneLayout(geometry: geometry, split: split, activePane: activePane) {
            configuration.primary
            configuration.secondary
        }
    }
}

private struct NotebookPaneLayout: Layout {
    let geometry: WorkspaceGeometry
    let split: Bool
    let activePane: Int
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, view) in subviews.enumerated() {
            let frame = split && geometry.canSplit ? (index == 0 ? geometry.first : geometry.second)
                : CGRect(origin: index == activePane ? .zero : CGPoint(x: bounds.width + 100, y: 0), size: bounds.size)
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                       anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }
}

struct WorkspaceDivider: View {
    let vertical: Bool
    var handleOffset: CGFloat = 0
    let keepFirst: () -> Void
    let keepSecond: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var translation: CGFloat = 0
    var body: some View {
        Color.black.allowsHitTesting(false)
            .overlay {
                Capsule().fill(handleOffset == 0 ? Color.white.opacity(0.8) : Color.primary)
                    .frame(width: vertical ? 40 : 5, height: vertical ? 5 : 40)
                    .offset(x: vertical ? 0 : handleOffset + max(-16, min(16, translation)),
                            y: vertical ? handleOffset + max(-16, min(16, translation)) : 0)
            }
            .overlay {
                Color.clear.frame(width: 44, height: 44)
                    .contentShape(.rect)
                    .gesture(DragGesture(minimumDistance: 8)
                        .updating($translation) { value, state, _ in state = vertical ? value.translation.height : value.translation.width }
                        .onEnded { value in
                            let travel = vertical ? value.translation.height : value.translation.width
                            let projected = vertical ? value.predictedEndTranslation.height : value.predictedEndTranslation.width
                            guard abs(travel) > 36 || abs(projected) > 110 else { return }
                            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.9)) {
                                if travel > 0 { keepFirst() } else { keepSecond() }
                            }
                        })
                    .offset(x: vertical ? 0 : handleOffset, y: vertical ? handleOffset : 0)
                    .accessibilityElement().accessibilityLabel("Split divider")
            .accessibilityHint("Swipe toward a pane to close it")
            .accessibilityIdentifier("workspaceDivider")
            .accessibilityAction(named: "Keep first pane", keepFirst)
            .accessibilityAction(named: "Keep second pane", keepSecond)
            }
    }
}

/// Semantic native toolbar placements automatically move to Duo's outer edge.
struct NotebookToolbar<PageProgress: View, SettingsContent: View>: ToolbarContent {
    @Bindable var session: CanvasSession
    let notes: () -> Void
    let settings: () -> Void
    @Binding var settingsPresented: Bool
    var settingsDismissed: () -> Void = {}
    var showsNotes = true
    var showsSettings = true
    var showsDrawingTools = true
    var settingsInDrawingBar = false
    var settingsPopoverEnabled = false
    var usesClearCoverControls = false
    var combinesHistory = false
    let sources: () -> Void
    var switchPane: (() -> Void)? = nil
    var showsPageProgress = false
    @ViewBuilder var pageProgress: () -> PageProgress
    @ViewBuilder var settingsContent: () -> SettingsContent
    @AppStorage("showsGestureTestTools") private var showsCircle = false
    var body: some ToolbarContent {
        if showsNotes {
            ToolbarItem(placement: .navigation) {
                coverControl {
                    Button("Notes", systemImage: "sidebar.left", action: notes)
                        .accessibilityIdentifier("showNotes")
                }
            }
            .axisBehavior(usesClearCoverControls ? .verticalPreferred : .automatic)
            .sharedBackgroundVisibility(usesClearCoverControls ? .hidden : .automatic)
        }
        if showsSettings && !settingsInDrawingBar {
            ToolbarItem(placement: .primaryAction) {
                Button("Settings", systemImage: "ellipsis", action: settings).accessibilityIdentifier("openSettings")
            }
        }
        if showsPageProgress {
            ToolbarItem(placement: .bottomBar) { pageProgress() }
                .axisBehavior(.verticalPreferred)
                .sharedBackgroundVisibility(.hidden)
                .visibilityPriority(.high)
            ToolbarSpacer(.fixed, placement: .bottomBar)
        }
        if showsSettings && settingsInDrawingBar {
            ToolbarItem(placement: .bottomBar) {
                coverControl {
                    Button("Settings", systemImage: "ellipsis", action: settings)
                        .accessibilityIdentifier("openSettings")
                }
                .popover(isPresented: Binding(
                    get: { settingsPopoverEnabled && settingsPresented },
                    set: { settingsPresented = $0 }
                ), attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
                    settingsContent()
                        .presentationCompactAdaptation(.popover)
                        .onDisappear(perform: settingsDismissed)
                }
            }
            .axisBehavior(.verticalPreferred)
            .sharedBackgroundVisibility(usesClearCoverControls ? .hidden : .automatic)
            .visibilityPriority(.high)
            ToolbarSpacer(.fixed, placement: .bottomBar)
        }
        if showsDrawingTools {
            if usesClearCoverControls {
                ToolbarItem(placement: .bottomBar) {
                    VStack(spacing: 0) {
                        drawingButtons
                        sourceAndHistoryButtons
                    }
                    .buttonStyle(CoverToolButtonStyle())
                    .glassEffect(.clear, in: .capsule)
                }
                .axisBehavior(.verticalPreferred)
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItemGroup(placement: .bottomBar) { drawingButtons }
                ToolbarItemGroup(placement: .bottomBar) { sourceAndHistoryButtons }
            }
        }
        if let switchPane {
            ToolbarItem(placement: .topBarPinnedTrailing) {
                Button("Switch pane", systemImage: "rectangle.on.rectangle", action: switchPane)
                    .accessibilityIdentifier("switchWorkspacePane")
            }
        }
    }

    @ViewBuilder private func coverControl<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if usesClearCoverControls {
            content()
                .buttonStyle(CoverToolButtonStyle())
                .glassEffect(.clear.interactive(), in: .circle)
        } else {
            content()
        }
    }

    @ViewBuilder private var drawingButtons: some View {
        Button("Pen", systemImage: "pencil.tip") { session.tool = .pen }
            .tint(session.tool == .pen ? .accentColor : .primary)
            .contextMenu { Toggle("Draw with finger", isOn: $session.allowsFingerDrawing) }
        Button("Eraser", systemImage: "eraser") { session.tool = .eraser }
            .tint(session.tool == .eraser ? .accentColor : .primary)
        if showsCircle {
            // The native vertical toolbar requires an image label; hosting
            // a SwiftUI glass view here moves the item to the bottom bar.
            Button("Circle intent", image: .circleJelly) { session.tool = .circle }
                .tint(CircleAIStyle.green)
                .accessibilityLabel("Circle intent")
                .accessibilityIdentifier("circleIntentTool")
                .accessibilityAddTraits(session.tool == .circle ? [.isSelected] : [])
        }
    }

    @ViewBuilder private var sourceAndHistoryButtons: some View {
        Button("Sources", systemImage: "books.vertical", action: sources).accessibilityIdentifier("lectureSources")
        if !combinesHistory {
            Button("Undo", systemImage: "arrow.uturn.backward", action: session.undo).disabled(!session.canUndo)
            Button("Redo", systemImage: "arrow.uturn.forward", action: session.redo).disabled(!session.canRedo)
        }
    }
}

private struct CoverToolButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(.tint)
            .frame(width: 44, height: 44)
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}

/// Read the navigation container's bar axis inside its environment, so the
/// compact progress control follows native toolbar adaptation on both displays.
struct WorkspaceToolbarAxis<Content: View>: View {
    @Environment(\.toolbarVerticalEdge) private var verticalEdge
    @ViewBuilder var content: (Bool) -> Content
    var body: some View { content(verticalEdge != nil) }
}
