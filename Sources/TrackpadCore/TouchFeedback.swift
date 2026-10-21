import Foundation

private struct FiveRegion {
    static let width = 1 / Double(PadKey.columnCount)
    static let height = 1 / Double(PadKey.rowCount)
    let center: PadPoint
    init(layout: KeypadLayout) { center = layout.center(of: "5") }

    func distance(_ touch: Touch) -> Double {
        hypot((touch.x - center.x) / Self.width, (touch.y - center.y) / Self.height)
    }
    func containsAnchor(_ touch: Touch) -> Bool {
        touch.x.isFinite && touch.y.isFinite &&
            abs(touch.x - center.x) <= Self.width * 0.5 && abs(touch.y - center.y) <= Self.height * 0.5
    }
}

/// A center detent for each continuous contact, with separate entry/exit radii
/// so sensor noise at the boundary cannot cause repeated pulses.
public struct CenterCrossingFeedback {
    private var contacts: [Int32: Bool] = [:]
    private let region: FiveRegion
    public init(layout: KeypadLayout = .right) { region = FiveRegion(layout: layout) }
    public mutating func reset() { contacts.removeAll() }

    public mutating func process(_ touches: [Touch]) -> Bool {
        var next: [Int32: Bool] = [:]
        var entered = false
        for touch in touches where touch.x.isFinite && touch.y.isFinite {
            let distance = region.distance(touch)
            if let wasInside = contacts[touch.id] {
                let inside = wasInside ? distance < 0.18 : distance <= 0.12
                if inside != wasInside { entered = true }
                next[touch.id] = inside
            } else {
                // Landing directly on 5 is a tap, not a crossing.
                next[touch.id] = distance <= 0.12
            }
        }
        contacts = next
        return entered
    }
}

/// A stationary resting contact becomes an anchor while another finger taps.
/// A simultaneous contact near 5 remains a convenient immediate anchor.
public struct AnchoredTapRecognizer {
    public private(set) var beganKey: PadKey?
    private struct Rest {
        var point: PadPoint
        var since: Double
    }
    private enum Block { case none, initialContact, fullLift }
    private var tap: TapRecognizer
    private let region: FiveRegion
    private var anchorID: Int32?
    private var anchorOrigin: PadPoint?
    private var resting: [Int32: Rest] = [:]
    private var block = Block.none
    public init(layout: KeypadLayout = .right) {
        tap = TapRecognizer(layout: layout); region = FiveRegion(layout: layout)
    }

    public mutating func cancelCurrentTap() { tap.reset(waitForLift: true); beganKey = nil }

    public mutating func reset(waitForLift: Bool = false) {
        anchorID = nil; anchorOrigin = nil; resting = [:]
        beganKey = nil
        block = waitForLift ? .initialContact : .none
        tap.reset(waitForLift: waitForLift)
    }

    public mutating func process(_ touches: [Touch], at timestamp: Double, suppressInput: Bool = false) -> PadKey? {
        beganKey = nil
        guard timestamp.isFinite, touches.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            reset(waitForLift: true); block = .fullLift; return nil
        }
        let currentIDs = Set(touches.map(\.id))
        resting = resting.filter { currentIDs.contains($0.key) }
        for touch in touches {
            if let rest = resting[touch.id], timestamp >= rest.since,
               hypot(touch.x - rest.point.x, touch.y - rest.point.y) <= 0.035 {
                continue
            }
            resting[touch.id] = Rest(point: PadPoint(x: touch.x, y: touch.y), since: timestamp)
        }
        if suppressInput {
            // Keep contact age through the activation grace period. A finger
            // held while toggling can become an anchor without having to lift.
            if touches.isEmpty { reset() } else {
                block = .initialContact; anchorID = nil; anchorOrigin = nil; tap.reset(waitForLift: true)
            }
            return nil
        }
        if block == .fullLift {
            if touches.isEmpty { reset() }
            return nil
        }
        let stableAnchor = touches.filter { timestamp - (resting[$0.id]?.since ?? timestamp) >= 0.12 }
            .min { resting[$0.id]!.since < resting[$1.id]!.since }
        if block == .initialContact {
            if touches.isEmpty { reset(); return nil }
            guard let anchor = stableAnchor else { return nil }
            setAnchor(anchor)
        }
        if let anchorID, let origin = anchorOrigin {
            guard let anchor = touches.first(where: { $0.id == anchorID }),
                  hypot(anchor.x - origin.x, anchor.y - origin.y) <= 0.08 else {
                reset(waitForLift: !touches.isEmpty)
                if !touches.isEmpty { block = .fullLift }
                return nil
            }
            return processTap(touches.filter { $0.id != anchorID }, at: timestamp)
        }
        if touches.count >= 2 {
            let anchor = stableAnchor ?? touches.filter { region.distance($0) <= 0.22 }
                .min { region.distance($0) < region.distance($1) }
            if let anchor {
                setAnchor(anchor)
                return processTap(touches.filter { $0.id != anchor.id }, at: timestamp)
            }
        }
        return processTap(touches, at: timestamp)
    }

    private mutating func processTap(_ touches: [Touch], at timestamp: Double) -> PadKey? {
        let key = tap.process(touches, at: timestamp)
        beganKey = tap.beganKey
        return key
    }

    private mutating func setAnchor(_ touch: Touch) {
        anchorID = touch.id; anchorOrigin = PadPoint(x: touch.x, y: touch.y)
        block = .none; tap.reset()
    }
}
