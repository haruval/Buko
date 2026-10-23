import FoundationModels
import Observation
import PencilKit

@Observable
final class BulletinCapture: Identifiable {
    let id: UUID
    let source: BulletinSource
    let document: AutofillDocument
    let drawing: PKDrawing
    let polygon: [CGPoint]
    var drafts: [BulletinDraft] = []
    var selectedText = ""
    var message: String?
    var busy = false
    var stage = "Reading handwriting…"
    private var requestID: UUID?
    private var task: Task<Void, Never>?
    private var timeout: Task<Void, Never>?

    init(source: BulletinSource, document: AutofillDocument, drawing: PKDrawing, polygon: [CGPoint]) {
        id = source.id; self.source = source; self.document = document; self.drawing = drawing; self.polygon = polygon
    }

    func start() {
        cancel()
        message = nil; drafts = []; busy = true; stage = "Reading handwriting…"
        let request = UUID(); requestID = request
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if requestID == request { busy = false; timeout?.cancel(); timeout = nil } }
            do {
                guard #available(iOS 27, *) else {
                    message = "Handwriting extraction needs iPadOS 27 or later."; return
                }
                guard case .available = SystemLanguageModel.default.availability else {
                    message = "On-device extraction isn’t available. Check that Apple Intelligence is enabled and its model has finished downloading in Settings."; return
                }
                guard drawing.strokes.count <= 1600 else { throw BulletinError.tooLarge }
                let text = try await CircleInkReader().read(drawing: drawing, polygon: polygon)
                try Task.checkCancellation()
                guard requestID == request else { return }
                selectedText = text.text; stage = "Finding important items…"
                let result = try await BulletinExtractor.extract(selected: text.text, context: text.context, source: source)
                try Task.checkCancellation()
                guard requestID == request else { return }
                drafts = result
                if result.isEmpty { message = "No clear action, event or important information was found in this band." }
            } catch is CancellationError { }
            catch {
                guard requestID == request else { return }
                if let read = error as? CircleInkReader.ReadError {
                    message = read == .noInk ? "No handwriting inside this band. Sweep across a few written lines."
                        : "This handwriting couldn’t be read. Try a wider band or clearer lettering."
                } else { message = error.localizedDescription }
            }
        }
        timeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
            guard let self, requestID == request, busy else { return }
            cancel(); message = "Extraction took too long. Try a smaller band."
        }
    }

    func cancel() {
        requestID = nil; task?.cancel(); task = nil; timeout?.cancel(); timeout = nil; busy = false
    }
}
