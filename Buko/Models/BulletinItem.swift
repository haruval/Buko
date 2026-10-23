import Foundation
import CoreGraphics
import SwiftData

@Model
final class BulletinItem {
    var id: UUID
    var title: String
    var kind: String
    var dueDate: Date?
    var dateHasTime: Bool
    var completedAt: Date?
    var capturedAt: Date
    var timeZoneID: String
    var noteID: UUID
    var noteTitle: String
    var pageID: UUID
    var pageIndex: Int
    var sourceText: String
    var sourceX: Double
    var sourceY: Double
    var sourceWidth: Double
    var sourceHeight: Double
    var sourceStrokeIDs: Data
    var captureID: UUID

    init(draft: BulletinDraft, source: BulletinSource) {
        id = UUID(); title = draft.title; kind = draft.kind.rawValue
        dueDate = draft.date; dateHasTime = draft.dateHasTime; completedAt = nil
        capturedAt = source.capturedAt; timeZoneID = source.timeZoneID
        noteID = source.noteID; noteTitle = source.noteTitle; pageID = source.pageID; pageIndex = source.pageIndex
        sourceText = draft.quote
        sourceX = source.bounds.minX; sourceY = source.bounds.minY
        sourceWidth = source.bounds.width; sourceHeight = source.bounds.height
        sourceStrokeIDs = (try? JSONEncoder().encode(source.strokeIDs)) ?? Data()
        captureID = source.id
    }
}

nonisolated enum BulletinKind: String, Codable, CaseIterable, Sendable {
    case action, event, information
    var label: String { switch self { case .action: "Action"; case .event: "Event"; case .information: "Information" } }
    var symbol: String { switch self { case .action: "checkmark.circle"; case .event: "calendar"; case .information: "pin" } }
}

nonisolated struct BulletinDraft: Identifiable, Sendable {
    var id = UUID()
    var title: String
    var kind: BulletinKind
    var quote: String
    var date: Date?
    var dateHasTime: Bool
    var included = true
}

nonisolated struct BulletinSource: Identifiable, Sendable {
    var id = UUID()
    var noteID: UUID
    var noteTitle: String
    var pageID: UUID
    var pageIndex: Int
    /// Page-relative document coordinates; stable across page reordering.
    var bounds: CGRect
    var strokeIDs: [String]
    var capturedAt: Date
    var timeZoneID: String
}

nonisolated enum BulletinDates {
    /// Calendar arithmetic preserves the captured local day across DST changes.
    static func resolve(dayOffset: Int?, calendarDate: String, time: String,
                        capturedAt: Date, timeZoneID: String) throws -> Date? {
        guard let zone = TimeZone(identifier: timeZoneID) else { throw BulletinError.invalidDate }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        guard dayOffset != nil || !calendarDate.isEmpty else {
            guard time.isEmpty else { throw BulletinError.invalidDate }
            return nil
        }
        guard dayOffset == nil || calendarDate.isEmpty else { throw BulletinError.invalidDate }
        let base: Date
        if let offset = dayOffset {
            guard (-3660...3660).contains(offset),
                  let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: capturedAt)) else {
                throw BulletinError.invalidDate
            }
            base = date
        } else {
            let parts = calendarDate.split(separator: "-", omittingEmptySubsequences: false).compactMap { Int($0) }
            guard calendarDate.count == 10, parts.count == 3,
                  calendarDate == String(format: "%04d-%02d-%02d", parts[0], parts[1], parts[2]),
                  (1900...2200).contains(parts[0]), (1...12).contains(parts[1]), (1...31).contains(parts[2]),
                  let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
                  calendar.component(.year, from: date) == parts[0], calendar.component(.month, from: date) == parts[1],
                  calendar.component(.day, from: date) == parts[2] else { throw BulletinError.invalidDate }
            base = date
        }
        guard !time.isEmpty else { return base }
        let parts = time.split(separator: ":", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard time.count == 5, parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]),
              let result = calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: base),
              calendar.isDate(result, inSameDayAs: base), calendar.component(.hour, from: result) == parts[0],
              calendar.component(.minute, from: result) == parts[1] else { throw BulletinError.invalidDate }
        return result
    }
}

nonisolated enum BulletinError: LocalizedError {
    case invalidDate, invalidEvidence, tooLarge, stale
    var errorDescription: String? {
        switch self {
        case .invalidDate: "The date wasn’t clear enough to save. Try selecting a clearer date with the item."
        case .invalidEvidence: "The extracted item couldn’t be matched to the selected handwriting. Try a smaller band."
        case .tooLarge: "Select a few handwritten lines on one page at a time."
        case .stale: "The source note changed. Select the band again before adding these items."
        }
    }
}
