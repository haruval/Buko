import Foundation
import CoreGraphics
import SwiftData
import PencilKit

@main
struct BulletinLibraryChecks {
    @MainActor static func main() throws {
        if CommandLine.arguments.count > 2 {
            let url = URL(fileURLWithPath: CommandLine.arguments[2])
            let schema = Schema([Note.self, TrashedPage.self, NoteFolder.self, BulletinItem.self])
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let context = container.mainContext
            let legacy = try context.fetch(FetchDescriptor<Note>()).first!
            precondition(legacy.title == "Legacy" && legacy.pageCount == 3 && legacy.folderID == nil)
            let drawing = try PKDrawing(data: legacy.drawingData)
            precondition(drawing.strokes.count == 3)
            try NotebookEdits.commit(in: context, notes: [legacy]) { try NotebookEdits.prepare(legacy) }
            precondition(legacy.activePages.count == 3)
            print("PASS: real on-disk legacy migration with folder and bulletin schema; existing ink and pages retained")
        }
        try dates()
        geometry()
        try evidence()
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let schema = Schema([Note.self, TrashedPage.self, NoteFolder.self, BulletinItem.self])
        let configuration = ModelConfiguration(schema: schema, url: root.appendingPathComponent("library.store"))
        let aID: UUID, bID: UUID, itemID: UUID
        do {
            let container = try ModelContainer(for: schema, configurations: configuration)
            let context = ModelContext(container); context.autosaveEnabled = false
            let a = Note(title: "Algorithms"), b = Note(title: "Networks"), c = Note(title: "Review")
            a.drawingData = Data([1, 2, 3]); b.drawingData = Data([4, 5]); aID = a.id; bID = b.id
            [a, b, c].forEach { context.insert($0) }; try context.save()
            try LibraryOrganization.group(a, with: b, in: context)
            let folder = try context.fetch(FetchDescriptor<NoteFolder>()).first!
            precondition(a.folderID == folder.id && b.folderID == folder.id)
            try LibraryOrganization.group(a, with: a, in: context)
            let folderCount = try context.fetchCount(FetchDescriptor<NoteFolder>())
            precondition(folderCount == 1)
            try LibraryOrganization.move(c, to: folder, in: context)
            try LibraryOrganization.rename(folder, to: "  Semester  ", in: context)
            precondition(folder.title == "Semester")
            b.deletedAt = .now; try context.save()
            try LibraryOrganization.ungroup(folder, in: context)
            precondition([a, b, c].allSatisfy { $0.folderID == nil })
            precondition(a.drawingData == Data([1, 2, 3]) && b.drawingData == Data([4, 5]))
            precondition(b.deletedAt != nil)
            enum Expected: Error { case stop }
            do {
                try NotebookEdits.commit(in: context, notes: [a]) {
                    a.folderID = UUID(); throw Expected.stop
                }
            } catch Expected.stop { }
            precondition(a.folderID == nil && a.drawingData == Data([1, 2, 3]))
            try LibraryOrganization.group(c, with: a, in: context)
            let source = fixtureSource(noteID: a.id)
            let item = BulletinItem(draft: BulletinDraft(title: "Review recursion", kind: .action,
                quote: "review later today", date: source.capturedAt, dateHasTime: false), source: source)
            itemID = item.id
            context.insert(item); try context.save()
            item.completedAt = .now; try context.save()
        }
        do {
            let container = try ModelContainer(for: schema, configurations: configuration)
            let context = ModelContext(container)
            let notes = try context.fetch(FetchDescriptor<Note>())
            precondition(notes.first { $0.id == aID }!.folderID != nil)
            precondition(notes.first { $0.id == bID }!.deletedAt != nil)
            let item = try context.fetch(FetchDescriptor<BulletinItem>()).first!
            precondition(item.id == itemID && item.completedAt != nil && item.noteID == aID)
            precondition(item.sourceText == "review later today" && item.timeZoneID == "America/Denver")
        }
        print("PASS: folders create/move/rename/ungroup, rollback, ink preservation, and bulletin source/completion persistence")
    }

    static func fixtureSource(noteID: UUID = UUID()) -> BulletinSource {
        BulletinSource(noteID: noteID, noteTitle: "Lecture", pageID: UUID(), pageIndex: 0,
                       bounds: CGRect(x: 50, y: 80, width: 500, height: 100), strokeIDs: [],
                       capturedAt: ISO8601DateFormatter().date(from: "2026-10-23T23:30:00Z")!, timeZoneID: "America/Denver")
    }

