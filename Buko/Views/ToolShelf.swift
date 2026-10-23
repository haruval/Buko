import SwiftUI

struct ToolShelf: View {
    @Bindable var session: CanvasSession
    @AppStorage("showsGestureTestTools") private var showsGestureTestTools = true
    let openLectureSources: () -> Void

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
            if showsGestureTestTools {
                circleTool
                bandTool
            }
            ShelfButton(title: "Lecture sources", symbol: "books.vertical", action: openLectureSources)
                .accessibilityIdentifier("lectureSources")
                .accessibilityHint("Attach lecture PDFs for source-grounded autofill.")
            Divider().frame(height: 22).padding(.horizontal, 6)
            ShelfButton(title: "Undo", symbol: "arrow.uturn.backward", action: session.undo)
                .disabled(!session.canUndo)
            ShelfButton(title: "Redo", symbol: "arrow.uturn.forward", action: session.redo)
                .disabled(!session.canRedo)
        }
        .padding(8)
        .bukoGlass(cornerRadius: 32)
        .onChange(of: showsGestureTestTools, initial: true) { _, visible in
            if !visible, session.tool == .circle || session.tool == .band { session.tool = .pen }
        }
    }

    private var circleTool: some View {
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
    }

    private var bandTool: some View {
        Button { session.tool = .band } label: {
            RoundedRectangle(cornerRadius: 4).fill(.clear).frame(width: 20, height: 20)
                .glassEffect(.clear.tint(CircleAIStyle.glassTint).interactive(), in: .rect(cornerRadius: 4))
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(CircleAIStyle.green.opacity(session.tool == .band ? 1 : 0.75), lineWidth: 1.5)
                }
                .frame(width: 46, height: 46)
                .background(session.tool == .band ? CircleAIStyle.green.opacity(0.18) : .clear, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Band selection")
        .accessibilityIdentifier("bandSelectionTool")
        .accessibilityAddTraits(session.tool == .band ? [.isSelected] : [])
        .accessibilityHint("Drag diagonally with one finger to select a rectangle for the bulletin board. With Pen selected, sweep horizontally with two fingers.")
    }
}
