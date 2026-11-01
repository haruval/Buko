import CryptoKit
import Foundation
import PencilKit
import Observation

/// Derived from a bounded snapshot of one note, independently of any autofill.
nonisolated struct PreparedHandwriting: Codable, Sendable {
    struct Heading: Codable, Sendable {
        let text: String
        let bounds: CGRect
    }
    var samples: [String: HandwritingSample] = [:]
    var headings: [Heading] = []

    func targetBounds(_ target: String?, selection: [CGPoint]) -> CGRect? {
        guard let target else { return nil }
        let region = CircleGeometry.path(selection).boundingBoxOfPath
        let matches = headings.filter {
            AutofillTypography.normalized($0.text) == AutofillTypography.normalized(target) && region.contains($0.bounds)
        }
        return matches.count == 1 ? matches[0].bounds : nil
    }
}

/// Regenerable, app-local derivatives. Source ink/provenance determines identity;
/// renaming or moving the camera never requires another recognition pass.
actor HandwritingCache {
    typealias Builder = @Sendable (AutofillDocument) async throws -> PreparedHandwriting
    private struct Envelope: Codable {
        let version: Int
        let revision: String
        let handwriting: PreparedHandwriting
    }
    private let directory: URL?
    private let build: Builder
    private static let byteLimit = 8_000_000

    init(directory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("BukoHandwriting", isDirectory: true),
         build: @escaping Builder = { document in
             guard #available(iOS 27, macOS 27, *) else { return PreparedHandwriting() }
             return try await HandwritingSampler().prepare(document: document)
         }) {
        self.directory = directory; self.build = build
    }

    func prepared(for document: AutofillDocument, ignoringCache: Bool = false) async throws -> PreparedHandwriting {
        try Task.checkCancellation()
        var hash = SHA256()
        hash.update(data: document.ink); hash.update(data: document.history)
        let revision = hash.finalize().map { String(format: "%02x", $0) }.joined()
        let url = directory?.appendingPathComponent(document.noteID.uuidString + ".json")
        if !ignoringCache, let url, let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= Self.byteLimit,
           let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(Envelope.self, from: data),
           saved.version == 2, saved.revision == revision, Self.valid(saved.handwriting) {
            try Task.checkCancellation()
            return saved.handwriting
        }
        let handwriting = try await build(document)
        try Task.checkCancellation()
        guard Self.valid(handwriting) else { return PreparedHandwriting() }
        if let directory, let url {
            // Failure to save derived data never prevents writing or previewing.
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(Envelope(version: 2, revision: revision, handwriting: handwriting))
                if data.count <= Self.byteLimit { try data.write(to: url, options: .atomic) }
            } catch { }
        }
        return handwriting
    }

    func prune(keeping ids: Set<UUID>) {
        guard !Task.isCancelled, let directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        let names = Set(ids.map { $0.uuidString + ".json" })
        for file in files where file.pathExtension == "json" && !names.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    func storedNoteIDs() throws -> Set<UUID> {
        guard let directory, FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return Set(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).compactMap { url in
            guard url.pathExtension == "json", let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  url.lastPathComponent == id.uuidString + ".json" else { return nil }
            return id
        })
    }

    func removeNotes(_ ids: Set<UUID>) throws {
        guard let directory else { return }
        for id in ids {
            let url = directory.appendingPathComponent(id.uuidString + ".json")
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }

    private static func valid(_ profile: PreparedHandwriting) -> Bool {
        guard profile.samples.count <= 224, profile.headings.count <= 128,
              profile.samples.values.reduce(0, { $0 + $1.drawingData.count }) <= byteLimit else { return false }
        for (key, sample) in profile.samples {
            guard !key.isEmpty, key.count <= 128,
                  let drawing = try? PKDrawing(data: sample.drawingData),
                  (try? HandwritingSample(drawing: drawing)) != nil else { return false }
        }
        return profile.headings.allSatisfy {
            !$0.text.isEmpty && $0.text.count <= 100 && !$0.bounds.isEmpty &&
            [$0.bounds.minX, $0.bounds.minY, $0.bounds.width, $0.bounds.height].allSatisfy(\.isFinite)
        }
    }
}

/// Only the inspector observes these coarse changes; ink input never publishes
/// preparation progress or thumbnail work through the canvas view hierarchy.
@Observable @MainActor final class HandwritingPreparationStatus {
    fileprivate(set) var revision = 0
    fileprivate(set) var message = "Waiting for notes"
    fileprivate(set) var isRebuilding = false
}

nonisolated struct HandwritingInspectionSample: Sendable {
    let sample: HandwritingSample
    let source: String
}

/// One workspace-owned scheduler. Nothing here observes or mutates live ink, and
/// autofill only reads completed profiles; it never starts or waits for this work.
@MainActor final class HandwritingPreparation {
    struct Stamp: Equatable {
        let id: UUID
        let updatedAt: Date
        init(_ note: Note) { id = note.id; updatedAt = note.updatedAt }
    }
    private struct Entry { let stamp: Stamp; let handwriting: PreparedHandwriting }
    let status = HandwritingPreparationStatus()
    private var resetRequested = false
    private let cache: HandwritingCache
    private let idleDelay: Duration
    let alphabet: PersonalAlphabetStore
    private var notes: [Note] = []
    private var stamps: [Stamp] = []
    private var entries: [UUID: Entry] = [:]
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var paused = false

    init(cache: HandwritingCache = HandwritingCache(), idleDelay: Duration = .seconds(2), alphabet: PersonalAlphabetStore? = nil) {
        self.cache = cache; self.idleDelay = idleDelay; self.alphabet = alphabet ?? PersonalAlphabetStore()
    }

