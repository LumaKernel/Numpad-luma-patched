import Foundation

/// A rectangular sub-region of the trackpad in normalized coordinates (0…1).
/// Touches outside this region are ignored; touches inside are remapped to 0…1.
public struct PadRegion: Codable, Equatable, Sendable {
    public let minX: Double
    public let minY: Double
    public let maxX: Double
    public let maxY: Double

    public static let full = PadRegion(minX: 0, minY: 0, maxX: 1, maxY: 1)

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }
    public var isFullPad: Bool { self == .full }
    public var isUsable: Bool { width > 0.05 && height > 0.05 }

    /// Returns nil if the point is outside the region; otherwise remaps to 0…1.
    public func remap(_ point: PadPoint) -> PadPoint? {
        guard point.x >= minX, point.x <= maxX,
              point.y >= minY, point.y <= maxY,
              isUsable else { return nil }
        return PadPoint(
            x: (point.x - minX) / width,
            y: (point.y - minY) / height
        )
    }

    /// Returns nil if the touch is outside the region; otherwise remaps to 0…1.
    public func remap(_ touch: Touch) -> Touch? {
        guard let p = remap(PadPoint(x: touch.x, y: touch.y)) else { return nil }
        return Touch(id: touch.id, x: p.x, y: p.y)
    }

    /// Clamp edges to valid bounds.
    public func clamped() -> PadRegion {
        let lo = 0.0, hi = 1.0
        let x0 = min(max(minX, lo), hi)
        let y0 = min(max(minY, lo), hi)
        let x1 = min(max(maxX, lo), hi)
        let y1 = min(max(maxY, lo), hi)
        // Ensure min < max with a minimum size
        let minSize = 0.05
        if x1 - x0 < minSize || y1 - y0 < minSize {
            return .full
        }
        return PadRegion(minX: x0, minY: y0, maxX: x1, maxY: y1)
    }

    // MARK: - Persistence

    private static let key = "padRegion"

    public static func load(from defaults: UserDefaults = .standard) -> PadRegion {
        guard let data = defaults.data(forKey: key),
              let region = try? JSONDecoder().decode(PadRegion.self, from: data),
              region.isUsable else { return .full }
        return region
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: PadRegion.key)
        }
    }
}
