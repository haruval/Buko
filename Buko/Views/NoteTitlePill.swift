import SwiftUI

/// Edit in the same glass surface; keep a draft until Return or focus leaves.
struct NoteTitlePill: View {
    let title: String
    let width: CGFloat
    let commit: (String) -> String
    @State private var draft: String
    var focus: FocusState<Bool>.Binding
    @Environment(\.scenePhase) private var scenePhase

    init(title: String, width: CGFloat, focus: FocusState<Bool>.Binding, commit: @escaping (String) -> String) {
        self.title = title
        self.width = width
        self.commit = commit
        self.focus = focus
        _draft = State(initialValue: title)
    }

    var body: some View {
        TextField("Note title", text: $draft)
            .textFieldStyle(.plain)
            .font(.headline)
            .multilineTextAlignment(.center)
            .submitLabel(.done)
            .focused(focus)
            .padding(.horizontal, 20)
            .frame(width: width, height: 52)
            .bukoGlass(cornerRadius: 26, interactive: true)
            .contentShape(.capsule)
            .simultaneousGesture(TapGesture().onEnded { focus.wrappedValue = true })
            .accessibilityIdentifier("currentNoteTitle")
            .onSubmit { saveDraft(); focus.wrappedValue = false }
            .onChange(of: focus.wrappedValue) { _, value in if !value { saveDraft() } }
            .onChange(of: title) { _, value in if !focus.wrappedValue { draft = value } }
            .onChange(of: scenePhase) { _, value in if value != .active { saveDraft() } }
            .onDisappear { saveDraft() }
    }

    private func saveDraft() {
        guard draft != title else { return }
        draft = commit(draft)
    }
}
