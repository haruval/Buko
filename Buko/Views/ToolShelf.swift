import SwiftUI

struct ToolShelf: View {
    @Bindable var session: CanvasSession

    var body: some View {
        HStack(spacing: 4) {
            ShelfButton(title: "Pen", symbol: "pencil.tip", selected: session.tool == .pen) {
                session.tool = .pen
            }
            .contextMenu {
                Toggle("Draw with finger", isOn: $session.allowsFingerDrawing)
            }
            .accessibilityHint("Touch and hold for pencil options.")
            ShelfButton(title: "Eraser", symbol: "eraser", selected: session.tool == .eraser) {
                session.tool = .eraser
            }
            Button { session.tool = .circle } label: {
                Circle().fill(.clear).frame(width: 20, height: 20)
                    .glassEffect(.clear.tint(CircleAIStyle.glassTint).interactive(), in: .circle)
                    .overlay { Circle().stroke(CircleAIStyle.green.opacity(session.tool == .circle ? 1 : 0.75), lineWidth: 1.5) }
                    .frame(width: 46, height: 46)
                    .background(session.tool == .circle ? CircleAIStyle.green.opacity(0.18) : .clear, in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Circle intent")
            .accessibilityIdentifier("circleIntentTool")
            .accessibilityAddTraits(session.tool == .circle ? [.isSelected] : [])
            .accessibilityHint("Draw a closed loop with one finger to interpret handwriting. With Pen selected, use two fingers.")
            Divider().frame(height: 22).padding(.horizontal, 6)
            ShelfButton(title: "Undo", symbol: "arrow.uturn.backward", action: session.undo)
                .disabled(!session.canUndo)
            ShelfButton(title: "Redo", symbol: "arrow.uturn.forward", action: session.redo)
                .disabled(!session.canRedo)
        }
        .padding(8)
        .bukoGlass(cornerRadius: 32)
    }
}
