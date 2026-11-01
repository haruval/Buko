import PencilKit
import SwiftUI

struct PersonalAlphabetView: View {
    let preparation: HandwritingPreparation
    @Environment(\.dismiss) private var dismiss
    @State private var letter = "a"
    @State private var drafts: [String: PKDrawing] = [:]
    @State private var saved = Set<String>()
    @State private var error: String?

    private var drawing: Binding<PKDrawing> {
        Binding(get: { drafts[letter] ?? PKDrawing() }, set: { drafts[letter] = $0 })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Write each letter in your usual handwriting. Samples from your notes always come first; this alphabet fills the gaps.")
                        .foregroundStyle(.secondary)
                    Text("\(saved.count) of 52 letters saved").font(.subheadline.weight(.medium))
                        .accessibilityIdentifier("alphabetCoverage")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
                        ForEach(PersonalAlphabetStore.letters, id: \.self) { key in
                            Button { letter = key } label: {
                                Text(key).font(.title3).frame(maxWidth: .infinity, minHeight: 44)
                                    .background(letter == key ? Color.accentColor.opacity(0.2) : .clear, in: .rect(cornerRadius: 12))
                                    .overlay(alignment: .topTrailing) {
                                        if saved.contains(key) { Image(systemName: "checkmark").font(.system(size: 9)).padding(4) }
                                    }
                            }
                            .buttonStyle(.plain).accessibilityLabel("\(key), \(saved.contains(key) ? "saved" : "not saved")")
                            .accessibilityIdentifier("alphabetLetter.\(key)")
                        }
                    }
                    Text("Write \(letter)").font(.title2.weight(.medium))
                    AlphabetCanvas(drawing: drawing)
                        .frame(height: 220)
                        .clipShape(.rect(cornerRadius: 20))
                        .accessibilityLabel("Write the letter \(letter)")
                        .accessibilityIdentifier("alphabetCanvas")
                    HStack {
                        Button("Clear", systemImage: "eraser") { drafts[letter] = PKDrawing() }
                            .buttonStyle(.glass).accessibilityIdentifier("clearAlphabetLetter")
                        Spacer()
                        Button("Save & next", systemImage: "checkmark") { saveAndAdvance() }
                            .buttonStyle(.glassProminent).disabled(drawing.wrappedValue.strokes.isEmpty)
                            .accessibilityIdentifier("saveAlphabetLetter")
                    }
                    Text("Use Apple Pencil or a finger. Save replaces only this letter; Clear affects the unsaved drawing.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(24)
            }
            .navigationTitle("Your alphabet").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("closeAlphabet")
                }
            }
        }
        .onAppear {
            saved = Set(preparation.alphabet.samples.keys)
            for (key, sample) in preparation.alphabet.samples where drafts[key] == nil {
                if let drawing = try? PKDrawing(data: sample.drawingData) {
                    drafts[key] = drawing.transformed(using: CGAffineTransform(translationX: 60, y: 0))
                }
            }
        }
        .alert("Letter couldn’t be saved", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { }
        } message: { Text(error ?? "Try writing the letter again.") }
    }

    private func saveAndAdvance() {
        do {
            try preparation.saveAlphabet(drawing.wrappedValue, letter: letter)
            saved.insert(letter)
            let letters = PersonalAlphabetStore.letters
            if let index = letters.firstIndex(of: letter), index + 1 < letters.count { letter = letters[index + 1] }
        } catch { self.error = "Your previous saved alphabet is unchanged. Try a clear letter with no erased strokes, or try saving again." }
    }
}

private struct AlphabetCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .secondarySystemBackground
        canvas.overrideUserInterfaceStyle = .light
        canvas.drawingPolicy = .anyInput
        canvas.isScrollEnabled = false
        canvas.tool = PKInkingTool(.pen, color: .black, width: 2.5)
        canvas.drawing = drawing
        canvas.delegate = context.coordinator
        return canvas
    }
    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        if canvas.drawing != drawing { canvas.drawing = drawing; canvas.undoManager?.removeAllActions() }
    }
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: AlphabetCanvas
        init(_ parent: AlphabetCanvas) { self.parent = parent }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) { parent.drawing = canvasView.drawing }
    }
}
