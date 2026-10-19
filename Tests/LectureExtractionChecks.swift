import Foundation
import PDFKit
import CoreText
import AppKit

enum LectureExtractionChecks {
    static func run(in scratch: URL) async throws {
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let original = scratch.appendingPathComponent("mixed.pdf")
        try fixture(at: original)
        let originalBytes = try Data(contentsOf: original)
        let pdf = PDFDocument(data: originalBytes)!
        let heading = "Engineering Laboratory Notes and Revision Summary"
        precondition(pdf.page(at: 1)!.string!.contains(heading))
        precondition(!pdf.page(at: 1)!.string!.contains("eleven cooling fins"), "Body must be a real raster image")
        // More than 30 native letters on the mixed page reproduced the old omission.
        precondition(pdf.page(at: 1)!.string!.filter(\.isLetter).count > 30)

        let root = scratch.appendingPathComponent("library")
        let noteID = UUID()
        let library = LectureLibrary(root: root)
        let imported = try await library.importPDF(from: original, noteID: noteID)
        precondition(imported.extractionVersion == LecturePageExtractor.version)
        precondition(imported.pageCount == 2 && imported.skippedPages.isEmpty)
        let native = imported.passages.filter { $0.page == 1 }
        precondition(native.allSatisfy { !$0.usedOCR }, "OCR must not duplicate or replace good native text")
        precondition(native.map(\.text).joined(separator: " ") == "A native definition stays exact: scope follows source structure.")
        let mixed = imported.passages.filter { $0.page == 2 }
        let text = mixed.map(\.text).joined(separator: " ")
        precondition(text.contains(heading) && text.contains("eleven cooling fins") && text.contains("42 units"))
        precondition(text.contains("seventeen samples"), "OCR must retain raster text sharing a line with native text")
        precondition(text.components(separatedBy: heading).count == 2, "Native heading must appear only once")
        precondition(mixed.allSatisfy(\.usedOCR), "Mixed extraction must disclose OCR provenance")
        let search = try await library.search(noteID: noteID, selected: "reactor cooling fins", intent: "", method: .lexical)
        precondition(search.hits.first?.passage.page == 2 && search.hits.first!.passage.text.contains("eleven cooling fins"))
        let copiedPDF = try await library.pdfURL(noteID: noteID, documentID: imported.id)
        try checkBytes(copiedPDF, equalTo: originalBytes)
        try checkBytes(original, equalTo: originalBytes)

        // Rotation affects display, not the coordinate space used to merge native
        // and raster text. Use a separate temporary copy, never the user's PDF.
        pdf.page(at: 1)!.rotation = 90
        let rotated = scratch.appendingPathComponent("rotated.pdf")
        precondition(pdf.write(to: rotated))
        let rotatedDoc = try await library.importPDF(from: rotated, noteID: UUID())
        let rotatedText = rotatedDoc.passages.filter { $0.page == 2 }.map(\.text).joined(separator: " ")
        precondition(rotatedText.contains("eleven cooling fins") && rotatedText.components(separatedBy: heading).count == 2)

        // Recreate the old heading-only index in this isolated store, including
        // its absent extractionVersion key. A normal load must repair it once.
        let indexURL = copiedPDF.deletingLastPathComponent().appendingPathComponent("index.json")
        var legacy = imported
        legacy.extractionVersion = nil
        legacy.passages = [LecturePassage(id: "\(legacy.id):2:0", documentID: legacy.id, title: legacy.title,
                                         page: 2, text: heading, usedOCR: false, vector: nil)]
        let legacyData = try JSONEncoder().encode(legacy)
        precondition(!String(decoding: legacyData, as: UTF8.self).contains("extractionVersion"))
        try legacyData.write(to: indexURL, options: .atomic)
        let fresh = LectureLibrary(root: root)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await fresh.documents(noteID: noteID)
        }
        do { _ = try await cancelled.value; preconditionFailure("Cancelled repair published an index") }
        catch is CancellationError { }
        try checkBytes(indexURL, equalTo: legacyData)
        let repaired = try await fresh.documents(noteID: noteID).first!
        precondition(repaired.id == imported.id && repaired.importedAt == imported.importedAt && repaired.title == imported.title)
        precondition(repaired.extractionVersion == LecturePageExtractor.version)
        precondition(repaired.passages.contains { $0.page == 2 && $0.text.contains("eleven cooling fins") && $0.usedOCR })
        try checkBytes(copiedPDF, equalTo: originalBytes)
        try checkBytes(original, equalTo: originalBytes)
        let repairedData = try Data(contentsOf: indexURL)
        let anotherLaunch = LectureLibrary(root: root)
        _ = try await anotherLaunch.documents(noteID: noteID)
        try checkBytes(indexURL, equalTo: repairedData)
        let isolated = try await anotherLaunch.documents(noteID: UUID())
        precondition(isolated.isEmpty)

