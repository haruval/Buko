import Foundation
import CoreGraphics

/// Small, bounded physics state in document coordinates; independent of rendering/audio.
nonisolated struct CubeDynamics {
    static let side: CGFloat = 64
    // Reserves room for microphone expansion, deformation and the rounded page corner.
    static let edgeInset: CGFloat = 104
    static let voiceScaleGain: CGFloat = 0.45
    static let maximumFacePull: CGFloat = 20
    var position: CGPoint
    var velocity = CGVector.zero
    var target: CGPoint?
    var collision: CGFloat = 0
    var voice: CGFloat = 0
    var facePull = CGVector.zero
    private var faceVelocity = CGVector.zero
    private var voiceVelocity: CGFloat = 0

    mutating func step(seconds: CGFloat, page: CGRect, level: CGFloat, reduceMotion: Bool) {
        let duration = min(1.0 / 15, max(0, seconds))
        let steps = max(1, Int(ceil(duration * 120)))
        let dt = duration / CGFloat(steps)
        let limits = page.insetBy(dx: Self.edgeInset, dy: Self.edgeInset)
        for _ in 0..<steps {
            if let target {
                let goal = Self.clamp(target, to: limits)
                if reduceMotion { position = goal; velocity = .zero }
                else {
                    velocity.dx += ((goal.x - position.x) * 340 - velocity.dx * 25) * dt
                    velocity.dy += ((goal.y - position.y) * 340 - velocity.dy * 25) * dt
                }
            } else {
                let friction = exp(-5.5 * dt)
                velocity.dx *= friction; velocity.dy *= friction
            }
            // Viscous resistance in the last 24 points absorbs most edge impacts.
            if (velocity.dx < 0 && position.x - limits.minX < 24) || (velocity.dx > 0 && limits.maxX - position.x < 24) {
                velocity.dx *= exp(-18 * dt)
            }
            if (velocity.dy < 0 && position.y - limits.minY < 24) || (velocity.dy > 0 && limits.maxY - position.y < 24) {
                velocity.dy *= exp(-18 * dt)
            }
            position.x += velocity.dx * dt; position.y += velocity.dy * dt
            let bounded = Self.clamp(position, to: limits)
            if position.x != bounded.x {
                collision = min(1, collision + abs(velocity.dx) / 350)
                velocity.dx *= -0.2
            }
            if position.y != bounded.y {
                collision = min(1, collision + abs(velocity.dy) / 350)
                velocity.dy *= -0.2
            }
            position = bounded
            collision *= exp(-10 * dt)
            // The grabbed top leads the heavier body in the finger's direction.
            // It relaxes independently after release instead of flipping with velocity.
            let goal = target.map { Self.clamp($0, to: limits) }
            var desiredPull = goal.map { CGVector(dx: ($0.x - position.x) * 0.8 + velocity.dx * 0.012,
                                                  dy: ($0.y - position.y) * 0.8 + velocity.dy * 0.012) } ?? .zero
            let distance = hypot(desiredPull.dx, desiredPull.dy)
            if distance > Self.maximumFacePull {
                desiredPull.dx *= Self.maximumFacePull / distance
                desiredPull.dy *= Self.maximumFacePull / distance
            }
            if reduceMotion { facePull = .zero; faceVelocity = .zero }
            else {
                faceVelocity.dx += ((desiredPull.dx - facePull.dx) * 520 - faceVelocity.dx * 30) * dt
                faceVelocity.dy += ((desiredPull.dy - facePull.dy) * 520 - faceVelocity.dy * 30) * dt
                facePull.dx += faceVelocity.dx * dt; facePull.dy += faceVelocity.dy * dt
            }
            // Faster attack makes syllables visible, with a softer decay in silence.
            let voiceTarget = min(1, max(0, level))
            let stiffness: CGFloat = voiceTarget > voice ? 420 : 220
            let damping: CGFloat = voiceTarget > voice ? 28 : 24
            voiceVelocity += ((voiceTarget - voice) * stiffness - voiceVelocity * damping) * dt
            voice = min(1, max(0, voice + voiceVelocity * dt))
        }
        if target == nil, hypot(velocity.dx, velocity.dy) < 0.5 { velocity = .zero }
    }

    static func microphoneLevel(rms: Float) -> CGFloat {
        let db = 20 * log10(max(0.00001, rms))
        let normalized = min(1, max(0, (db + 60) / 35))
        return CGFloat(pow(normalized, 0.7))
    }

    static func clamp(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(x: min(rect.maxX, max(rect.minX, point.x)), y: min(rect.maxY, max(rect.minY, point.y)))
    }
}
