// Compiled only by run-insertion-simulator-checks.sh into an isolated app bundle.
// Synthetic fixtures exercise insertion, never masquerade as model or user output.
import PencilKit
import SwiftData
import SwiftUI

@main struct InsertionHarnessApp: App {
    var body: some Scene { WindowGroup { InsertionHarnessView().ignoresSafeArea() } }
}

private struct InsertionHarnessView: UIViewRepresentable {
    func makeUIView(context: Context) -> CanvasHostView {
        let host = CanvasHostView(pagePull: PagePullState())
        let driver = InsertionHarnessDriver(host: host)
        context.coordinator.driver = driver
        Task { await driver.run() }
        return host
    }
    func updateUIView(_ uiView: CanvasHostView, context: Context) { }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var driver: InsertionHarnessDriver? }
}

@MainActor private final class InsertionHarnessDriver {
    let host: CanvasHostView
    let container: ModelContainer
    let note: Note
    let original: AutofillDocument
    let session = CanvasSession()
    var coordinator: NoteCanvas.Coordinator?
    var failSave = false
    var isFlowExample: Bool { ProcessInfo.processInfo.arguments.contains("--flow-preview") }
    var heading: String { isFlowExample ? "Precedence vs associativity:" : "Parsing:" }
    var text: String {
        isFlowExample
            ? "Precedence determines which operators bind more tightly: multiplication typically binds more tightly than addition.\nAssociativity resolves grouping among operators of the same precedence. Left-associative subtraction groups a - b - c as (a - b) - c."
            : "groups tokens into a syntax tree.\nThe parser checks how tokens fit the grammar."
    }
    var polygon: [CGPoint] {
        isFlowExample
            ? [CGPoint(x: 1060, y: 120), CGPoint(x: 1530, y: 120), CGPoint(x: 1530, y: 182), CGPoint(x: 1060, y: 182)]
            : [CGPoint(x: 1060, y: 180), CGPoint(x: 1260, y: 180), CGPoint(x: 1260, y: 222), CGPoint(x: 1060, y: 222)]
    }

