import Foundation

enum AutofillReflowChecks {
    static func run() {
        var spring = AutofillReflowSpring()
        spring.retarget(120, at: 10)
        precondition(spring.sample(at: 10).position == 0)
        let halfway = spring.sample(at: 10.12)
        precondition(halfway.position > 0 && halfway.position < 120 && halfway.velocity > 0)
        let positions = (0...144).map { spring.sample(at: 10 + Double($0) / 120).position }
        precondition(positions.max()! > 122 && positions.max()! < 128, "Small, visible rebound like the circle")
        let before = spring.sample(at: 10.12)
        spring.retarget(0, at: 10.12)
        let reversed = spring.sample(at: 10.12)
        precondition(abs(before.position - reversed.position) < 0.00001
                     && abs(before.velocity - reversed.velocity) < 0.00001, "Decline preserves position and momentum")
        precondition(spring.sample(at: 11.4).position == 0 && spring.sample(at: 11.4).velocity == 0)

        spring.retarget(350, at: 12)
        let updating = spring.sample(at: 12.1)
        spring.retarget(600, at: 12.1)
        precondition(abs(spring.sample(at: 12.1).position - updating.position) < 0.00001)
        precondition(abs(spring.sample(at: 12.1).velocity - updating.velocity) < 0.00001)
        precondition(spring.sample(at: 13.4).position == 600, "New handwriting metrics retarget the same motion")
        spring.retarget(0, at: 14, reduceMotion: true)
        precondition(spring.sample(at: 14).position == 0 && spring.sample(at: 14).velocity == 0)

        spring.retarget(120, at: 15)
        let prepared = spring.sample(at: 15.05)
        spring.delay(by: 0.3)
        precondition(abs(spring.sample(at: 15.35).position - prepared.position) < 0.00001,
                     "Renderer preparation must not consume the first animation frames")

        for distance: CGFloat in [-2400, -120, 0, 120, 2400] {
            var value = AutofillReflowSpring()
            value.retarget(distance, at: 20)
            let points = (0...144).map { value.sample(at: 20 + Double($0) / 120).position }
            precondition(points.allSatisfy { $0.isFinite && abs($0) <= abs(distance) + 8.01 })
            value.settle()
            precondition(value.sample(at: 20.1).position == distance && value.sample(at: 20.1).velocity == 0)
        }
        print("Autofill reflow: rebound, reversal/retarget continuity, long-distance bounds and Reduce Motion passed")
    }
}
