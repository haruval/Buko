import SwiftUI

struct SettingsPanel: View {
    let trashedNotes: [Note]
    let trashedPages: [TrashedPage]
    @Binding var showsTrash: Bool
    @Binding var showsDevelopment: Bool
    @Binding var showsGrid: Bool
    @AppStorage("detailedAutofillPreview") private var detailedPreview = false
    @AppStorage("showsGestureTestTools") private var showsGestureTestTools = false
    let writeAlphabet: () -> Void
    let scanHandwriting: () -> Void
    let handwritingStatus: HandwritingPreparationStatus
    let restore: (Note) -> Void
    let restorePage: (TrashedPage) -> Void
    let emptyTrash: () -> Void
    var historySession: CanvasSession? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsTrash || showsDevelopment {
                HStack(spacing: 4) {
                    ShelfButton(title: "Back to settings", symbol: "chevron.left") {
                        showsTrash = false; showsDevelopment = false
                    }
                    Text(showsTrash ? "Trash" : "Dev").font(.headline)
                    Spacer()
                }
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
            } else if showsDevelopment {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Circle test tool", isOn: $showsGestureTestTools)
                            .font(.subheadline)
                            .padding(.horizontal, 8).frame(minHeight: 44)
                            .accessibilityIdentifier("showGestureTestTools")
                        Text("Show circle tool in the toolbar")
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle("Detailed preview", isOn: $detailedPreview)
                            .font(.subheadline)
                            .padding(.horizontal, 8).frame(minHeight: 44)
                            .accessibilityIdentifier("detailedPreview")
                        Text("Show live pipeline stages, prompt inputs and retrieved evidence in autofill previews.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button(action: writeAlphabet) {
                            Label("Write your alphabet", systemImage: "pencil.line")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }.buttonStyle(.glass).accessibilityIdentifier("writeAlphabet")
                        Button(action: scanHandwriting) {
                            Label(handwritingStatus.isRebuilding ? "Scanning handwriting…" : "Scan handwriting now", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }.buttonStyle(.glass).disabled(handwritingStatus.isRebuilding)
                            .accessibilityIdentifier("scanHandwritingNow")
                        Text(handwritingStatus.message).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                if let historySession {
                    Button(action: historySession.undo) {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.horizontal, 14)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain).disabled(!historySession.canUndo)
                    .accessibilityIdentifier("undo")
                    Button(action: historySession.redo) {
                        Label("Redo", systemImage: "arrow.uturn.forward")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.horizontal, 14)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain).disabled(!historySession.canRedo)
                    .accessibilityIdentifier("redo")
                    Divider()
                }
                Toggle(isOn: $showsGrid) {
                    Label("Grid", systemImage: "square.grid.3x3")
                        .font(.subheadline)
                }
                .toggleStyle(.switch)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .accessibilityIdentifier("gridLines")
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
                Button { showsDevelopment = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "hammer")
                        Text("Dev")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }.font(.subheadline).padding(14).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("openDevelopment")
                Spacer(minLength: 0)
            }
        }
        .labelStyle(.titleAndIcon)
        .padding(18)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settingsPanel")
    }
}
