import CryptoKit
import Foundation
import PencilKit
import OSLog

/// Optional private device-validation input; never compiled into normal Buko.
/// The ordinary schemes write nothing. Capture schemes retain at most 24 input
/// snapshots of at most 8 MB each, inside this experiment's app container.
actor SpatialDeviceCapture {
    private static let shared = SpatialDeviceCapture()
    private let log = Logger(subsystem: "dev.buko.LayoutExperiment.M4", category: "Capture")

    nonisolated static func record(drawing: PKDrawing, polygon: [CGPoint]) async {
        guard ProcessInfo.processInfo.arguments.contains("--spatial-record-capture") else { return }
        await shared.save(drawing: drawing, polygon: polygon)
    }

    private func save(drawing: PKDrawing, polygon: [CGPoint]) {
        guard !Task.isCancelled else { return }
        do {
            let root = URL.documentsDirectory.appendingPathComponent("IndependentCaptures", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let existing = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            guard existing.count < 24 else { log.error("Capture limit reached; no input saved."); return }
            let data = drawing.dataRepresentation()
            guard data.count <= 8_000_000, polygon.count <= 4_096,
                  polygon.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
                log.error("Input exceeds capture bounds; no input saved."); return
            }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let id = UUID().uuidString
            let directory = root.appendingPathComponent(id, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            do {
                try data.write(to: directory.appendingPathComponent("input.drawing"), options: .atomic)
                let metadata: [String: Any] = [
                    "id": id, "date": ISO8601DateFormatter().string(from: .now),
                    "drawingSHA256": digest, "strokeCount": drawing.strokes.count,
                    "polygon": polygon.map { [Double($0.x), Double($0.y)] },
                    "mode": ProcessInfo.processInfo.arguments.contains("--spatial-baseline") ? "baseline" : "candidate",
                    "os": ProcessInfo.processInfo.operatingSystemVersionString,
                    "provenance": "User input in isolated app; human authorship must be confirmed separately"
                ]
                try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
                    .write(to: directory.appendingPathComponent("input.json"), options: .atomic)
                log.notice("Saved validation input \(id, privacy: .public)")
            } catch {
                try? FileManager.default.removeItem(at: directory)
                throw error
            }
        } catch { log.error("Validation capture failed; inference may still proceed. Review the device console.") }
    }
}
