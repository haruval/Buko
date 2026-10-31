import Foundation
import PencilKit

/// Authored lecture-note fixtures, not independent human handwriting.
@MainActor enum SpatialAppFixture {
    static var name: String {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--spatial-fixture"), args.indices.contains(i+1) else { return "static" }
        return args[i+1]
    }
    static var baseline: Bool { ProcessInfo.processInfo.arguments.contains("--spatial-baseline") }
    static var pdfName: String { name.hasPrefix("question-") ? "linearAlgebra" : (name == "threads" ? "operatingSystems" : "programmingLanguages") }
    static var root: URL { URL.documentsDirectory.appendingPathComponent("SpatialEvidence", isDirectory: true) }
    static var rectangle: CGRect {
        if name == "question-why" { return CGRect(x: 1045, y: 1045, width: 900, height: 50) }
        if name.hasPrefix("question-") { return CGRect(x: 1045, y: 855, width: 900, height: 95) }
        if name == "single" { return CGRect(x: 1050, y: 210, width: 850, height: 95) }
        return CGRect(x: 1045, y: 210, width: 900, height: name == "wrapped" ? 115 : 75)
    }
    static func ink(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat) -> PKDrawing {
        var drawing = LectureHandwriting.drawing(pages: [[text]])
        let b = drawing.bounds, sx = min(1, width / drawing.bounds.width), sy = 20 / drawing.bounds.height
        drawing.transform(using: CGAffineTransform(scaleX: sx, y: sy).concatenating(
            CGAffineTransform(translationX: PageGeometry.pageOriginX+x-b.minX*sx, y:y-b.minY*sy)))
        return drawing
    }
    static func drawing() -> PKDrawing {
        if name.hasPrefix("question-") {
            var page = SampleLecture.linearAlgebraPages[0]
            if name == "question-new-dimensions" {
                page[15] = "A is 4 by 6 and B is 6 by 4."
            }
            if name == "question-missing-input" { page[15] = "A is 2 by 3. B has an unknown size." }
            return LectureHandwriting.drawing(pages: [page])
        }
        var rows: [(String, CGFloat, CGFloat, CGFloat)] = [
            ("PROGRAMMING LANGUAGES - scope rules",60,70,850),
            ("Record each scope's purpose and lookup rule.",60,160,870),
            ("Static scope resolves variable names.",60,220,370),
            ("Dynamic scope resolves variable names.",560,220,370)]
        switch name {
        case "threads":
            rows = [("OPERATING SYSTEMS - execution units",60,70,850),
                    ("Record each unit's purpose and memory ownership.",60,160,870),
                    ("Process is a running program.",60,220,370),
                    ("Thread is an execution unit.",560,220,370),
                    ("Owns a private address space.",80,260,370)]
        case "dynamic": rows.append(("Lookup follows lexical nesting.",80,260,370))
        case "wrapped":
            rows.append(("Lookup follows the",580,260,370))
            rows.append(("active calling sequence.",580,300,370))
        case "complete":
            rows.append(("Lookup follows lexical nesting.",80,260,370))
            rows.append(("Lookup follows the calling sequence.",580,260,370))
        case "ambiguous": break
        case "single":
            rows = [("COMPILER PIPELINE",60,70,850),
                    ("Lexical analysis produces tokens.",60,220,750), ("Parsing:",60,265,750)]
        default: rows.append(("Lookup follows the calling sequence.",580,260,370))
        }
        rows.append((name == "threads" ? "Keep: scheduling and memory are different." : "Keep: binding time and lifetime are different.",60,660,850))
        rows.append((name == "threads" ? "Next lecture: synchronization and shared state." : "Next lecture: functions and parameter passing.",60,710,850))
        return PKDrawing(strokes: rows.flatMap { ink($0.0, x:$0.1, y:$0.2, width:$0.3).strokes })
    }
    static func saveOriginal(_ document: AutofillDocument) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: [
            "id": document.noteID.uuidString, "ink": document.ink, "pages": document.pages,
            "count": document.pageCount, "version": document.layoutVersion, "history": document.history
        ], format: .binary, options: 0)
        try data.write(to: root.appendingPathComponent("original.plist"), options: .atomic)
    }
    static func loadOriginal() throws -> AutofillDocument {
        let object = try PropertyListSerialization.propertyList(from: Data(contentsOf: root.appendingPathComponent("original.plist")), format:nil) as! [String:Any]
        return AutofillDocument(noteID: UUID(uuidString: object["id"] as! String)!, ink:object["ink"] as! Data,
            pages:object["pages"] as! Data, pageCount:object["count"] as! Int,
            layoutVersion:object["version"] as! Int, history:object["history"] as! Data)
    }
    static func checkpoint(note: Note, host: CanvasHostView, original: AutofillDocument, tag: String) throws -> String {
        let current = AutofillDocument(note), intent = host.circleIntent
        let records = current.history.isEmpty ? [] : try JSONDecoder().decode([AutofillRecord].self, from: current.history)
        let liveOriginal = AutofillDocument.sameInk(try AutofillDocument.drawing(original.ink), host.canonicalDrawing)
        let liveMatchesStore = AutofillDocument.sameInk(try AutofillDocument.drawing(current.ink), host.canonicalDrawing)
        let status = "original=\(original.matches(current));liveOriginal=\(liveOriginal);liveMatchesStore=\(liveMatchesStore);records=\(records.count);pages=\(current.pageCount)"
        var row: [String:Any] = ["fixture":name, "baseline":baseline, "tag":tag, "status":status,
            "noteID":note.id.uuidString, "phase":String(describing:intent.phase), "recognition":intent.recognizedText,
            "recognitionMethod":intent.recognitionMethod, "context":intent.nearbyContext, "intent":intent.intent,
            "action":intent.action, "clarification":intent.clarification, "issue":intent.issue ?? "",
            "insertionIssue":intent.insertion.issue ?? "", "sourceDetail":intent.sourceDetail,
            "draft":intent.proposal?.text ?? "", "draftDetail":intent.draftDetail,
            "originalRevision":original.revision,"revision":current.revision,
            "strokeCount":host.canonicalDrawing.strokes.count,
            "records":try JSONSerialization.jsonObject(with:JSONEncoder().encode(records)),
            "trace":intent.pipeline.steps.map { ["id":$0.id,"input":$0.input,"instructions":$0.instructions ?? "","summary":$0.summary,"status":String(describing:$0.status)] }]
        if let gap = intent.missingInformation { row["gap"] = try JSONSerialization.jsonObject(with:JSONEncoder().encode(gap)) }
        row["citations"] = intent.citations.map { ["quote":$0.quote,"page":$0.passage.page,"title":$0.passage.title] as [String:Any] }
        if let layout = intent.insertion.layout {
            row["previewBounds"] = [layout.bounds.minX,layout.bounds.minY,layout.bounds.width,layout.bounds.height]
        }
        let filename = "\(baseline ? "baseline" : "candidate")-\(name)-\(tag)-\(UUID().uuidString)"
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        try JSONSerialization.data(withJSONObject:row,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent(filename+".json"))
        try current.ink.write(to:root.appendingPathComponent(filename+".drawing"))
        return status
    }
}