    func update(notes all: [Note], preferredID: UUID?) {
        let active = all.filter { $0.deletedAt == nil }
        let preferred = active.first { $0.id == preferredID }
        let next = (preferred.map { [$0] } ?? []) + active.filter { $0.id != preferredID }
        let nextStamps = next.map(Stamp.init)
        guard stamps != nextStamps else { return }
        notes = next; stamps = nextStamps
        entries = entries.filter { nextStamps.contains($0.value.stamp) }
        status.revision += 1
        restart()
    }

    func setPaused(_ value: Bool) {
        guard paused != value else { return }
        paused = value
        restart()
    }

    func invalidate(noteID: UUID) {
        entries[noteID] = nil
        status.revision += 1
        // Called synchronously on edits, before SwiftUI delivers query changes.
        task?.cancel(); generation = UUID()
        stamps = []
    }

    func storedNoteIDs() async throws -> Set<UUID> { try await cache.storedNoteIDs() }

    func removeCaches(for ids: Set<UUID>) async throws {
        guard !ids.isEmpty else { return }
        for id in ids { invalidate(noteID: id) }
        try await cache.removeNotes(ids)
    }

    func rebuild() {
        entries.removeAll()
        resetRequested = true
        status.isRebuilding = true
        status.revision += 1
        restart()
    }

    func saveAlphabet(_ drawing: PKDrawing, letter: String) throws {
        try alphabet.save(drawing, for: letter)
        status.revision += 1
    }

    func inspection(preferredID: UUID?) -> [String: HandwritingInspectionSample] {
        var result: [String: HandwritingInspectionSample] = [:]
        let ids = preferredID.map { [$0] } ?? []
        for id in ids + stamps.map(\.id).filter({ $0 != preferredID }) {
            guard let entry = entries[id], let note = notes.first(where: { $0.id == id }),
                  note.deletedAt == nil, Stamp(note) == entry.stamp else { continue }
            for (key, sample) in entry.handwriting.samples where result[key] == nil {
                result[key] = HandwritingInspectionSample(sample: sample, source: note.title)
            }
        }
        for (key, sample) in alphabet.samples where result[key] == nil {
            result[key] = HandwritingInspectionSample(sample: sample, source: "Your alphabet")
        }
        return result
    }

    private func restart() {
        task?.cancel()
        let token = UUID(); generation = token
        let ids = Set(stamps.map(\.id)), cache = cache, delay = idleDelay
        status.message = notes.isEmpty ? "No active notes to sample" : paused ? "Paused · resumes when you’re idle" : "Waiting for an idle moment"
        task = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await cache.prune(keeping: self.resetRequested ? [] : ids)
            guard token == self.generation, !Task.isCancelled else { return }
            self.resetRequested = false
            guard !self.paused else { return }
            do {
                if !self.status.isRebuilding { try await Task.sleep(for: delay) }
                let pending = self.status.isRebuilding ? self.notes : Array(self.notes.prefix(4))
                for (index, note) in pending.enumerated() {
                    try Task.checkCancellation()
                    guard token == self.generation, note.deletedAt == nil else { return }
                    let stamp = Stamp(note)
                    if self.entries[note.id]?.stamp == stamp { continue }
                    self.status.message = "Preparing \(index + 1) of \(pending.count) · \(note.title)"
                    let document = AutofillDocument(note)
                    let handwriting = try await cache.prepared(for: document, ignoringCache: self.status.isRebuilding)
                    try Task.checkCancellation()
                    guard token == self.generation, note.deletedAt == nil, Stamp(note) == stamp else { return }
                    self.entries[note.id] = Entry(stamp: stamp, handwriting: handwriting)
                    // Scanning every note persists each derivative, but keeps
                    // only a bounded set of recent profiles resident on iPad.
                    var residentBytes = 0
                    for stamp in self.stamps {
                        guard let entry = self.entries[stamp.id] else { continue }
                        let bytes = entry.handwriting.samples.values.reduce(0) { $0 + $1.drawingData.count }
                        if residentBytes + bytes > 24_000_000 { self.entries[stamp.id] = nil }
                        else { residentBytes += bytes }
                    }
                    self.status.revision += 1
                }
                self.status.message = self.notes.isEmpty ? "No active notes to sample" : "Ready · \(self.entries.count) notes prepared"
                self.status.isRebuilding = false
            } catch {
                guard token == self.generation, !Task.isCancelled else { return }
                self.status.message = "Preparation couldn’t finish. Try rebuilding."
                self.status.isRebuilding = false
            }
        }
    }

    func prepared(for proposal: AutofillProposal) -> HandwritingSampler.Result {
        var result = HandwritingSampler.Result()
        let keys = Set(HandwritingSampler.words(in: proposal.text) + proposal.text.filter { !$0.isWhitespace }.map(String.init))
        let ids = [proposal.noteID] + stamps.map(\.id).filter { $0 != proposal.noteID }
        for id in ids {
            guard let entry = entries[id], let note = notes.first(where: { $0.id == id }),
                  note.deletedAt == nil, Stamp(note) == entry.stamp else { continue }
            for key in keys where result.samples[key] == nil { result.samples[key] = entry.handwriting.samples[key] }
            if id == proposal.noteID {
                result.targetBounds = entry.handwriting.targetBounds(proposal.insertionTarget, selection: proposal.selectionPolygon)
            }
        }
        for key in keys where result.samples[key] == nil { result.samples[key] = alphabet.samples[key] }
        return result
    }
}