        // If the saved PDF no longer matches its hash, repair must not replace
        // its old index or overwrite the suspect source in an attempt to fix it.
        try legacyData.write(to: indexURL, options: .atomic)
        let damaged = Data("not the original PDF".utf8)
        try damaged.write(to: copiedPDF, options: .atomic)
        do {
            _ = try await LectureLibrary(root: root).documents(noteID: noteID)
            preconditionFailure("Reindexed mismatched source bytes")
        } catch LectureLibrary.LibraryError.invalidIndex { }
        try checkBytes(indexURL, equalTo: legacyData)
        try checkBytes(copiedPDF, equalTo: damaged)
        try checkBytes(original, equalTo: originalBytes)
        print("Lecture extraction checks passed: native/mixed/rotated pages, OCR provenance, retrieval, legacy repair/reopen, cancellation, and original-byte preservation.")
        try await disagreementChecks(in: scratch, healthyPDF: original)
    }

    private static func disagreementChecks(in scratch: URL, healthyPDF: URL) async throws {
        let bad = scratch.appendingPathComponent("incorrect-hidden-text.pdf")
        LectureEvidenceFixtures.layeredPDF(at: bad)
        let bytes = try Data(contentsOf: bad), pdf = PDFDocument(data: bytes)!
        precondition(pdf.string!.contains(LectureEvidenceFixtures.seven) && !pdf.string!.contains(LectureEvidenceFixtures.nine),
                     "The fixture must contain a genuinely incorrect native layer")
        let extracted = try LecturePageExtractor.extract(pdf.page(at: 0)!)
        precondition(extracted.hasTextDisagreement && extracted.text.isEmpty, "Never index either conflicting transcription as trusted evidence")

        let good = scratch.appendingPathComponent("matching-hidden-text.pdf")
        LectureEvidenceFixtures.layeredPDF(at: good, native: LectureEvidenceFixtures.nine)
        let matched = try LecturePageExtractor.extract(PDFDocument(url: good)!.page(at: 0)!)
        precondition(!matched.hasTextDisagreement && !matched.usedOCR && matched.text == LectureEvidenceFixtures.nine)
        for (index, pair) in [("The Luma sample has exactly 17 chambers.", "The Luma sample has exactly 19 chambers."),
                              ("The Luma sample is stable.", "The Luma sample is not stable.")].enumerated() {
            let url = scratch.appendingPathComponent("layer-disagreement-\(index).pdf")
            LectureEvidenceFixtures.layeredPDF(at: url, native: pair.0, visible: pair.1)
            let result = try LecturePageExtractor.extract(PDFDocument(url: url)!.page(at: 0)!)
            precondition(result.hasTextDisagreement)
        }
        pdf.page(at: 0)!.rotation = 90
        let rotated = scratch.appendingPathComponent("rotated-hidden-text.pdf")
        precondition(pdf.write(to: rotated))
        let rotatedResult = try LecturePageExtractor.extract(PDFDocument(url: rotated)!.page(at: 0)!)
        precondition(rotatedResult.hasTextDisagreement)

        let root = scratch.appendingPathComponent("disagreement-library"), note = UUID()
        let library = LectureLibrary(root: root)
        let healthy = try await library.importPDF(from: healthyPDF, noteID: note)
        let document = try await library.importPDF(from: bad, noteID: note)
        precondition(document.textDisagreementPages == [1] && document.passages.isEmpty && document.skippedPages.isEmpty)
        let copy = try await library.pdfURL(noteID: note, documentID: document.id)
        try checkBytes(copy, equalTo: bytes)
        let blocked = try await library.search(noteID: note, selected: "reactor cooling fins", intent: "")
        precondition(blocked.hasUnverifiedText && blocked.hits.isEmpty && blocked.documentCount == 2,
                     "Do not silently omit a suspect page while answering from the other PDFs")
        let otherNote = UUID()
        try await library.importPDF(from: healthyPDF, noteID: otherNote)
        let isolated = try await library.search(noteID: otherNote, selected: "reactor cooling fins", intent: "")
        precondition(!isolated.hasUnverifiedText && !isolated.hits.isEmpty)

        // Simulate the v2 index that trusted the wrong searchable layer. Repair
        // derived data only, retaining access to inspect/remove the original copy.
        var legacy = document
        legacy.extractionVersion = 2; legacy.textDisagreementPages = nil
        legacy.passages = [LecturePassage(id: "\(document.id):1:0", documentID: document.id, title: document.title,
                                         page: 1, text: LectureEvidenceFixtures.seven, usedOCR: false, vector: nil)]
        let index = copy.deletingLastPathComponent().appendingPathComponent("index.json")
        let legacyBytes = try JSONEncoder().encode(legacy)
        try legacyBytes.write(to: index, options: .atomic)
        let fresh = LectureLibrary(root: root)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await fresh.documents(noteID: note)
        }
        do { _ = try await cancelled.value; preconditionFailure("Cancelled migration published") }
        catch is CancellationError { }
        try checkBytes(index, equalTo: legacyBytes)
        let repaired = try await fresh.documents(noteID: note).first { $0.id == document.id }!
        precondition(repaired.extractionVersion == 3 && repaired.textDisagreementPages == [1] && repaired.passages.isEmpty)
        precondition(repaired.title == document.title && repaired.importedAt == document.importedAt)
        let repairedBytes = try Data(contentsOf: index)
        let reopened = LectureLibrary(root: root)
        let reopenedSearch = try await reopened.search(noteID: note, selected: "Luma chamber count", intent: "")
        precondition(reopenedSearch.hasUnverifiedText && reopenedSearch.hits.isEmpty)
        try checkBytes(index, equalTo: repairedBytes)
        let inspectable = try await reopened.pdfURL(noteID: note, documentID: document.id)
        precondition(inspectable == copy)
        try checkBytes(copy, equalTo: bytes)
        try checkBytes(bad, equalTo: bytes)
        try await reopened.remove(documentID: document.id, noteID: note)
        let resumed = try await reopened.search(noteID: note, selected: "reactor cooling fins", intent: "")
        precondition(!resumed.hasUnverifiedText && resumed.hits.contains { $0.passage.documentID == healthy.id })
        try checkBytes(bad, equalTo: bytes)
        print("Text-layer disagreement checks passed: visible/native mismatch, numbers/negation, rotation, matching layer, quarantine, notebook isolation, inspect/remove, v2 repair/reopen, cancellation, and original-byte preservation.")
    }

    private static func checkBytes(_ url: URL, equalTo expected: Data) throws {
        let actual = try Data(contentsOf: url)
        precondition(actual == expected, "Unexpected file change: \(url.lastPathComponent)")
    }

    private static func fixture(at url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = CGContext(url as CFURL, mediaBox: &box, nil)!
        context.beginPDFPage(nil)
        draw("A native definition stays exact: scope follows source structure.",
             in: context, at: CGPoint(x: 36, y: 720), size: 16)
        context.endPDFPage()
        context.beginPDFPage(nil)
        draw("Engineering Laboratory Notes and Revision Summary", in: context, at: CGPoint(x: 36, y: 720), size: 16)
        let bitmap = CGContext(data: nil, width: 1400, height: 240, bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        bitmap.setFillColor(CGColor(gray: 1, alpha: 1)); bitmap.fill(CGRect(x: 0, y: 0, width: 1400, height: 240))
        draw("The fictional reactor has exactly eleven cooling fins.", in: bitmap, at: CGPoint(x: 30, y: 150), size: 36)
        draw("Its test threshold is 42 units under controlled conditions.", in: bitmap, at: CGPoint(x: 30, y: 80), size: 36)
        context.draw(bitmap.makeImage()!, in: CGRect(x: 36, y: 450, width: 540, height: 92.57))
        draw("A separate replication used a total of exactly", in: context, at: CGPoint(x: 36, y: 300), size: 16)
        let inline = CGContext(data: nil, width: 500, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        inline.setFillColor(CGColor(gray: 1, alpha: 1)); inline.fill(CGRect(x: 0, y: 0, width: 500, height: 80))
        draw("seventeen samples", in: inline, at: CGPoint(x: 0, y: 20), size: 40)
        context.draw(inline.makeImage()!, in: CGRect(x: 390, y: 293.2, width: 170, height: 27.2))
        context.endPDFPage()
        context.closePDF()
    }

    private static func draw(_ text: String, in context: CGContext, at point: CGPoint, size: CGFloat) {
        context.textPosition = point
        let attributes: [NSAttributedString.Key: Any] = [.font: CTFontCreateWithName("Helvetica" as CFString, size, nil),
                                                        .foregroundColor: CGColor(gray: 0, alpha: 1)]
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)), context)
    }
}
