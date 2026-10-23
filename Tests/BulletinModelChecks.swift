import Foundation
import FoundationModels
import CoreGraphics

@main struct BulletinModelChecks {
    static func main() async throws {
        guard #available(macOS 27, *), case .available = SystemLanguageModel.default.availability else {
            print("Local model unavailable"); exit(77)
        }
        let source = BulletinSource(noteID: UUID(), noteTitle: "Lecture", pageID: UUID(), pageIndex: 0,
            bounds: CGRect(x: 0, y: 0, width: 600, height: 140), strokeIDs: [],
            capturedAt: ISO8601DateFormatter().date(from: "2026-10-23T23:30:00Z")!, timeZoneID: "America/Denver")
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: source.timeZoneID)!
        let cases: [(String, String)] = [
            ("The exam is in 12 days. Review recursion later today.", "This week we studied closures."),
            ("A closure retains access to its lexical environment.", "Read chapter 8 tomorrow."),
            ("The exam on November 4, 2026 was cancelled. No review session is scheduled.", ""),
            ("Email Professor Chen tomorrow at 2 pm about the project proposal.", "")
        ]
        for (index, input) in cases.enumerated() {
            let items = try await BulletinExtractor.extract(selected: input.0, context: input.1, source: source, observe: { extraction in
                FileHandle.standardOutput.write(Data("RAW: \(extraction)\n".utf8))
            }, observeDate: { plan in
                FileHandle.standardOutput.write(Data("DATE: \(plan)\n".utf8))
            })
            print("CASE \(index): \(items.map { "\($0.kind.rawValue):\($0.title)|\($0.quote)|\($0.date?.description ?? "undated")" })")
            switch index {
            case 0:
                guard items.count == 2,
                      let exam = items.first(where: { $0.kind == .event }), let examDate = exam.date,
                      calendar.component(.day, from: examDate) == 4, calendar.component(.month, from: examDate) == 11,
                      let action = items.first(where: { $0.kind == .action }), let date = action.date,
                      calendar.isDate(date, inSameDayAs: source.capturedAt), !action.dateHasTime else { fatalError("Relative dates/actions mismatch") }
            case 1:
                guard items.count == 1, items[0].kind == .information, items[0].date == nil else { fatalError("Nearby task leaked into extraction") }
            case 2:
                guard !items.contains(where: { $0.kind == .action }),
                      items.allSatisfy({ $0.title.lowercased().contains("cancel") || $0.title.lowercased().contains("no ") }) else { fatalError("Negation lost") }
            default:
                guard items.count == 1, items[0].kind == .action, let date = items[0].date,
                      calendar.component(.day, from: date) == 24, calendar.component(.hour, from: date) == 14,
                      items[0].dateHasTime else { fatalError("Explicit local time mismatch") }
            }
        }
        print("PASS: 4 live on-device-model development cases")
    }
}
