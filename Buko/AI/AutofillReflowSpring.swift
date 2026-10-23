import Foundation

/// The circle's center spring, expressed as document-space position and velocity.
/// Retargeting (including Decline) carries momentum through the new destination.
nonisolated struct AutofillReflowSpring: Hashable {
    static let duration: TimeInterval = 1.2
    private(set) var position: CGFloat = 0
    private(set) var velocity: CGFloat = 0
    private(set) var target: CGFloat = 0
    private var startedAt: TimeInterval = 0
    private var damping: CGFloat = 0.7

    func sample(at time: TimeInterval) -> (position: CGFloat, velocity: CGFloat) {
        let age = max(0, time - startedAt)
        guard age < Self.duration else { return (target, 0) }
        let t = CGFloat(age), omega: CGFloat = 15
        let decay = damping * omega, frequency = omega * sqrt(1 - damping * damping)
        let a = position - target, b = (velocity + decay * a) / frequency
        let c = cos(frequency * t), s = sin(frequency * t), e = exp(-decay * t)
        return (target + e * (a * c + b * s),
                e * ((b * frequency - decay * a) * c - (a * frequency + decay * b) * s))
    }

    mutating func retarget(_ value: CGFloat, at time: TimeInterval, reduceMotion: Bool = false) {
        if reduceMotion {
            position = value; velocity = 0; target = value; startedAt = time
            return
        }
        guard value != target else { return }
        let current = sample(at: time)
        position = current.position; velocity = current.velocity; target = value; startedAt = time
        // Long fills can move ink several pages. Keep their rebound small rather
        // than amplifying the circle's playful overshoot into a large page jump.
        let fraction = min(0.046, 8 / max(1, abs(target - position)))
        let logarithm = -log(fraction)
        damping = max(0.7, logarithm / sqrt(.pi * .pi + logarithm * logarithm))
    }

    mutating func settle() { position = target; velocity = 0 }

    mutating func delay(by duration: TimeInterval) { startedAt += duration }
}
