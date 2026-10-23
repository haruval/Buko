import SwiftUI

struct BulletinExtractionView: View {
    @Bindable var capture: BulletinCapture
    let save: ([BulletinDraft]) throws -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if capture.busy {
                    VStack(spacing: 18) {
                        ProgressView()
                        Text(capture.stage).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if capture.drafts.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing added yet", systemImage: "rectangle.grid.1x2")
                    } description: {
                        Text(capture.message ?? "Select a few written lines with a two-finger horizontal sweep.")
                    } actions: { Button("Try again") { capture.start() }.buttonStyle(.glass) }
                } else {
                    Form {
                        Section {
                            Text("Review the items and dates before adding them.").foregroundStyle(.secondary)
                            if let message = capture.message { Text(message).foregroundStyle(.red) }
                        }
                        ForEach($capture.drafts) { $draft in
                            Section {
                                Toggle("Add this item", isOn: $draft.included)
                                TextField("Title", text: $draft.title, axis: .vertical)
                                    .accessibilityIdentifier("bulletinDraftTitle")
                                Picker("Type", selection: $draft.kind) {
                                    ForEach(BulletinKind.allCases, id: \.self) { Text($0.label).tag($0) }
                                }
                                if let date = draft.date {
                                    DatePicker("Date", selection: Binding(get: { draft.date ?? date }, set: { draft.date = $0 }),
                                               displayedComponents: draft.dateHasTime ? [.date, .hourAndMinute] : [.date])
                                    Button("Remove date") { draft.date = nil; draft.dateHasTime = false }
                                }
                                Text(draft.quote).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                        Section("Source") {
                            Text("\(capture.source.noteTitle) · Page \(capture.source.pageIndex + 1)")
                            Text(capture.source.timeZoneID).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Add to bulletin board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { capture.cancel(); dismiss() }.accessibilityIdentifier("cancelBulletinExtraction")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        do { try save(capture.drafts.filter(\.included)); dismiss() }
                        catch { capture.message = error.localizedDescription }
                    }
                    .disabled(capture.busy || !capture.drafts.contains { $0.included && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                              || capture.drafts.contains { $0.included && ($0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.title.count > 240) })
                    .accessibilityIdentifier("addBulletinItems")
                }
            }
        }
        .environment(\.timeZone, TimeZone(identifier: capture.source.timeZoneID) ?? .current)
        .onAppear { capture.start() }
        .onDisappear { capture.cancel() }
    }
}
