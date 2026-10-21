import CoreGraphics

public struct OverlaySnapResult: Equatable {
    public let frame: CGRect
    public let verticalGuide: CGFloat?
    public let horizontalGuide: CGFloat?
    public var hasGuides: Bool { verticalGuide != nil || horizontalGuide != nil }
}

public enum OverlaySnap {
    /// Independent axis alignment gives corners, edge centers and free edge docking.
    public static func align(_ proposed: CGRect, on screen: CGRect, previous: OverlaySnapResult? = nil) -> OverlaySnapResult {
        let frame = OverlayPlacement.clamp(proposed, to: screen)
        let gap: CGFloat = 24
        let xs = [screen.minX + gap, screen.midX - frame.width / 2, screen.maxX - gap - frame.width]
        let ys = [screen.minY + gap, screen.midY - frame.height / 2, screen.maxY - gap - frame.height]
        func nearest(_ value: CGFloat, _ targets: [CGFloat], old: CGFloat?) -> Int? {
            if let old, let index = targets.indices.first(where: { abs(targets[$0] - old) < 0.01 }), abs(value - old) <= 30 { return index }
            guard let index = targets.indices.min(by: { abs(targets[$0] - value) < abs(targets[$1] - value) }),
                  abs(targets[index] - value) <= 20 else { return nil }
            return index
        }
        let x = nearest(frame.minX, xs, old: previous?.verticalGuide != nil ? previous?.frame.minX : nil)
        let y = nearest(frame.minY, ys, old: previous?.horizontalGuide != nil ? previous?.frame.minY : nil)
        let target = OverlayPlacement.clamp(CGRect(x: x.map { xs[$0] } ?? frame.minX,
            y: y.map { ys[$0] } ?? frame.minY, width: frame.width, height: frame.height), to: screen)
        let guideX = x.map { $0 == 0 ? target.minX : ($0 == 1 ? target.midX : target.maxX) }
        let guideY = y.map { $0 == 0 ? target.minY : ($0 == 1 ? target.midY : target.maxY) }
        return OverlaySnapResult(frame: target, verticalGuide: guideX, horizontalGuide: guideY)
    }
}
