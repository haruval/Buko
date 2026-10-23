import Foundation
import PencilKit

@MainActor enum PreparedHandwritingChecks {
    private actor Builds {
        var count = 0
        func record() { count += 1 }
    }
    static func run(root: URL, sample: HandwritingSample) async throws {
        let directory = root.appendingPathComponent("handwriting-cache")
        let profile = PreparedHandwriting(samples: ["a": sample, "tokens": sample],
            headings: [.init(text: "Parsing:", bounds: CGRect(x: 1070, y: 180, width: 120, height: 30))])
        let builds = Builds()
        let cache = HandwritingCache(directory: directory) { _ in await builds.record(); return profile }
        let note = Note(title: "Preparation fixture")
        note.drawingData = sample.drawingData
        let document = AutofillDocument(note)
        _ = try await cache.prepared(for: document)
        _ = try await cache.prepared(for: document)
        let count = await builds.count
        precondition(count == 1, "Unchanged ink must reuse the persisted cache")
        let reopened = HandwritingCache(directory: directory) { _ in preconditionFailure("Relaunch must not recognize unchanged ink") }
        let loaded = try await reopened.prepared(for: document)
        precondition(loaded.samples["a"]?.drawingData == sample.drawingData)
        note.title = "Renamed"; note.updatedAt = .now
        _ = try await reopened.prepared(for: AutofillDocument(note))
        let headings = HandwritingSampler.headings(in: "Lexical analysis: groups characters into tokens. Parsing: static scope:")
        precondition(headings.contains("Parsing:") && headings.contains("static scope:"))
        let selection = [CGPoint(x: 1060, y: 170), CGPoint(x: 1260, y: 170), CGPoint(x: 1260, y: 225), CGPoint(x: 1060, y: 225)]
        let proposal = AutofillProposal(requestID: UUID(), noteID: note.id, capturedAt: .now,
            selectionPolygon: selection, selectedText: "Parsing:", sourceRevision: "test",
            content: AutofillContent(lines: [.init(text: "a tokens", citationIndices: [])], origin: .lectureDraft),
            citations: [], insertionTarget: "Parsing:")
        let preparation = HandwritingPreparation(cache: cache, idleDelay: .milliseconds(1))
        preparation.update(notes: [note], preferredID: note.id)
        for _ in 0..<200 {
            if preparation.prepared(for: proposal).samples["a"] != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let ready = preparation.prepared(for: proposal)
        precondition(ready.samples.count == 2 && ready.targetBounds == profile.headings[0].bounds)
        for _ in 0..<20 { precondition(preparation.prepared(for: proposal).samples.count == 2) }
        let reusedCount = await builds.count
        precondition(reusedCount == 1, "Reading ready samples for any number of previews must never invoke recognition")
        let inspected = preparation.inspection(preferredID: note.id)
        precondition(inspected["a"]?.sample.drawingData == sample.drawingData && inspected["a"]?.source == "Renamed")
        precondition(inspected["z"] == nil, "The inspector must distinguish missing letters from prepared ink")
        preparation.rebuild()
        precondition(preparation.prepared(for: proposal).samples.isEmpty && preparation.status.isRebuilding)
        for _ in 0..<200 {
            if !preparation.status.isRebuilding { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let rebuiltCount = await builds.count
        precondition(rebuiltCount == 2 && !preparation.status.isRebuilding,
            "Manual rebuild must rerun preparation even when source ink is unchanged")
        precondition(preparation.inspection(preferredID: note.id)["a"] != nil)
        preparation.setPaused(true)
        preparation.invalidate(noteID: note.id)
        note.drawingData = Data(); note.updatedAt = .now
        preparation.update(notes: [note], preferredID: note.id)
        precondition(preparation.prepared(for: proposal).samples.isEmpty, "Edits invalidate old samples immediately")
        try await Task.sleep(for: .milliseconds(40))
        let pausedCount = await builds.count
        precondition(pausedCount == 2, "Drawing/background/autofill must pause preparation")
        preparation.setPaused(false)
        for _ in 0..<200 {
            if preparation.prepared(for: proposal).samples["a"] != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let updatedCount = await builds.count
        precondition(updatedCount == 3, "Changed ink must rebuild during idle time")
        note.autofillHistory = Data("changed provenance".utf8)
        _ = try await cache.prepared(for: AutofillDocument(note))
        let historyCount = await builds.count
        precondition(historyCount == 4, "Generated-ink exclusions belong in the cache identity")
        note.deletedAt = .now
        preparation.update(notes: [note], preferredID: note.id)
        precondition(preparation.prepared(for: proposal).samples.isEmpty)
        await cache.prune(keeping: [])
        precondition((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) == [])
        let delayed = HandwritingCache(directory: directory) { _ in
            try? await Task.sleep(for: .milliseconds(80)) // Deliberately ignores cancellation like an OS recognizer may.
            return profile
        }
        let cancelled = Task { try await delayed.prepared(for: document) }
        try await Task.sleep(for: .milliseconds(10)); cancelled.cancel()
        do { _ = try await cancelled.value; preconditionFailure("Cancelled work must not publish") }
        catch is CancellationError { }
        precondition((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) == [])
        let file = directory.appendingPathComponent(document.noteID.uuidString + ".json")
        try Data("broken cache".utf8).write(to: file)
        _ = try await cache.prepared(for: document)
        let repairedCount = await builds.count
        precondition(repairedCount == 5, "A corrupt derivative should rebuild without affecting the source")
        precondition(document.ink == sample.drawingData)
        print("Prepared handwriting checks passed: persisted reuse, revision/provenance invalidation, idle pause/resume, immediate lookups, deletion, cancellation, corrupt-cache repair and unchanged source ink")
    }
}
