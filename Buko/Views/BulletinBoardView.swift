import SwiftData
import SwiftUI

struct BulletinBoardView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BulletinItem.capturedAt, order: .reverse) private var items: [BulletinItem]
    let openSource: (BulletinItem) -> String?
    @State private var error: String?
    @State private var showsCompleted = false

    private var visibleItems: [BulletinItem] {
        items.filter { showsCompleted || $0.completedAt == nil }.sorted {
            if ($0.completedAt == nil) != ($1.completedAt == nil) { return $0.completedAt == nil }
            if $0.dueDate != $1.dueDate { return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            return $0.capturedAt > $1.capturedAt
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if visibleItems.isEmpty {
                    ContentUnavailableView {
                        Label(items.isEmpty ? "Your bulletin board" : "All caught up", systemImage: "rectangle.grid.1x2")
                    } description: {
                        Text("Place two fingers above and below a few handwritten lines, then sweep horizontally to collect important information and action items.")
                    }
                } else {
                    ScrollView {
                        GlassEffectContainer(spacing: 16) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], alignment: .leading, spacing: 16) {
                                ForEach(visibleItems) { item in card(item) }
                            }.padding(24)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color("CanvasBackground"))
            .navigationTitle("Bulletin board")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(showsCompleted ? "Hide completed" : "Show completed") { showsCompleted.toggle() }
                        .accessibilityAddTraits(showsCompleted ? [.isSelected] : [])
                        .accessibilityIdentifier("showCompletedBulletinItems")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("closeBulletinBoard")
                }
            }
            .alert("Couldn’t complete that change", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { }
            } message: { Text(error ?? "") }
        }
    }

    private func card(_ item: BulletinItem) -> some View {
        let kind = BulletinKind(rawValue: item.kind) ?? .information
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                if kind == .action {
                    Button { toggle(item) } label: {
                        Image(systemName: item.completedAt == nil ? "circle" : "checkmark.circle.fill")
                            .font(.title2).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.completedAt == nil ? "Complete \(item.title)" : "Mark \(item.title) incomplete")
                    .accessibilityIdentifier("completeBulletinItem")
                } else { Image(systemName: kind.symbol).font(.title3).padding(.top, 3).accessibilityHidden(true) }
                Text(item.title).font(.headline).strikethrough(item.completedAt != nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let date = item.dueDate {
                Text(date, format: dateFormat(item)).font(.subheadline.weight(.medium)).foregroundStyle(Color.accentColor)
            }
            Text(item.sourceText).font(.callout).foregroundStyle(.secondary).lineLimit(6)
            Button {
                if let problem = openSource(item) { error = problem } else { dismiss() }
            } label: {
                Label("\(item.noteTitle) · Page \(item.pageIndex + 1)", systemImage: "arrow.up.right")
                    .font(.caption.weight(.medium)).lineLimit(2).frame(minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain).accessibilityIdentifier("openBulletinSource")
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .bukoGlass(cornerRadius: 28)
        .contextMenu {
            Button("Remove from board", systemImage: "trash", role: .destructive) {
                do { try NotebookEdits.commit(in: context) { context.delete(item) } }
                catch { self.error = error.localizedDescription }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bulletinCard")
    }

    private func dateFormat(_ item: BulletinItem) -> Date.FormatStyle {
        var style = Date.FormatStyle(date: .abbreviated, time: item.dateHasTime ? .shortened : .omitted)
        style.timeZone = TimeZone(identifier: item.timeZoneID) ?? .current
        return style
    }

    private func toggle(_ item: BulletinItem) {
        let previous = item.completedAt
        do { try NotebookEdits.commit(in: context) { item.completedAt = previous == nil ? .now : nil } }
        catch { item.completedAt = previous; self.error = error.localizedDescription }
    }
}
