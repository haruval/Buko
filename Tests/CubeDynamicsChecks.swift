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
        precondition(CubeDynamics.microphoneLevel(rms: 0) == 0)
        precondition(CubeDynamics.microphoneLevel(rms: 0.01) > 0.65, "Ordinary speech should produce a stronger envelope")
        precondition(CubeDynamics.microphoneLevel(rms: 1) == 1)
        var attack = CubeDynamics(position: CGPoint(x: page.midX, y: page.midY))
        for _ in 0..<6 { attack.step(seconds: 1/60, page: page, level: 1, reduceMotion: false) }
        precondition(attack.voice > 0.65, "Microphone attack should respond within about 100 ms")
        for direction in [CGVector(dx: 0, dy: -1), CGVector(dx: 0, dy: 1), CGVector(dx: -1, dy: 0), CGVector(dx: 1, dy: 0),
                          CGVector(dx: -1, dy: -1), CGVector(dx: 1, dy: -1), CGVector(dx: -1, dy: 1), CGVector(dx: 1, dy: 1)] {
            var pulled = CubeDynamics(position: CGPoint(x: page.midX, y: page.midY))
            pulled.target = CGPoint(x: page.midX + direction.dx * 100, y: page.midY + direction.dy * 100)
            for _ in 0..<6 { pulled.step(seconds: 1/60, page: page, level: 0, reduceMotion: false) }
            precondition(pulled.facePull.dx * direction.dx + pulled.facePull.dy * direction.dy > 5,
                         "Top face must lead toward the finger; the exposed wall trails in the opposite direction")
            if direction.dx == 0 { precondition(abs(pulled.facePull.dx) < 0.001) }
            if direction.dy == 0 { precondition(abs(pulled.facePull.dy) < 0.001) }
            pulled.target = nil
            for _ in 0..<180 { pulled.step(seconds: 1/60, page: page, level: 0, reduceMotion: false) }
            precondition(hypot(pulled.facePull.dx, pulled.facePull.dy) < 0.001, "Face must settle flat on release")
        }
        print("Cube dynamics checks passed: page boundaries, release inertia/friction, volume smoothing, Reduce Motion and frame-rate consistency.")
    }
}
