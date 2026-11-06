import PencilKit
import SwiftUI

struct PersonalAlphabetView: View {
    let preparation: HandwritingPreparation
    var noteID: UUID? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    let _ = preparation.status.revision
                    let samples = preparation.inspection(preferredID: noteID)
                    Text("\(PersonalAlphabetStore.letters.filter { samples[$0] != nil }.count) of 52 handwriting examples saved")
                        .font(.subheadline.weight(.medium)).accessibilityIdentifier("alphabetCoverage")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                        ForEach(Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init), id: \.self) { capital in
                            VStack(alignment: .leading, spacing: 12) {
                                Text("\(capital) \(capital.lowercased())").font(.title3.weight(.semibold))
                                HStack(alignment: .top, spacing: 12) {
                                    letter(capital, samples: samples)
                                    letter(capital.lowercased(), samples: samples)
                                }
                            }
                            .padding(14).background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 20))
                        }
                    }
                }.padding(24)
            }
            .navigationTitle("Your alphabet").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", systemImage: "checkmark") { dismiss() }.accessibilityIdentifier("closeAlphabet")
                }
            }
        }
    }

    private func letter(_ key: String, samples: [String: HandwritingInspectionSample]) -> some View {
        AlphabetLetterCell(letter: key, sample: samples[key]) { drawing in
            try preparation.saveAlphabet(drawing, letter: key)
        }
    }
}

private struct AlphabetLetterCell: View {
    let letter: String
    let sample: HandwritingInspectionSample?
    let save: (PKDrawing) throws -> Void
    @State private var drawing = PKDrawing()
    @State private var editing = false
    @State private var dirty = false
    @State private var saveTask: Task<Void, Never>?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(letter == letter.uppercased() ? "Capital \(letter)" : "Lowercase \(letter)")
                .font(.caption.weight(.medium))
            AlphabetCanvas(letter: letter, drawing: $drawing, changed: {
                dirty = true; editing = true; error = nil
                saveTask?.cancel()
                saveTask = Task {
                    do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
                    persist()
                }
            })
            .frame(height: 172).clipShape(.rect(cornerRadius: 12))
            .accessibilityLabel("Write \(letter) with Apple Pencil")
            .accessibilityIdentifier("alphabetCanvas.\(letter)")
            if let error {
                Text(error).font(.caption2).foregroundStyle(.red)
                    .accessibilityIdentifier("alphabetSource.\(letter)")
            } else if dirty {
                ProgressView("Saving…").font(.caption2)
            }
            Button("Rewrite", systemImage: "pencil.tip.crop.circle") {
                saveTask?.cancel(); dirty = false; editing = true; error = nil
                drawing = PKDrawing()
            }.buttonStyle(.glass).controlSize(.small)
                .accessibilityLabel("Rewrite \(letter)").accessibilityIdentifier("rewriteAlphabet.\(letter)")
        }
        .frame(maxWidth: .infinity)
        .onAppear { loadSample() }
        .onChange(of: sample?.sample.drawingData) { _, _ in if !editing { loadSample() } }
        .onDisappear { saveTask?.cancel(); persist() }
    }

    private func loadSample() {
        guard !editing, let sample, let ink = try? PKDrawing(data: sample.sample.drawingData) else { return }
        drawing = ink.transformed(using: CGAffineTransform(translationX: max(0, (140 - ink.bounds.width) / 2 - ink.bounds.minX), y: 0))
    }

    private func persist() {
        guard dirty, !drawing.strokes.isEmpty else { return }
        do { try save(drawing); dirty = false; error = nil }
        catch { self.error = "Couldn’t save. Add the rest of the letter or rewrite it." }
    }
}

private struct AlphabetCanvas: UIViewRepresentable {
    let letter: String
    @Binding var drawing: PKDrawing
    let changed: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> AlphabetWritingView {
        let view = AlphabetWritingView(letter: letter)
        view.canvas.drawing = drawing
        view.canvas.delegate = context.coordinator
        return view
    }
    func updateUIView(_ view: AlphabetWritingView, context: Context) {
        context.coordinator.parent = self
        if view.canvas.drawing != drawing {
            context.coordinator.updating = true
            view.canvas.drawing = drawing
            view.canvas.undoManager?.removeAllActions()
            context.coordinator.updating = false
        }
    }
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: AlphabetCanvas
        var updating = false
        init(_ parent: AlphabetCanvas) { self.parent = parent }
        func canvasViewDrawingDidChange(_ canvas: PKCanvasView) {
            guard !updating, canvas.drawing != parent.drawing else { return }
            parent.drawing = canvas.drawing
            parent.changed()
        }
    }
}

private final class AlphabetWritingView: UIView {
    let canvas = PKCanvasView()
    private let guide = UILabel()
    init(letter: String) {
        super.init(frame: .zero)
        backgroundColor = .white
        guide.attributedText = NSAttributedString(string: letter, attributes: [
            .font: UIFont.systemFont(ofSize: 96, weight: .regular),
            .strokeColor: UIColor.black.withAlphaComponent(0.15), .strokeWidth: 1.2,
            .foregroundColor: UIColor.clear
        ])
        guide.textAlignment = .center
        guide.isUserInteractionEnabled = false
        guide.isAccessibilityElement = false
        addSubview(guide)
        canvas.backgroundColor = .clear; canvas.isOpaque = false
        canvas.overrideUserInterfaceStyle = .light
        canvas.drawingPolicy = .pencilOnly
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--alphabetFingerTesting") { canvas.drawingPolicy = .anyInput }
        #endif
        canvas.isScrollEnabled = false
        canvas.tool = PKInkingTool(.pen, color: .black, width: MonochromeInk.penWidth)
        addSubview(canvas)
    }
    required init?(coder: NSCoder) { fatalError("Use init(letter:)") }
    override func layoutSubviews() {
        super.layoutSubviews()
        guide.frame = CGRect(x: 0, y: 13, width: bounds.width, height: 136)
        canvas.frame = bounds
    }
}
