import Foundation
import CoreGraphics

nonisolated enum CircleGeometry {
    struct Ellipse {
        let center: CGPoint
        let radii: CGSize
        func angle(_ point: CGPoint) -> CGFloat {
            atan2((point.y - center.y) / radii.height, (point.x - center.x) / radii.width)
        }
    }

    static func path(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }

    static func isLoop(_ points: [CGPoint]) -> Bool { completedLoop(points) != nil }

    /// Accept roughly three quarters of a loop, and continue its missing arc in
    /// the same direction. Geometry used for ink selection matches the completion.
    static func completedLoop(_ points: [CGPoint]) -> [CGPoint]? {
        guard points.count >= 10, let first = points.first, let last = points.last else { return nil }
        let bounds = path(points).boundingBoxOfPath
        guard bounds.width >= 40, bounds.height >= 28 else { return nil }
        let length = zip(points, points.dropFirst()).reduce(CGFloat.zero) { $0 + distance($1.0, $1.1) }
        guard length >= 100, length < 3.5 * (bounds.width + bounds.height) else { return nil }
        let ellipse = fittedEllipse(points) ?? Ellipse(center: CGPoint(x: bounds.midX, y: bounds.midY),
                                                       radii: CGSize(width: bounds.width / 2, height: bounds.height / 2))
        let travel = angularTravel(points, around: ellipse)
        guard abs(travel.signed) >= .pi * 1.45, abs(travel.signed) <= .pi * 2.35,
              abs(travel.signed) >= travel.absolute * 0.8 else { return nil }
        let area = abs(zip(points, points.dropFirst() + [first]).reduce(CGFloat.zero) {
            $0 + $1.0.x * $1.1.y - $1.1.x * $1.0.y
        }) / 2
        guard area > bounds.width * bounds.height * 0.38 else { return nil }
        let direction: CGFloat = travel.signed >= 0 ? 1 : -1
        let missing = max(0, 2 * .pi - abs(travel.signed))
        if missing < 0.03 || distance(first, last) < 3 { return points + [first] }
        let startAngle = ellipse.angle(last)
        let startRadius = hypot((last.x - ellipse.center.x) / ellipse.radii.width,
                                (last.y - ellipse.center.y) / ellipse.radii.height)
        let endRadius = hypot((first.x - ellipse.center.x) / ellipse.radii.width,
                              (first.y - ellipse.center.y) / ellipse.radii.height)
        let steps = max(8, Int(missing * max(ellipse.radii.width, ellipse.radii.height) / 6))
        var result = points
        for index in 1..<steps {
            let fraction = CGFloat(index) / CGFloat(steps)
            let angle = startAngle + direction * missing * fraction
            let radius = startRadius + (endRadius - startRadius) * fraction
            result.append(CGPoint(x: ellipse.center.x + cos(angle) * ellipse.radii.width * radius,
                                  y: ellipse.center.y + sin(angle) * ellipse.radii.height * radius))
        }
        result.append(first)
        return result
    }

    /// An axis-aligned least-squares ellipse gives an origin before the loop is
    /// finished. Normalize coordinates to keep the small normal system stable.
    /// Reject poorly constrained early arcs instead of guessing far off screen.
    static func fittedEllipse(_ points: [CGPoint]) -> Ellipse? {
        guard points.count >= 8 else { return nil }
        let bounds = path(points).boundingBoxOfPath
        guard bounds.width >= 24, bounds.height >= 18 else { return nil }
        let sx = bounds.width / 2, sy = bounds.height / 2
        var matrix = Array(repeating: Array(repeating: CGFloat.zero, count: 5), count: 4)
        for point in points {
            let x = (point.x - bounds.midX) / sx, y = (point.y - bounds.midY) / sy
            let row = [x * x, y * y, x, y]
            for i in 0..<4 {
                for j in 0..<4 { matrix[i][j] += row[i] * row[j] }
                matrix[i][4] += row[i]
            }
        }
        for column in 0..<4 {
            let pivot = (column..<4).max { abs(matrix[$0][column]) < abs(matrix[$1][column]) }!
            guard abs(matrix[pivot][column]) > 0.00001 else { return nil }
            matrix.swapAt(column, pivot)
            let divisor = matrix[column][column]
            for j in column..<5 { matrix[column][j] /= divisor }
            for i in 0..<4 where i != column {
                let factor = matrix[i][column]
                for j in column..<5 { matrix[i][j] -= factor * matrix[column][j] }
            }
        }
        let a = matrix[0][4], b = matrix[1][4], c = matrix[2][4], d = matrix[3][4]
        guard a > 0.01, b > 0.01 else { return nil }
        let cx = -c / (2 * a), cy = -d / (2 * b)
        let k = 1 + a * cx * cx + b * cy * cy
        let center = CGPoint(x: bounds.midX + cx * sx, y: bounds.midY + cy * sy)
        let radii = CGSize(width: sqrt(k / a) * sx, height: sqrt(k / b) * sy)
        guard radii.width.isFinite, radii.height.isFinite,
              bounds.insetBy(dx: -bounds.width * 0.7, dy: -bounds.height * 0.7).contains(center),
              radii.width >= sx * 0.6, radii.width <= bounds.width * 1.8,
              radii.height >= sy * 0.6, radii.height <= bounds.height * 1.8 else { return nil }
        let ellipse = Ellipse(center: center, radii: radii)
        let error = points.reduce(CGFloat.zero) { total, p in
            total + abs(hypot((p.x - center.x) / radii.width, (p.y - center.y) / radii.height) - 1)
        } / CGFloat(points.count)
        guard error < 0.16 else { return nil }
        return ellipse
    }

    static func angularTravel(_ points: [CGPoint], around ellipse: Ellipse) -> (signed: CGFloat, absolute: CGFloat) {
        zip(points, points.dropFirst()).reduce((CGFloat.zero, CGFloat.zero)) { total, pair in
            let difference = ellipse.angle(pair.1) - ellipse.angle(pair.0)
            let delta = atan2(sin(difference), cos(difference))
            return (total.0 + delta, total.1 + abs(delta))
        }
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}
