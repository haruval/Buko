import Foundation
import PencilKit
import SwiftData

@main struct AutofillInsertionChecks {
    enum Injected: Error { case failure }
    @MainActor static func main() async throws {
        try await AutofillPreparationRaceChecks.run()
        AutofillReflowChecks.run()
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        func stroke(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat = 60, _ height: CGFloat = 20) -> PKStroke {
            let points = [CGPoint(x: x, y: y), CGPoint(x: x + width / 2, y: y + height), CGPoint(x: x + width, y: y)]
            let path = PKStrokePath(controlPoints: points.enumerated().map { i, p in
                PKStrokePoint(location: p, timeOffset: Double(i) * 0.1, size: CGSize(width: 2, height: 2),
                              opacity: 1, force: 0.7, azimuth: 0.2, altitude: 1.1)
            }, creationDate: Date(timeIntervalSince1970: 1))
            return PKStroke(ink: PKInk(.pen, color: .black), path: path, randomSeed: 42)
        }
        func selection(_ y: CGFloat) -> [CGPoint] {
            [CGPoint(x: 1050, y: y - 20), CGPoint(x: 1250, y: y - 20),
             CGPoint(x: 1250, y: y + 45), CGPoint(x: 1050, y: y + 45)]
        }
        let sample = PKDrawing(strokes: [stroke(100, 60, 45, 65)])
        let samples = ["a": try HandwritingSample(drawing: sample), "b": try HandwritingSample(drawing: sample)]
        try await PreparedHandwritingChecks.run(root: root, sample: samples["a"]!)
        do { _ = try HandwritingSample(drawing: PKDrawing()); preconditionFailure("Empty samples must fail") }
        catch HandwritingSample.SampleError.invalidInk { }

        // Reproduce the physical report: tiny cached connected words beside
        // ordinary fallback ink. Size/baseline must be independent of source scale.
        for word in ["can", "but", "edit", "gy", "Maya"] {
            var strokes: [PKStroke] = []
            var x: CGFloat = 0
            for character in word {
                let glyph = try PKDrawing(data: HandwrittenFont.sample(String(character))!.drawingData)
                strokes += glyph.transformed(using: CGAffineTransform(translationX: x, y: 0)).strokes
                x += glyph.bounds.width + 8
            }
            let reference = PKDrawing(strokes: strokes)
            for factor: CGFloat in [0.08, 0.3, 2] {
                let source = reference.transformed(using: CGAffineTransform(scaleX: factor, y: factor)
                    .concatenating(CGAffineTransform(translationX: 800, y: 450)))
                let normalized = try HandwritingSample.normalized(drawing: source, text: word)
                let actual = try PKDrawing(data: normalized.drawingData)
                precondition(abs(actual.bounds.height - reference.bounds.height) < 2, "Sample height must match the shared lettering metrics")
                precondition(abs(actual.bounds.maxY - reference.bounds.maxY) < 2, "Samples must share a baseline and preserve descenders")
                let again = try PKDrawing(data: HandwritingSample.normalized(drawing: actual, text: word).drawingData)
                precondition(abs(again.bounds.height - actual.bounds.height) < 0.5, "Normalization must not compound on cache reuse")
            }
        }
        print("Physical handwriting regression: tiny words, cap/x-height, baseline, descenders and repeated normalization passed")

        let original = PKDrawing(strokes: [stroke(1100, 110), stroke(1100, 160), stroke(1100, 235)])
        let originalData = original.dataRepresentation()
        let staged = try AutofillLayout.stage(text: "abba abba\nba", drawing: original,
            selection: selection(110), pageCount: 1, samples: samples)
        precondition(staged.missing.isEmpty && staged.inserted.strokes.count == 10)
        precondition(Set(staged.inserted.strokes.map(\.id)).count == 10, "Every composed letter needs its own identity")
        precondition(AutofillDocument.sameInk(PKDrawing(strokes: [staged.existing.strokes[0]]), PKDrawing(strokes: [original.strokes[0]])))
        for (before, after) in zip(original.strokes, staged.existing.strokes) {
            precondition(before.path.map(\.location) == after.path.map(\.location)
                         && before.path.map(\.force) == after.path.map(\.force)
                         && before.mask == after.mask && before.randomSeed == after.randomSeed)
            precondition(before.id == after.id && after.transform.ty >= before.transform.ty)
        }
        precondition(staged.existing.strokes[1].renderBounds.minY > staged.bounds.maxY)
        precondition(original.dataRepresentation() == originalData, "Staging cannot mutate original ink")
        let lettersOnly = try AutofillLayout.stage(text: "aba", drawing: original, selection: selection(110),
            pageCount: 1, samples: ["a": samples["a"]!, "aba": samples["b"]!])
        precondition(lettersOnly.sampledGlyphCount == 2 && lettersOnly.fallbackGlyphCount == 1,
            "An old word cache must never hide personal letter samples or missing-letter fallback")
        let unavailable = try AutofillLayout.stage(text: "abc", drawing: original, selection: selection(110),
            pageCount: 1, samples: samples)
        precondition(unavailable.missing.isEmpty && !unavailable.inserted.strokes.isEmpty && unavailable.fallbackGlyphCount == 1)

        let edge = PKDrawing(strokes: [stroke(1100, 1220), stroke(1100, 1270),
            stroke(1100, NotebookPaging.pageStride + 50)])
        let flowed = try AutofillLayout.stage(text: String(repeating: "abba ", count: 45), drawing: edge,
            selection: selection(1220), pageCount: 2, samples: samples)
        for line in flowed.lines {
            let page = NotebookPaging.rect(for: Int(line.frame.minY / NotebookPaging.pageStride))
            precondition(page.insetBy(dx: 0, dy: AutofillLayout.margin).contains(line.frame))
        }
        for new in flowed.existing.strokes.dropFirst() {
            let page = NotebookPaging.rect(for: Int(new.renderBounds.minY / NotebookPaging.pageStride))
            precondition(new.renderBounds.maxY <= page.maxY - AutofillLayout.margin)
        }
        precondition(flowed.existing.strokes[1].renderBounds.maxY < flowed.existing.strokes[2].renderBounds.minY)
        let nearGutter = NotebookPaging.pageHeight - 10
        let nudgedUp = try AutofillLayout.onPaper(nearGutter, height: 20, minimumTop: NotebookPaging.pageHeight - 100)
        precondition(nudgedUp < nearGutter && nudgedUp + 20 <= NotebookPaging.pageHeight - AutofillLayout.margin)
        let spaced = PKDrawing(strokes: [stroke(1100, 110), stroke(1100, 800)])
        let untouched = try AutofillLayout.stage(text: "ab", drawing: spaced, selection: selection(110), pageCount: 1, samples: samples)
        precondition(AutofillDocument.sameInk(untouched.existing, spaced), "Don't shift ink when whitespace already fits")
        do {
            _ = try AutofillLayout.stage(text: "ab", drawing: PKDrawing(strokes: [stroke(1100, 110), stroke(1100, 200, 50, 3000)]),
                selection: selection(110), pageCount: 2, samples: samples)
            preconditionFailure("Oversized diagrams must not be cut")
        } catch AutofillLayout.LayoutError.oversizedInk { }

        let storeURL = root.appendingPathComponent("notes.store")
        let container = try ModelContainer(for: Note.self, TrashedPage.self, configurations: ModelConfiguration(url: storeURL))
        let context = container.mainContext
        let note = Note(title: "Disposable insertion check")
        note.pageLayoutVersion = 2; try note.setPages([NotebookPage()]); note.drawingData = originalData
        context.insert(note); try context.save()
        let before = AutofillDocument(note)
        let appendedInk = PKDrawing(strokes: original.strokes + [stroke(1100, 650)])
        note.drawingData = appendedInk.dataRepresentation()
        let appended = AutofillDocument(note)
        precondition(before.permitsAppending(appended, outside: selection(110)), "Writing elsewhere must preserve an in-progress capture")
        let rebuilt = try AutofillLayout.stage(text: "abba", drawing: appendedInk,
            selection: selection(110), pageCount: 1, samples: samples)
        precondition(rebuilt.existing.strokes.count == appendedInk.strokes.count, "Rebase retains every new stroke")
        for stroke in rebuilt.inserted.strokes {
            for point in stroke.path {
                let width = point.size.width * hypot(stroke.transform.a, stroke.transform.b)
                precondition(abs(width - 1.62) < 0.01, "Personal autofill must use 81% of the surrounding pen width")
            }
        }
        note.drawingData = PKDrawing(strokes: original.strokes + [stroke(1110, 115)]).dataRepresentation()
        precondition(!before.permitsAppending(AutofillDocument(note), outside: selection(110)), "Writing inside captured content invalidates the request")
        note.drawingData = PKDrawing(strokes: Array(original.strokes.dropFirst())).dataRepresentation()
        precondition(!before.permitsAppending(AutofillDocument(note), outside: selection(110)), "Erasing captured ink must refuse a rebase")
        var movedOriginal = original.strokes
        movedOriginal[0].transform = CGAffineTransform(translationX: 10, y: 0)
        note.drawingData = PKDrawing(strokes: movedOriginal).dataRepresentation()
        precondition(!before.permitsAppending(AutofillDocument(note), outside: selection(110)), "Moving original ink must refuse a rebase")
        before.apply(to: note)
        try context.save()
        print("Concurrent ink: append/reflow retention, changed-selection/erase/move rejection and lighter autofill pen weight passed")

        let proposal = AutofillProposal(requestID: UUID(), noteID: note.id, capturedAt: .now,
            selectionPolygon: selection(110), selectedText: "Heading:", sourceRevision: "test-revision",
            content: AutofillContent(lines: [.init(text: "abba abba", citationIndices: []), .init(text: "ba", citationIndices: [])], origin: .localArithmetic), citations: [])
        let after = try before.inserting(staged, proposal: proposal)
        precondition(before.matches(AutofillDocument(note)))
        try NotebookEdits.commit(in: context, notes: [note]) { after.apply(to: note) }
        precondition(after.matches(AutofillDocument(note)) && !before.matches(AutofillDocument(note)))
        let records = try JSONDecoder().decode([AutofillRecord].self, from: note.autofillHistory!)
        precondition(records.count == 1)
        let storedRecords = try JSONSerialization.jsonObject(with: note.autofillHistory!) as! [[String: Any]]
        precondition(storedRecords.allSatisfy { Set($0.keys) == ["strokeIDs"] },
                     "Accepted fills must not persist selected text, answers or source excerpts")
        precondition(records[0].strokeIDs.count == staged.inserted.strokes.count)
        try NotebookEdits.commit(in: context, notes: [note]) { before.apply(to: note) }
        precondition(before.matches(AutofillDocument(note)), "Undo restores original pages, ink and provenance")
        try NotebookEdits.commit(in: context, notes: [note]) { after.apply(to: note) }
        do {
            try NotebookEdits.commit(in: context, notes: [note]) { before.apply(to: note); throw Injected.failure }
            preconditionFailure("Injected failure should roll back")
        } catch Injected.failure { }
        precondition(after.matches(AutofillDocument(note)), "Rollback must retain accepted provenance too")
        let reopened = try ModelContainer(for: Note.self, TrashedPage.self, configurations: ModelConfiguration(url: storeURL))
        let reopenedNote = try reopened.mainContext.fetch(FetchDescriptor<Note>()).first!
        precondition(after.matches(AutofillDocument(reopenedNote)))
        let source = LectureHandwriting.drawing(pages: [["Lexical analysis: groups characters into tokens.", "Parsing:", "Type checking:"]])
        let circle = [CGPoint(x: 1060, y: 130), CGPoint(x: 1850, y: 130), CGPoint(x: 1850, y: 228), CGPoint(x: 1060, y: 228)]
        let text = "groups tokens into a syntax tree"
        let inline = try AutofillLayout.stage(text: text, drawing: source, selection: circle, pageCount: 1, samples: [:],
            selectedText: "Lexical analysis: groups characters into tokens.\nParsing:", target: "Parsing:")
        let rows = AutofillTypography.rows(source.strokes)
        precondition(inline.lines[0].frame.minX > rows[1].bounds.maxX, "Start after the target colon")
        precondition(abs(inline.lines[0].frame.minY - rows[1].bounds.minY) < 1, "Share the target row")
        precondition(inline.letterHeight < 35 && inline.letterHeight > 15, "Match note size")
        let wrapped = try AutofillLayout.stage(text: String(repeating: text + " ", count: 12), drawing: source,
            selection: circle, pageCount: 1, samples: [:], selectedText: "Lexical analysis: groups characters into tokens.\nParsing:", target: "Parsing:")
        precondition(wrapped.lines.count > 1 && wrapped.lines[0].frame.minX == inline.lines[0].frame.minX)
        precondition(wrapped.lines.dropFirst().allSatisfy { $0.frame.minX == rows[1].bounds.minX },
                     "Wrapped lines return to the heading's left edge")
        for line in wrapped.lines { precondition(line.frame.maxX <= PageGeometry.pageOriginX + PageGeometry.pageWidth - AutofillLayout.margin + 0.01) }
        let lastOriginalRow = rows[2]
        let firstMoved = wrapped.existing.strokes.first { lastOriginalRow.strokes.map(\.id).contains($0.id) }!
        precondition(firstMoved.renderBounds.minY > wrapped.bounds.maxY, "Later rows must clear wrapped definitions")
        let comparison = "Precedence vs associativity:"
        let comparisonInk = LectureHandwriting.drawing(pages: [[comparison]])
        let headingBounds = comparisonInk.bounds
        let headingCircle = [CGPoint(x: headingBounds.minX - 10, y: headingBounds.minY - 10),
            CGPoint(x: headingBounds.maxX + 10, y: headingBounds.minY - 10),
            CGPoint(x: headingBounds.maxX + 10, y: headingBounds.maxY + 10),
            CGPoint(x: headingBounds.minX - 10, y: headingBounds.maxY + 10)]
        let definition = "Precedence determines which operators bind more tightly: multiplication typically binds more tightly than addition.\nAssociativity resolves grouping among operators of the same precedence. Left-associative subtraction groups a - b - c as (a - b) - c."
        let fullWidth = try AutofillLayout.stage(text: definition, drawing: comparisonInk, selection: headingCircle,
            pageCount: 1, samples: [:], selectedText: comparison)
        let rightMargin = PageGeometry.pageOriginX + PageGeometry.pageWidth - AutofillLayout.margin
        precondition(fullWidth.lines[0].frame.minX > headingBounds.maxX)
        precondition(fullWidth.lines.dropFirst().allSatisfy { $0.frame.minX == headingBounds.minX })
        precondition(fullWidth.lines.dropFirst().contains { $0.frame.width > rightMargin - fullWidth.lines[0].frame.minX },
                     "Continuations must use the newly available width, not merely shift a narrow column left")
        precondition(fullWidth.lines.map(\.text).joined(separator: " ") == definition.replacingOccurrences(of: "\n", with: " "))
        let crossingInk = stroke(headingBounds.minX, headingBounds.maxY - 5, 60, 160)
        let aroundDiagram = try AutofillLayout.stage(text: definition,
            drawing: PKDrawing(strokes: comparisonInk.strokes + [crossingInk]), selection: headingCircle,
            pageCount: 1, samples: [:], selectedText: comparison)
        precondition(aroundDiagram.lines[1].frame.minY > crossingInk.renderBounds.maxY,
                     "Full-width continuation must clear intact ink crossing the heading row")
        // The same rule survives a page break and explicit paragraph boundary.
        let offset = CGAffineTransform(translationX: 0, y: 1_070)
        let nearPageEnd = PKDrawing(strokes: comparisonInk.strokes.map { original in
            var copy = original; copy.transform = copy.transform.concatenating(offset); return copy
        })
        let acrossPages = try AutofillLayout.stage(text: definition, drawing: nearPageEnd,
            selection: headingCircle.map { $0.applying(offset) }, pageCount: 1, samples: [:], selectedText: comparison)
        precondition(acrossPages.pageCount > 1)
        precondition(acrossPages.lines.dropFirst().allSatisfy { $0.frame.minX == headingBounds.minX })
        for line in acrossPages.lines {
            let page = NotebookPaging.rect(for: Int(line.frame.minY / NotebookPaging.pageStride))
            precondition(page.insetBy(dx: AutofillLayout.margin, dy: AutofillLayout.margin).contains(line.frame))
        }
        let longWord = "pneumonoultramicroscopicsilicovolcanoconiosis"
        let wholeWord = try AutofillLayout.stage(text: longWord, drawing: comparisonInk, selection: headingCircle,
            pageCount: 1, samples: [:], selectedText: comparison)
        precondition(wholeWord.lines.count == 1 && wholeWord.lines[0].text == longWord)
        precondition(wholeWord.lines[0].frame.minX == headingBounds.minX && wholeWord.lines[0].frame.minY > headingBounds.maxY,
                     "A word too wide for the inline slot should move intact below the heading")
        let crowded = PKDrawing(strokes: source.strokes + [stroke(rows[1].bounds.maxX + 50, rows[1].bounds.minY, 100, 15)])
        precondition(AutofillTypography.anchor(drawing: crowded, selection: circle, selectedText: "Parsing:", target: "Parsing:") == nil)
        let attached = stroke(100, 60, 150, 30)
        precondition(!HandwritingSampler.isIsolated(strokes: [attached], bounds: CGRect(x: 99, y: 59, width: 40, height: 40), all: [attached]), "Never cut connected handwriting")
        let omittedDot = stroke(110, 62, 2, 2)
        precondition(!HandwritingSampler.isIsolated(strokes: [attached], bounds: CGRect(x: 95, y: 55, width: 170, height: 50), all: [attached, omittedDot]), "Don't omit a dot/accent")
        for key in ["A", "P", "é", "α", "→", "≤", "“"] { precondition(HandwrittenFont.sample(key) != nil, "Preserve supported Unicode symbols: \(key)") }
        let doubled = PKDrawing(strokes: source.strokes.map { original in
            var copy = original
            copy.transform = copy.transform.concatenating(CGAffineTransform(translationX: -1000, y: 0))
                .concatenating(CGAffineTransform(scaleX: 1, y: 2)).concatenating(CGAffineTransform(translationX: 1000, y: 0))
            return copy
        })
        let doubleRows = AutofillTypography.rows(doubled.strokes)
        precondition(abs(AutofillTypography.style(doubleRows[1], neighbors: doubleRows).height / AutofillTypography.style(rows[1], neighbors: rows).height - 2) < 0.15)
        print("Autofill checks passed: sampled/fallback composition, Unicode, no connected-stroke cutting, matching size, inline colon placement, wrap/reflow/gutters, revisions, atomic save/undo/redo, rollback and reopen")
    }
}