    init(host: CanvasHostView) {
        self.host = host
        container = try! ModelContainer(for: Note.self, TrashedPage.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        note = Note(title: "Isolated autofill validation")
        note.pageLayoutVersion = 2
        try! note.setPages([NotebookPage()])
        let fixtureLines = ProcessInfo.processInfo.arguments.contains("--flow-preview")
            ? ["Precedence vs associativity:", "Keep these existing notes intact."] : [
            "Lexical analysis: groups characters into tokens.", "Parsing:", "Type checking:",
            "Keep these existing notes intact.", "An expression can have a type."]
        note.drawingData = LectureHandwriting.drawing(pages: [fixtureLines]).dataRepresentation()
        container.mainContext.insert(note); try! container.mainContext.save()
        original = AutofillDocument(note)
        host.circleIntent.noteID = note.id
        host.load(try! AutofillDocument.drawing(note.drawingData), savedPageCount: 1, pageIndex: 0)
        let dark = ProcessInfo.processInfo.arguments.contains("--dark")
        host.overrideUserInterfaceStyle = dark ? .dark : .light
        host.configure(tool: .pen, allowsFingerDrawing: true, showsGrid: true, colorScheme: dark ? .dark : .light)
        session.host = host; session.canvas = host.canvas
        let coordinator = NoteCanvas.Coordinator(session: session) { [weak self] data in
            guard let self else { return }
            self.note.drawingData = data
            try! self.container.mainContext.save()
        }
        coordinator.host = host; coordinator.hasLoadedDrawing = true
        self.coordinator = coordinator; host.canvas.delegate = coordinator
        host.captureAutofillDocument = { [weak self] in self.map { AutofillDocument($0.note) } }
        host.persistAutofill = { [weak self] before, after in
            guard let self, before.matches(AutofillDocument(self.note)) else { throw AutofillEditError.stale }
            try NotebookEdits.commit(in: self.container.mainContext, notes: [self.note]) {
                after.apply(to: self.note)
                if self.failSave { throw AutofillEditError.unavailable }
            }
        }
    }

    func preview(source: String? = nil) async throws {
        host.circleIntent.cancel()
        let revision = try await LectureLibrary.shared.revision(noteID: note.id)
        let proposal = AutofillProposal(requestID: UUID(), noteID: note.id, capturedAt: .now,
            selectionPolygon: polygon, selectedText: heading, sourceRevision: source ?? revision,
            content: AutofillContent(lines: text.components(separatedBy: .newlines).map {
                .init(text: $0, citationIndices: [])
            }, origin: .lectureDraft), citations: [], insertionTarget: heading)
        host.circleIntent.insertion.capture()
        host.circleIntent.validationPreview(proposal, scale: host.canvas.zoomScale, offset: host.canvas.contentOffset)
        for _ in 0..<200 {
            if !host.circleIntent.insertion.isPreparing { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(200))
        precondition(!host.circleIntent.insertion.isPreparing)
        precondition(original.matches(AutofillDocument(note)), "Preview mutated persistence")
        precondition(AutofillDocument.sameInk(host.canonicalDrawing, try! AutofillDocument.drawing(original.ink)), "Preview mutated live ink")
    }

    @available(iOS 27, *)
    func checkOtherNotesAndGeneratedExclusion() async throws {
        let proposal = AutofillProposal(requestID: UUID(), noteID: note.id, capturedAt: .now,
            selectionPolygon: polygon, selectedText: "Parsing:", sourceRevision: "fixture",
            content: AutofillContent(lines: [.init(text: "tokens into", citationIndices: [])], origin: .lectureDraft), citations: [])
        let ink = try AutofillDocument.drawing(original.ink)
        let record = AutofillRecord(proposal: proposal, documentRevision: original.revision,
            drawing: ink, bounds: ink.bounds, rendering: "fixture-generated")
        let generated = AutofillDocument(noteID: original.noteID, ink: original.ink, pages: original.pages,
            pageCount: 1, layoutVersion: original.layoutVersion, history: try JSONEncoder().encode([record]))
        let excluded = try await HandwritingSampler().sample(documents: [generated], proposal: proposal)
        precondition(excluded.samples.isEmpty, "Never call generated ink a personal handwriting sample")
        let otherNote = AutofillDocument(noteID: UUID(), ink: original.ink, pages: original.pages,
            pageCount: 1, layoutVersion: original.layoutVersion, history: Data())
        let sampled = try await HandwritingSampler().sample(documents: [generated, otherNote], proposal: proposal)
        precondition(!sampled.samples.isEmpty, "Use existing handwriting from another note without character setup")
    }

    func waitForAcceptance() async throws {
        for _ in 0..<100 {
            if !host.circleIntent.insertion.isAccepting { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        preconditionFailure("Acceptance timed out")
    }

    func run() async {
        do {
            try await Task.sleep(for: .seconds(1))
            host.canvas.undoManager?.removeAllActions()
            if ProcessInfo.processInfo.arguments.contains("--undo-controls") {
                let status = UILabel(frame: CGRect(x: 240, y: host.bounds.height - 64, width: 300, height: 44))
                status.accessibilityIdentifier = "validationUndoStatus"
                status.text = "Ready"; host.addSubview(status)
                let button = UIButton(type: .system)
                button.frame = CGRect(x: 24, y: host.bounds.height - 64, width: 200, height: 44)
                button.setTitle("Validation undo", for: .normal)
                button.addAction(UIAction { [weak self, weak status] _ in
                    guard let self else { return }
                    self.session.undo()
                    DispatchQueue.main.async {
                        status?.text = self.original.matches(AutofillDocument(self.note)) ? "Original restored" : "Edited"
                    }
                }, for: .touchUpInside)
                host.addSubview(button)
            }
            try await preview()
            guard ProcessInfo.processInfo.arguments.contains("--run-checks") else { return }
            precondition(host.circleIntent.insertion.canAccept)
            let layout = host.circleIntent.insertion.layout!
            precondition(layout.sampledGlyphCount > 0, "Real note recognition must supply at least one sample in this fixture")
            let rows = AutofillTypography.rows(try AutofillDocument.drawing(original.ink).strokes)
            precondition(layout.lines[0].frame.minX > rows[1].bounds.maxX)
            precondition(abs(layout.lines[0].frame.minY - rows[1].bounds.minY) < 1)
            let diagnostics = "Sampled characters: \(layout.sampledGlyphCount); fallback: \(layout.fallbackGlyphCount); size: \(layout.letterHeight)"
            try Data(diagnostics.utf8).write(to: URL.documentsDirectory.appendingPathComponent("sampling.txt"))
            host.circleIntent.cancel()
            precondition(original.matches(AutofillDocument(note)) && host.canvas.undoManager?.canUndo == false)
            try await preview()
            failSave = true
            host.circleIntent.insertion.accept(); try await waitForAcceptance()
            precondition(original.matches(AutofillDocument(note)) && host.circleIntent.insertion.canAccept)
            precondition(host.canvas.undoManager?.canUndo == false)
            failSave = false
            host.circleIntent.insertion.accept(); try await waitForAcceptance()
            let accepted = AutofillDocument(note)
            precondition(!original.matches(accepted) && !(note.autofillHistory ?? Data()).isEmpty)
            precondition(host.canvas.undoManager?.canUndo == true)
            host.canvas.undoManager?.undo()
            try await Task.sleep(for: .milliseconds(100))
            precondition(original.matches(AutofillDocument(note)), "Native undo failed to restore note")
            host.canvas.undoManager?.redo()
            try await Task.sleep(for: .milliseconds(100))
            precondition(accepted.matches(AutofillDocument(note)), "Native redo failed")
            host.canvas.undoManager?.undo()
            try await Task.sleep(for: .milliseconds(100))
            try await preview(source: "stale source revision")
            host.circleIntent.insertion.accept(); try await waitForAcceptance()
            precondition(original.matches(AutofillDocument(note)) && !host.circleIntent.insertion.canAccept)
            try await preview()
            host.circleIntent.insertion.accept()
            host.circleIntent.cancel()
            try await Task.sleep(for: .milliseconds(200))
            precondition(original.matches(AutofillDocument(note)), "Cancelled acceptance applied")
            try await preview()
            note.drawingData = PKDrawing().dataRepresentation()
            try container.mainContext.save()
            host.circleIntent.insertion.accept(); try await waitForAcceptance()
            precondition((try! PKDrawing(data: note.drawingData)).strokes.isEmpty && !host.circleIntent.insertion.canAccept)
            original.apply(to: note); try container.mainContext.save()
            try await preview()
            if #available(iOS 27, *) { try await checkOtherNotesAndGeneratedExclusion() }
            try Data("PASS: automatic current/other-note sampling, generated-ink exclusion, inline placement, preview/decline, failure rollback/retry, native atomic undo/redo, source and document staleness, cancellation".utf8)
                .write(to: URL.documentsDirectory.appendingPathComponent("result.txt"), options: .atomic)
        } catch {
            try? Data("FAIL: \(error)".utf8).write(to: URL.documentsDirectory.appendingPathComponent("result.txt"))
        }
    }
}
