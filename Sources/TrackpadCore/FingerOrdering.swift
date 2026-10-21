import Foundation

/// Project onto the physical principal axis, oriented by the previous layout.
public enum FingerOrdering {
    public static func indices(_ points: [PadPoint], reference: PadTransform = .identity) -> [Int] {
        guard points.count > 1 else { return Array(points.indices) }
        let aspect = PadGeometry.aspectRatio
        let mx = points.map(\.x).reduce(0, +) * aspect / Double(points.count)
        let my = points.map(\.y).reduce(0, +) / Double(points.count)
        var xx = 0.0, yy = 0.0, xy = 0.0
        for p in points {
            let x = p.x * aspect - mx, y = p.y - my
            xx += x * x; yy += y * y; xy += x * y
        }
        let angle = 0.5 * atan2(2 * xy, xx - yy)
        var dx = cos(angle), dy = sin(angle)
        let placement = reference.inverse
        if dx * placement.a * aspect + dy * placement.c < 0 { dx = -dx; dy = -dy }
        return points.indices.sorted {
            let p = points[$0], q = points[$1]
            let delta = (p.x - q.x) * aspect * dx + (p.y - q.y) * dy
            return abs(delta) > 1e-12 ? delta < 0 : $0 < $1
        }
    }
    public static func ordered(_ points: [PadPoint], reference: PadTransform = .identity) -> [PadPoint] {
        indices(points, reference: reference).map { points[$0] }
    }
}
