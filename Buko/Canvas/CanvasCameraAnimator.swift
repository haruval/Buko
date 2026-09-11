import UIKit

/// Animate the actual scroll camera each frame, so ink, grid, edge mask, and guide
/// geometry remain aligned throughout a snap. The callback never touches SwiftUI state.
final class CanvasCameraAnimator {
    private var displayLink: CADisplayLink?
    private var start: CFTimeInterval = 0
    private var duration: CFTimeInterval = 0.55
    private var step: ((CGFloat) -> Void)?
    private var completion: (() -> Void)?

    func animate(duration: CFTimeInterval = 0.55, step: @escaping (CGFloat) -> Void, completion: @escaping () -> Void) {
        cancel()
        if UIAccessibility.isReduceMotionEnabled {
            step(1)
            completion()
            return
        }
        self.step = step
        self.duration = max(0.01, duration)
        self.completion = completion
        start = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick() {
        let progress = min(1, (CACurrentMediaTime() - start) / duration)
        step?(progress)
        if progress >= 1 {
            let finished = completion
            cancel()
            finished?()
        }
    }

    func cancel() {
        displayLink?.invalidate()
        displayLink = nil
        step = nil
        completion = nil
    }
}
