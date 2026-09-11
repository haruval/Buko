import Foundation

@main struct CircleGeometryChecks {
    static func main() {
        func ellipse(_ center: CGPoint, rx: CGFloat, ry: CGFloat, start: Double = 0, end: Double = .pi * 2) -> [CGPoint] {
            (0...80).map { i in
                let angle = start + (end - start) * Double(i) / 80
                return CGPoint(x: center.x + rx * cos(angle), y: center.y + ry * sin(angle))
            }
        }
        let loop = ellipse(CGPoint(x: 200, y: 300), rx: 160, ry: 40)
        precondition(CircleGeometry.isLoop(loop))
        precondition(CircleGeometry.isLoop(loop.reversed()))
        for direction in [-1.0, 1.0] {
            for start in [0.0, Double.pi / 2, Double.pi, 4.4] {
                let partial = ellipse(CGPoint(x: 200, y: 300), rx: 160, ry: 40,
                                      start: start, end: start + direction * .pi * 1.6)
                let completed = CircleGeometry.completedLoop(partial)!
                precondition(completed.count > partial.count)
                precondition(completed.last == partial.first)
                precondition(CircleGeometry.path(completed).contains(CGPoint(x: 200, y: 300)))
                precondition(CircleGeometry.isLoop(completed))
            }
        }
        let early = ellipse(CGPoint(x: 200, y: 300), rx: 160, ry: 40, end: .pi * 0.65)
        let origin = CircleGeometry.flowOrigin(early)!
        precondition(CircleGeometry.distance(origin, CGPoint(x: 200, y: 300)) < 1)
        precondition(CircleGeometry.flowOrigin((0...40).map { CGPoint(x: $0 * 5, y: $0 * 3) }) == nil)
        precondition(CircleGeometry.springGrowth(age: 0) == 0)
        precondition(CircleGeometry.springGrowth(age: 0.1) > 0)
        precondition(abs(CircleGeometry.springGrowth(age: 1) - 1) < 0.002)
        precondition(!CircleGeometry.isLoop(ellipse(.zero, rx: 100, ry: 80, end: .pi)))
        precondition(!CircleGeometry.isLoop(ellipse(.zero, rx: 10, ry: 8)))
        precondition(!CircleGeometry.isLoop((0...40).map { CGPoint(x: $0 * 5, y: $0 * 3) }))
        let concave = [CGPoint(x: 0,y: 0), CGPoint(x: 100,y: 0), CGPoint(x: 40,y: 40), CGPoint(x: 0,y: 100)]
        precondition(CircleGeometry.path(concave).contains(CGPoint(x: 15,y: 15)))
        precondition(!CircleGeometry.path(concave).contains(CGPoint(x: 85,y: 85)))
        let doc = loop.map { PageGeometry.documentPoint($0, scale: 1.2, offset: CGPoint(x: 1200,y: 1357)) }
        precondition(CircleGeometry.path(doc).contains(PageGeometry.documentPoint(CGPoint(x: 200,y: 300), scale: 1.2, offset: CGPoint(x: 1200,y: 1357))))
        print("Circle geometry checks passed")
    }
}