    static func dates() throws {
        let zone = "America/Denver"
        let capture = ISO8601DateFormatter().date(from: "2026-10-23T23:30:00Z")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: zone)!
        let exam = try BulletinDates.resolve(dayOffset: 12, calendarDate: "", time: "", capturedAt: capture, timeZoneID: zone)!
        precondition(cal.component(.month, from: exam) == 11 && cal.component(.day, from: exam) == 4)
        precondition(cal.component(.hour, from: exam) == 0)
        // The interval crosses fall-back; adding 12 * 86400 seconds would be wrong.
        precondition(exam.timeIntervalSince(cal.startOfDay(for: capture)) == 12 * 86400 + 3600)
        let today = try BulletinDates.resolve(dayOffset: 0, calendarDate: "", time: "", capturedAt: capture, timeZoneID: zone)!
        precondition(cal.isDate(today, inSameDayAs: capture))
        let timed = try BulletinDates.resolve(dayOffset: 1, calendarDate: "", time: "14:30", capturedAt: capture, timeZoneID: zone)!
        precondition(cal.component(.hour, from: timed) == 14 && cal.component(.minute, from: timed) == 30)
        let none = try BulletinDates.resolve(dayOffset: nil, calendarDate: "", time: "", capturedAt: capture, timeZoneID: zone)
        precondition(none == nil)
        for (offset, date, time) in [(Int?.none, "2026-02-30", ""), (Int?.some(Int.min), "", ""), (nil, "2026-03-08", "02:30"), (0, "2026-10-24", "")] {
            do {
                _ = try BulletinDates.resolve(dayOffset: offset, calendarDate: date, time: time, capturedAt: capture, timeZoneID: zone)
                preconditionFailure("Invalid date accepted")
            } catch BulletinError.invalidDate { }
        }
        print("PASS: relative dates, local day, DST, explicit time, malformed/ambiguous date rejection")
    }

    static func geometry() {
        let start = [CGPoint(x: 100, y: 200), CGPoint(x: 100, y: 300)]
        let end = [CGPoint(x: 300, y: 200), CGPoint(x: 300, y: 300)]
        let points = (0...10).map { CGPoint(x: 100 + $0 * 20, y: 250) }
        precondition(BandGeometry.canStart(points: points, initial: start, current: end))
        precondition(BandGeometry.rect(initial: start, current: end) == CGRect(x: 100, y: 200, width: 200, height: 100))
        precondition(BandGeometry.canStart(points: Array(points.reversed()), initial: end, current: start))
        precondition(!BandGeometry.canStart(points: (0...10).map { CGPoint(x: 100, y: 250 + $0 * 20) }, initial: start, current: end))
        precondition(!BandGeometry.remainsHorizontal(initial: start, current: [CGPoint(x: 300, y: 175), CGPoint(x: 300, y: 325)]))
        precondition(!BandGeometry.canStart(points: points, initial: [CGPoint(x: 100, y: 200), CGPoint(x: 200, y: 200)], current: end))
        precondition(!BandGeometry.canStart(points: Array(points.prefix(2)), initial: start, current: start))
        print("PASS: both sweep directions and geometry; vertical, pinch, horizontal finger pair and short-path rejection")
    }

    static func evidence() throws {
        let source = fixtureSource()
        let item = ExtractedBulletinItem(title: "Exam", kind: .event, quote: "exam in 12 days", dateQuote: "in 12 days")
        let drafts = try BulletinExtractor.validate(ExtractedBulletin(items: [item]), selected: "exam in 12 days", source: source)
        precondition(drafts.count == 1 && drafts[0].kind == .event && drafts[0].date == nil && !drafts[0].dateHasTime)
        do {
            _ = try BulletinExtractor.validate(ExtractedBulletin(items: [item]), selected: "review recursion", source: source)
            preconditionFailure("Unselected evidence accepted")
        } catch BulletinError.invalidEvidence { }
        let relative = BulletinDateInterpretation(anchor: .relativeQuantity, quantityQuote: "12", unit: .days, direction: .afterCapture,
            impliedDayOffset: 0, calendarDate: "", timeQuote: "")
        let (resolved, timed) = try BulletinDateInterpreter.validate(relative, phrase: "in 12 days", source: source)
        precondition(resolved != nil && !timed)
        var inventedTime = relative; inventedTime.quantityQuote = ""; inventedTime.timeQuote = "later today"; inventedTime.anchor = .relativeDay
        do {
            _ = try BulletinDateInterpreter.validate(inventedTime, phrase: "later today", source: source)
            preconditionFailure("Invented clock time accepted")
        } catch BulletinError.invalidDate { }
        var wrongNumber = relative; wrongNumber.quantityQuote = "2"
        // Exact number tokens, not substring digits, must anchor quantities.
        do {
            _ = try BulletinDateInterpreter.validate(wrongNumber, phrase: "in 12 days", source: source)
            preconditionFailure("Substring number accepted")
        } catch BulletinError.invalidDate { }
        print("PASS: exact selected evidence and date phrase membership validation")
    }
}
