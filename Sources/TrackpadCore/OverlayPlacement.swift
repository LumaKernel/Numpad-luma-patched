import Foundation
import CoreGraphics

/// AppKit screen coordinates, including negative origins on secondary displays.
public enum OverlayPlacement {
    public static func clamp(_ frame: CGRect, to screen: CGRect, margin: CGFloat = 12) -> CGRect {
        let bounds = screen.insetBy(dx: min(margin, screen.width / 4), dy: min(margin, screen.height / 4))
        let scale = min(1, bounds.width / max(1, frame.width), bounds.height / max(1, frame.height))
        let size = CGSize(width: frame.width * scale, height: frame.height * scale)
        return CGRect(x: min(max(frame.minX, bounds.minX), bounds.maxX - size.width),
                      y: min(max(frame.minY, bounds.minY), bounds.maxY - size.height),
                      width: size.width, height: size.height)
    }

    public static func place(size: CGSize, preferredOrigin: CGPoint? = nil, on screen: CGRect,
                             avoiding field: CGRect? = nil, caret: CGRect? = nil) -> CGRect {
        let preferred = clamp(CGRect(origin: preferredOrigin ?? CGPoint(x: screen.midX - size.width / 2,
                                                                       y: screen.minY + 24), size: size), to: screen)
        let obstacle = field ?? caret
        guard let obstacle, !obstacle.isNull, !obstacle.isInfinite else { return preferred }
        let protected = obstacle.insetBy(dx: -12, dy: -12)
        guard preferred.intersects(protected) else { return preferred }
        let w = preferred.width, h = preferred.height
        var candidates = [preferred]
        for x in [preferred.minX, protected.minX, protected.midX - w / 2, protected.maxX - w] {
            candidates.append(CGRect(x: x, y: protected.maxY, width: w, height: h))
            candidates.append(CGRect(x: x, y: protected.minY - h, width: w, height: h))
        }
        for y in [preferred.minY, protected.minY, protected.midY - h / 2, protected.maxY - h] {
            candidates.append(CGRect(x: protected.minX - w, y: y, width: w, height: h))
            candidates.append(CGRect(x: protected.maxX, y: y, width: w, height: h))
        }
        for x in [screen.minX, screen.maxX - w] {
            for y in [screen.minY, screen.maxY - h] { candidates.append(CGRect(x: x, y: y, width: w, height: h)) }
        }
        candidates = candidates.map { clamp($0, to: screen) }
        func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
            let intersection = a.intersection(b)
            return intersection.isNull ? 0 : intersection.width * intersection.height
        }
        let clear = candidates.filter { overlap($0, protected) < 0.01 }
        let options = clear.isEmpty ? candidates : clear
        return options.min { lhs, rhs in
            if clear.isEmpty {
                // A full-screen editor may leave no clear space; protect the caret first.
                if let caret {
                    let a = overlap(lhs, caret.insetBy(dx: -10, dy: -10))
                    let b = overlap(rhs, caret.insetBy(dx: -10, dy: -10))
                    if abs(a - b) > 0.01 { return a < b }
                }
                let a = overlap(lhs, protected), b = overlap(rhs, protected)
                if abs(a - b) > 0.01 { return a < b }
            }
            return hypot(lhs.midX - preferred.midX, lhs.midY - preferred.midY) <
                hypot(rhs.midX - preferred.midX, rhs.midY - preferred.midY)
        } ?? preferred
    }
}
