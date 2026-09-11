import Foundation
import CoreGraphics

@main struct CubeDynamicsChecks {
    static func main() {
        let page = CGRect(x: 1000, y: 1357, width: 1000, height: 1333)
        let limits = page.insetBy(dx: CubeDynamics.edgeInset, dy: CubeDynamics.edgeInset)
        var cube = CubeDynamics(position: CGPoint(x: page.midX, y: page.midY))
        cube.target = CGPoint(x: page.maxX + 1000, y: page.maxY + 1000)
        for _ in 0..<180 {
            cube.step(seconds: 1/60, page: page, level: 1, reduceMotion: false)
            precondition(limits.insetBy(dx: -0.001, dy: -0.001).contains(cube.position), "Cube must remain on its page")
        }
        precondition(cube.voice > 0.95 && cube.voice <= 1)
        cube.target = nil
        cube.velocity = CGVector(dx: -2000, dy: -2000)
        for _ in 0..<600 {
            cube.step(seconds: 1/60, page: page, level: 0, reduceMotion: false)
            precondition(limits.insetBy(dx: -0.001, dy: -0.001).contains(cube.position))
        }
        precondition(cube.velocity == .zero && cube.voice < 0.001)
        let goal = CGPoint(x: page.midX + 70, y: page.midY - 80)
        cube.target = goal
        cube.step(seconds: 1/60, page: page, level: 0, reduceMotion: true)
        precondition(cube.position == goal && cube.velocity == .zero)
        var sixty = CubeDynamics(position: CGPoint(x: page.midX, y: page.midY))
        var fast = sixty
        sixty.target = goal; fast.target = goal
        for _ in 0..<60 { sixty.step(seconds: 1/60, page: page, level: 0.5, reduceMotion: false) }
        for _ in 0..<120 { fast.step(seconds: 1/120, page: page, level: 0.5, reduceMotion: false) }
        precondition(hypot(sixty.position.x - fast.position.x, sixty.position.y - fast.position.y) < 0.01)
        print("Cube dynamics checks passed: page boundaries, release inertia/friction, volume smoothing, Reduce Motion and frame-rate consistency.")
    }
}
