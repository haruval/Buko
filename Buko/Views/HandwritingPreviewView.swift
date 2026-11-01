import PencilKit
import SwiftUI

struct HandwritingPreviewView: View {
    let preparation: HandwritingPreparation
    let noteID: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var tiles: [HandwritingPreviewTile] = []
    @State private var showsWords = false
    private let renderer = HandwritingPreviewRenderer()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(preparation.status.message).font(.subheadline)
                            .accessibilityIdentifier("handwritingPreparationStatus")
                        Text("Notes take priority, then your saved alphabet. Remaining letters use Buko’s handwriting font. Scan notes now refreshes samples from every active note.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button(action: preparation.rebuild) {
                            Label(preparation.status.isRebuilding ? "Scanning notes…" : "Scan notes now", systemImage: "arrow.clockwise")
                                .frame(minHeight: 36)
                        }.buttonStyle(.glass).disabled(preparation.status.isRebuilding)
                            .accessibilityIdentifier("rebuildHandwritingCache")
                    }
                    Picker("Samples", selection: $showsWords) {
                        Text("Letters & symbols").tag(false)
                        Text("Prepared words").tag(true)
                    }.pickerStyle(.segmented)
                    if showsWords {
                        let words = tiles.filter { $0.key.count > 1 }
                        if words.isEmpty {
                            Text("No complete word samples are ready yet.").foregroundStyle(.secondary)
                        } else {
                            sampleGrid(words, minimum: 140)
                        }
                        Text("A prepared word can preserve connected handwriting even when its individual letters use the fallback.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        let letters = tiles.filter { $0.key.count == 1 }
                        Text("\(letters.filter(\.prepared).count) prepared · \(letters.filter { !$0.prepared }.count) fallback")
                            .font(.subheadline.weight(.medium)).accessibilityIdentifier("handwritingCoverage")
                        sampleGrid(letters, minimum: 76)
                    }
                }.padding(24)
            }
            .navigationTitle("Handwriting samples").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly).buttonBorderShape(.circle)
                        .accessibilityIdentifier("closeHandwritingPreview")
                }
            }
        }
        .task(id: preparation.status.revision) {
            let samples = preparation.inspection(preferredID: noteID)
            let result = await renderer.render(samples)
            guard !Task.isCancelled else { return }
            tiles = result
        }
    }

    private func sampleGrid(_ values: [HandwritingPreviewTile], minimum: CGFloat) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: 10)], spacing: 10) {
            ForEach(values) { tile in
                VStack(spacing: 6) {
                    Text(tile.key).font(.caption.weight(.semibold)).lineLimit(1)
                    if let image = UIImage(data: tile.image) {
                        Image(uiImage: image).renderingMode(.template).resizable().scaledToFit()
                            .frame(height: 52).frame(maxWidth: .infinity)
                            .foregroundStyle(tile.prepared ? Color.primary : Color.secondary)
                    } else { Color.clear.frame(height: 52) }
                    Text(tile.prepared ? "Prepared" : "Fallback").font(.caption2)
                        .foregroundStyle(tile.prepared ? Color.green : Color.secondary)
                }
                .padding(8).background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(tile.key), \(tile.prepared ? "prepared from " + tile.source : "fallback font")")
                .accessibilityIdentifier("handwritingSample.\(tile.key)")
            }
        }
    }
}

private nonisolated struct HandwritingPreviewTile: Identifiable, Sendable {
    var id: String { key }
    let key: String
    let prepared: Bool
    let source: String
    let image: Data
}

private actor HandwritingPreviewRenderer {
    func render(_ samples: [String: HandwritingInspectionSample]) -> [HandwritingPreviewTile] {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,:;!?+-=()".map(String.init))
        let extra = samples.keys.filter { !alphabet.contains($0) }.sorted()
        return (alphabet + extra).compactMap { key in
            guard !Task.isCancelled, let sample = samples[key]?.sample ?? HandwrittenFont.sample(key),
                  let drawing = try? PKDrawing(data: sample.drawingData) else { return nil }
            let top = min(28, drawing.bounds.minY - 8)
            let rect = CGRect(x: drawing.bounds.minX - 8, y: top, width: max(48, drawing.bounds.width + 16),
                height: max(152, drawing.bounds.maxY + 8 - top))
            let image = drawing.image(from: rect, scale: min(1.5, 320 / rect.width))
            guard let data = image.pngData() else { return nil }
            return HandwritingPreviewTile(key: key, prepared: samples[key] != nil,
                source: samples[key]?.source ?? "", image: data)
        }
    }
}
