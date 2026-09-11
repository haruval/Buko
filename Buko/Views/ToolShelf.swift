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
