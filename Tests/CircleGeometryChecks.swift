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
        let boundary = CircleJellyGeometry.boundary(loop)!
        // Painted input stays a hollow stroke, then the closed hole contracts.
        let paint = CircleJellyGeometry.paint(loop)
        precondition(!paint.contains(boundary.center))
        precondition(paint.contains(loop[0]))
        let justClosed = CircleJellyGeometry.inwardFill(boundary, age: 0, reduceMotion: false)
        precondition(!justClosed.contains(boundary.center))
        precondition(justClosed.contains(loop[0]))
        let nearEdge = CGPoint(x: boundary.center.x + 120, y: boundary.center.y)
        precondition(!justClosed.contains(nearEdge))
        let filling = CircleJellyGeometry.inwardFill(boundary, age: 0.65, reduceMotion: false)
        precondition(filling.contains(nearEdge))
        precondition(!filling.contains(boundary.center))
        let filled = CircleJellyGeometry.inwardFill(boundary, age: CircleJellyGeometry.closeDuration + CircleJellyGeometry.fillDuration, reduceMotion: false)
        precondition(filled.contains(boundary.center))
        precondition(CircleJellyGeometry.inwardFill(boundary, age: 0, reduceMotion: true).contains(boundary.center))

        // Release preserves the live silhouette, reveals the missing arc over
        // time, and flows continuously from a closed stroke into an inward fill.
        for direction in [-1.0, 1.0] {
            let partial = ellipse(CGPoint(x: 200, y: 300), rx: 160, ry: 40, end: direction * .pi * 1.6)
            let completed = CircleGeometry.completedLoop(partial)!
            var droplet = CircleDropletDynamics(at: partial[partial.count - 2], time: 0)
            droplet.follow(partial.last!, at: 0.02)
            let release = CircleJellyGeometry.Release(traced: partial, completed: completed, droplet: droplet, time: 0.03)
            let liveHead = droplet.sample(at: 0.03).position
            let live = CircleJellyGeometry.paint(Array(partial.dropLast()))
                .union(CircleJellyGeometry.paint([partial[partial.count - 2], liveHead]))
                .union(CircleJellyGeometry.smoothPath(droplet.contour(at: 0.03, reduceMotion: false)))
            let start = release.path(age: 0, reduceMotion: false)
            let before = release.path(age: CircleJellyGeometry.closeDuration - 0.0001, reduceMotion: false)
            let after = release.path(age: CircleJellyGeometry.closeDuration + 0.0001, reduceMotion: false)
            var startDifference = 0, seamDifference = 0
            for x in stride(from: 30, through: 370, by: 2) {
                for y in stride(from: 250, through: 350, by: 2) {
                    let point = CGPoint(x: x, y: y)
                    if live.contains(point) != start.contains(point) { startDifference += 1 }
                    if before.contains(point) != after.contains(point) { seamDifference += 1 }
                }
            }
            precondition(startDifference == 0, "Release must begin with the existing droplet and paint")
            precondition(seamDifference < 5, "Closing and filling must share the same silhouette")
            let gap = completed[partial.count + (completed.count - partial.count) / 2]
            precondition(!start.contains(gap), "The gap must not close instantly")
            precondition(after.contains(gap))
            precondition(!after.contains(release.center))
            let mid = release.path(age: CircleJellyGeometry.closeDuration + CircleJellyGeometry.fillDuration / 2, reduceMotion: false)
            precondition(mid.contains(nearEdge) && !mid.contains(release.center))
            let done = release.path(age: 2, reduceMotion: false)
            precondition(done.contains(release.center))
            precondition(release.path(age: 0, reduceMotion: true).contains(release.center))
            var lastProgress: CGFloat = 0
            for tick in 0...100 {
                let progress = release.closingProgress(age: CircleJellyGeometry.closeDuration * Double(tick) / 100)
                precondition(progress >= lastProgress && progress >= 0 && progress <= 1)
                lastProgress = progress
            }
            let impactAge = CircleJellyGeometry.closeDuration + 0.045
            let transform = release.impactTransform(age: impactAge, reduceMotion: false)
            let movedCenter = release.center.applying(transform)
            let displacement = CGPoint(x: movedCenter.x - release.center.x, y: movedCenter.y - release.center.y)
            precondition(displacement.x * release.joinDirection.x + displacement.y * release.joinDirection.y > 0,
                         "Closing recoil must follow the joining tangent")
            precondition(abs(transform.a * transform.d - transform.b * transform.c - 1) < 0.0001,
                         "The gel squeeze should preserve area")
            precondition(release.impactTransform(age: impactAge, reduceMotion: true) == .identity)
            precondition(release.impactTransform(age: 2, reduceMotion: false) == .identity)
        }

        // Dragging retains momentum, is tethered to the finger, and settles at rest.
        var drop = CircleDropletDynamics(at: .zero, time: 0)
        drop.follow(CGPoint(x: 50, y: 0), at: 0.02)
        let lagged = drop.sample(at: 0.02)
        precondition(lagged.position.x < 50 && lagged.position.x >= 32)
        let moving = drop.sample(at: 0.06)
        precondition(moving.velocity.x > 0)
        drop.follow(CGPoint(x: 55, y: 5), at: 0.06)
        precondition(abs(drop.velocity.x - moving.velocity.x) < 0.001)
        let rested = drop.sample(at: 1.5)
        precondition(CircleGeometry.distance(rested.position, drop.target) < 0.01)
        precondition(hypot(rested.velocity.x, rested.velocity.y) < 0.01)
        let blob = CircleJellyGeometry.smoothPath(drop.contour(at: 0.06, reduceMotion: false))
        precondition(blob.boundingBoxOfPath.width > 0 && blob.boundingBoxOfPath.height > 0)
        let reducedDrop = CircleJellyGeometry.smoothPath(drop.contour(at: 0.06, reduceMotion: true))
        precondition(abs(reducedDrop.boundingBoxOfPath.midX - drop.target.x) < 0.01)
        precondition(abs(reducedDrop.boundingBoxOfPath.midY - drop.target.y) < 0.01)

        // The circle and rectangle share a continuous contour. No shape swap:
        // first frame is the filled region, final frame is the fitted rectangle.
        let box = CGRect(x: 70, y: 265, width: 260, height: 70)
        let target = CircleJellyGeometry.roundedRectangle(box)
        let begin = CircleJellyGeometry.moldedContour(from: boundary, to: target, age: 0, reduceMotion: false)
        for i in begin.indices {
            let expected = CircleJellyGeometry.point(center: boundary.center,
                angle: CircleJellyGeometry.angle(at: i), radius: boundary.radii[i] + CircleJellyGeometry.brushRadius)
            precondition(CircleGeometry.distance(begin[i], expected) < 0.001)
        }
        let final = CircleJellyGeometry.moldedContour(from: boundary, to: target, age: CircleJellyGeometry.closeDuration + CircleJellyGeometry.fillDuration, reduceMotion: false)
        let reduced = CircleJellyGeometry.moldedContour(from: boundary, to: target, age: 0, reduceMotion: true)
        precondition(zip(final, reduced).allSatisfy { CircleGeometry.distance($0,$1) < 0.001 })
        for tick in 0...100 {
            let points = CircleJellyGeometry.moldedContour(from: boundary, to: target,
                age: Double(tick) / 100, reduceMotion: false)
            precondition(points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
            precondition(CircleJellyGeometry.smoothPath(points).contains(boundary.center))
        }
        precondition(CircleJellyGeometry.spring(0.3, omega: 13, damping: 0.56) > 1,
                     "The mold spring should overshoot rather than linearly interpolate")
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
