import SwiftUI

struct NotesSidebar: View {
    let notes: [Note]
    let selectedID: UUID?
    let select: (Note) -> Void
    let create: () -> Void
    let hide: () -> Void
    let rename: (Note) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("buko")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .tracking(-1.5)
                Spacer()
                ShelfButton(title: "Hide notes", symbol: "sidebar.left", action: hide)
                    .accessibilityIdentifier("hideNotes")
            }
            .padding(.leading, 8)

            HStack {
                Text("YOUR NOTES")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.8)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(notes.count, format: .number)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(notes) { note in
                        Button { select(note) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 20, weight: .light))
                                    .foregroundStyle(note.id == selectedID ? Color.accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(note.title)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(2)
                                        .foregroundStyle(.primary)
                                    Text(note.updatedAt, format: .dateTime.month(.abbreviated).day())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if note.id == selectedID {
                                    Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(note.id == selectedID ? Color.accentColor.opacity(0.08) : .clear,
                                        in: .rect(cornerRadius: 18))
                            .contentShape(.rect(cornerRadius: 18))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(note.id == selectedID ? [.isSelected] : [])
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") { rename(note) }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)

            Button(action: create) {
                Label("New note", systemImage: "plus")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("newNote")
        }
        .padding(18)
        .frame(width: 272)
        .bukoGlass(cornerRadius: 32)
    }
}
