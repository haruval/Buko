import CryptoKit
import Foundation
import PencilKit

/// A content revision includes ink, page identities and accepted-fill provenance.
/// Camera position and rename timestamps deliberately don't invalidate content.
nonisolated struct AutofillDocument {
    let noteID: UUID
    let ink: Data
    let pages: Data
    let pageCount: Int
    let layoutVersion: Int
    let history: Data

    @MainActor init(_ note: Note) {
        noteID = note.id; ink = note.drawingData; pages = note.pageMetadata
        pageCount = note.pageCount; layoutVersion = note.pageLayoutVersion
        let saved = note.autofillHistory ?? Data()
        // Never put legacy prose back into Undo snapshots. Malformed provenance
        // remains fail-closed and is reported by the startup migration.
        history = (try? AutofillRecord.minimized(saved)) ?? saved
    }

    init(noteID: UUID, ink: Data, pages: Data, pageCount: Int, layoutVersion: Int, history: Data) {
        self.noteID = noteID; self.ink = ink; self.pages = pages; self.pageCount = pageCount
        self.layoutVersion = layoutVersion; self.history = history
    }

    var revision: String {
        var hash = SHA256()
        hash.update(data: ink); hash.update(data: pages); hash.update(data: history)
        hash.update(data: Data("\(noteID):\(pageCount):\(layoutVersion)".utf8))
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func matches(_ other: Self) -> Bool {
        guard noteID == other.noteID, pages == other.pages, pageCount == other.pageCount,
              layoutVersion == other.layoutVersion, history == other.history else { return false }
        if ink == other.ink { return true }
        // PencilKit may reserialize an equivalent drawing during undo/appearance updates.
        guard let a = try? Self.drawing(ink), let b = try? Self.drawing(other.ink) else { return false }
        return Self.sameInk(a, b)
    }

    /// PKDrawing equality includes internal drawing identity. Compare the actual
    /// stroke content when PencilKit recreates that container during undo/recolor.
    static func sameInk(_ a: PKDrawing, _ b: PKDrawing) -> Bool {
        guard a.strokes.count == b.strokes.count else { return false }
        return zip(a.strokes, b.strokes).allSatisfy { a, b in
            guard a.transform == b.transform, a.mask == b.mask, a.randomSeed == b.randomSeed,
                  a.ink.inkType == b.ink.inkType, MonochromeInk.matches(a.ink.color, b.ink.color),
                  a.path.count == b.path.count, a.path.creationDate == b.path.creationDate else { return false }
            if #available(iOS 27, macOS 27, *) {
                guard a.id == b.id, a.renderGroupID == b.renderGroupID, a.renderState == b.renderState else { return false }
            }
            return zip(a.path, b.path).allSatisfy { p, q in
                guard p.location == q.location, p.size == q.size, p.timeOffset == q.timeOffset,
                      p.force == q.force, p.opacity == q.opacity, p.azimuth == q.azimuth,
                      p.altitude == q.altitude, p.secondaryScale == q.secondaryScale,
                      p.threshold == q.threshold else { return false }
                if #available(iOS 27, macOS 27, *) { return p.lateralJitter == q.lateralJitter }
                return true
            }
        }
    }

    static func drawing(_ data: Data) throws -> PKDrawing { data.isEmpty ? PKDrawing() : try PKDrawing(data: data) }

    @MainActor func apply(to note: Note) {
        note.drawingData = ink; note.pageMetadata = pages; note.pageCount = pageCount
        note.pageLayoutVersion = layoutVersion; note.autofillHistory = history
        note.currentPageIndex = min(note.currentPageIndex, max(0, pageCount - 1))
        note.updatedAt = .now
    }

    @available(iOS 27, macOS 27, *)
    func inserting(_ result: AutofillLayout.Result, proposal: AutofillProposal) throws -> Self {
        var manifest = try JSONDecoder().decode([NotebookPage].self, from: pages)
        guard manifest.filter({ !$0.isTrashed }).count == pageCount, result.pageCount >= pageCount,
              proposal.noteID == noteID, result.missing.isEmpty else { throw AutofillEditError.stale }
        manifest += (pageCount..<result.pageCount).map { _ in NotebookPage() }
        var records = history.isEmpty ? [] : try JSONDecoder().decode([AutofillRecord].self, from: history)
        records.append(AutofillRecord(strokeIDs: result.inserted.strokes.map(\.id)))
        return Self(noteID: noteID, ink: result.drawing.dataRepresentation(),
                    pages: try JSONEncoder().encode(manifest), pageCount: result.pageCount,
                    layoutVersion: layoutVersion, history: try JSONEncoder().encode(records))
    }
}

nonisolated enum AutofillEditError: LocalizedError, Equatable {
    case stale, unavailable, sourcesChanged
    var errorDescription: String? {
        switch self {
        case .stale: "This note changed after the preview was prepared. Circle the text again."
        case .unavailable: "The note couldn’t be saved. Your original ink is unchanged; try again."
        case .sourcesChanged: "The lecture sources changed. Circle the text again before inserting."
        }
    }
}
