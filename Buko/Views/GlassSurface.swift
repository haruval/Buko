import SwiftUI

extension View {
    /// Native clear glass lets the note stay legible beneath the floating chrome.
    func bukoGlass(cornerRadius: CGFloat = 28) -> some View {
        glassEffect(.clear, in: .rect(cornerRadius: cornerRadius))
    }
}

struct ShelfButton: View {
    let title: String
    let symbol: String
    var selected = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(selected ? Color.accentColor : .primary)
                .frame(width: 46, height: 46)
                .background(selected ? Color.accentColor.opacity(0.12) : .clear, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .help(title)
    }
}
