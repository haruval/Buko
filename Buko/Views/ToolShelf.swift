import SwiftUI

struct ToolShelf: View {
    @Bindable var session: CanvasSession

    var body: some View {
        HStack(spacing: 4) {
            ShelfButton(title: "Pen", symbol: "pencil.tip", selected: session.tool == .pen) {
                session.tool = .pen
            }
            ShelfButton(title: "Eraser", symbol: "eraser", selected: session.tool == .eraser) {
                session.tool = .eraser
            }
            Divider().frame(height: 22).padding(.horizontal, 6)
            ShelfButton(title: "Undo", symbol: "arrow.uturn.backward", action: session.undo)
                .disabled(!session.canUndo)
            ShelfButton(title: "Redo", symbol: "arrow.uturn.forward", action: session.redo)
                .disabled(!session.canRedo)
            Menu {
                Toggle("Draw with finger", isOn: $session.allowsFingerDrawing)
            } label: {
                Image(systemName: session.allowsFingerDrawing ? "hand.draw" : "ellipsis")
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: 46, height: 46)
                    .contentShape(.circle)
            }
            .accessibilityLabel("Canvas options")
        }
        .padding(8)
        .bukoGlass(cornerRadius: 32)
    }
}
