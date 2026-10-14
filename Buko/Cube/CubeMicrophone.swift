import AVFoundation
import Observation
import UIKit

/// Only a scalar envelope crosses from the audio callback. No buffer is retained.
nonisolated final class CubeAudioEnvelope: @unchecked Sendable {
    private let lock = NSLock()
    private var value: CGFloat = 0
    func write(_ next: CGFloat) { lock.lock(); value = next; lock.unlock() }
    func read() -> CGFloat { lock.lock(); defer { lock.unlock() }; return value }
}

@Observable @MainActor
final class CubeMicrophone {
    enum Status { case off, requesting, listening, denied, unavailable }
    private(set) var status = Status.off
    private var desired = false
    private var foreground = true
    private var permissionTask: Task<Void, Never>?
    private var engine: AVAudioEngine?
    private var ownsAudioSession = false
    private let envelope = CubeAudioEnvelope()
    var level: CGFloat { status == .listening ? envelope.read() : 0 }

    func setActive(_ active: Bool) {
        desired = active
        if active { startIfPossible() }
        else {
            permissionTask?.cancel(); permissionTask = nil
            stopHardware(); status = .off
        }
    }

    func setForeground(_ active: Bool) {
        foreground = active
        if active { startIfPossible() }
        else { stopHardware() }
    }

    func startIfPossible() {
        guard desired, foreground, UIApplication.shared.applicationState == .active, engine == nil, permissionTask == nil else { return }
        switch AVAudioApplication.shared.recordPermission {
        case .denied: status = .denied
        case .undetermined:
            status = .requesting
            permissionTask = Task { [weak self] in
                let granted = await AVAudioApplication.requestRecordPermission()
                guard let self, !Task.isCancelled else { return }
                self.permissionTask = nil
                guard self.desired else { return }
                if granted { self.startIfPossible() } else { self.status = .denied }
            }
        case .granted: startHardware()
        @unknown default: status = .unavailable
        }
    }

    func interrupted() { stopHardware(); if desired { status = .unavailable } }

    private func startHardware() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker])
            try session.setActive(true)
            ownsAudioSession = true
            let audio = AVAudioEngine()
            let input = audio.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw MicError.noInput }
            let meter = envelope
            input.installTap(onBus: 0, bufferSize: 512, format: format) { buffer, _ in
                guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
                var sum: Float = 0
                for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
                let rms = sqrt(sum / Float(buffer.frameLength))
                meter.write(CubeDynamics.microphoneLevel(rms: rms))
            }
            engine = audio
            audio.prepare()
            try audio.start()
            status = .listening
        } catch {
            stopHardware(); status = .unavailable
        }
    }

    private func stopHardware() {
        if let engine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            self.engine = nil
        }
        envelope.write(0)
        if status == .listening { status = .off }
        // The hidden cube's ordinary teardown must not touch the audio session.
        if ownsAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            ownsAudioSession = false
        }
    }

    private enum MicError: Error { case noInput }
}
