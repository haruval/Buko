import SwiftUI

struct SettingsPanel: View {
    let trashedNotes: [Note]
    let trashedPages: [TrashedPage]
    @Binding var showsTrash: Bool
    @Binding var showsGrid: Bool
    @Binding var infiniteCanvasEnabled: Bool
    let close: () -> Void
    let restore: (Note) -> Void
    let restorePage: (TrashedPage) -> Void
    let emptyTrash: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 4) {
                if showsTrash {
                    ShelfButton(title: "Back to settings", symbol: "chevron.left") { showsTrash = false }
                }
                Text(showsTrash ? "Trash" : "Settings")
                    .font(.title3.weight(.semibold))
                    .padding(.leading, showsTrash ? 0 : 8)
                Spacer(minLength: 0)
                ShelfButton(title: "Close settings", symbol: "xmark", action: close)
            }

            if showsTrash {
                if trashedNotes.isEmpty && trashedPages.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "trash")
                            .font(.system(size: 32, weight: .light))
                        Text("Trash is empty").font(.subheadline.weight(.medium))
                        Text("Deleted notes and pages will appear here.")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(trashedNotes) { note in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(note.title)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(2)
                                    Button { restore(note) } label: {
                                        Label("Restore", systemImage: "arrow.uturn.backward")
                                            .font(.caption.weight(.medium))
                                            .padding(.horizontal, 14)
                                            .frame(minHeight: 44)
                                    }
                                    .buttonStyle(.plain)
                                    .bukoGlass(cornerRadius: 22, interactive: true)
                                    .accessibilityLabel("Restore \(note.title)")
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                            }
                            ForEach(trashedPages) { page in
                                VStack(alignment: .leading, spacing: 10) {
                                    Label(page.label, systemImage: "doc")
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(2)
                                    Button { restorePage(page) } label: {
                                        Label("Restore", systemImage: "arrow.uturn.backward")
                                            .font(.caption.weight(.medium))
                                            .padding(.horizontal, 14).frame(minHeight: 44)
                                    }
                                    .buttonStyle(.plain)
                                    .bukoGlass(cornerRadius: 22, interactive: true)
                                    .accessibilityLabel("Restore \(page.label)")
                                    .accessibilityIdentifier("restorePage")
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    Button(role: .destructive, action: emptyTrash) {
                        Label("Empty Trash", systemImage: "trash.slash")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .bukoGlass(interactive: true)
                    .accessibilityIdentifier("emptyTrash")
                }
            } else {
                Toggle(isOn: $showsGrid) {
                    Label("Grid lines", systemImage: "square.grid.3x3")
                        .font(.subheadline)
                }
                .padding(.horizontal, 14)
                .accessibilityIdentifier("gridLines")
                Toggle(isOn: $infiniteCanvasEnabled) {
                    Text("Enable infinite canvas (experimental)")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .accessibilityIdentifier("infiniteCanvas")
                Button { showsTrash = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "trash")
                        Text("Trash")
                        Spacer()
                        Text(trashedNotes.count + trashedPages.count, format: .number).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                    .font(.subheadline)
                    .padding(14)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("openTrash")
                Spacer(minLength: 0)
            }
        }
        .padding(18)
    }
}
