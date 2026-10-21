import Foundation

public enum CalibrationPhase { case began, changed, ended, cancelled }
public struct InteractiveCalibrationFrame {
    public let consumed: Bool
    public let points: [PadPoint]?
    public let phase: CalibrationPhase?
}

/// Placement follows fixed contact IDs through translation and rotation.
public struct InteractiveCalibrationGesture {
    private var release = CalibrationGesture()
    private var ids: [Int32] = []
    private var initial: [PadPoint] = []
    private var latest: [PadPoint] = []
    private var invalid = false
    private var live = false
    private var blocked = false
    public init() {}
    public mutating func reset(waitForLift: Bool = false) {
        release.reset(waitForLift: waitForLift)
        ids = []; initial = []; latest = []
        invalid = false; live = false; blocked = waitForLift
    }

    public mutating func process(_ touches: [Touch], at timestamp: Double, allowFour: Bool,
                                 timing: CalibrationTiming = .touchDown, reference: PadTransform = .identity) -> InteractiveCalibrationFrame {
        func frame(_ consumed: Bool, _ points: [PadPoint]? = nil, _ phase: CalibrationPhase? = nil) -> InteractiveCalibrationFrame {
            InteractiveCalibrationFrame(consumed: consumed, points: points, phase: phase)
        }
        if blocked {
            if touches.isEmpty { reset() }
            return frame(true)
        }
        let legacy = release.process(touches, at: timestamp, allowFour: allowFour)
        if touches.isEmpty {
            defer { reset() }
            if !ids.isEmpty {
                if !invalid && (timing == .touchDown || live || legacy.points?.count == ids.count) {
                    return frame(true, latest, .ended)
                }
                return frame(true, nil, .cancelled)
            }
            return frame(legacy.consumed)
        }
        if touches.count > 4 || (touches.count == 4 && !allowFour) {
            invalid = true
            return frame(true, nil, .cancelled)
        }
        guard timestamp.isFinite, touches.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            invalid = true
            return frame(true, nil, .cancelled)
        }
        guard touches.count >= 3 else { return frame(!ids.isEmpty || legacy.consumed) }
        // A fourth contact upgrades the gesture once; subsequent partial lifts
        // keep the same four IDs and last complete sample until all lift.
        if ids.isEmpty || (ids.count == 3 && touches.count == 4) {
            let points = touches.map { PadPoint(x: $0.x, y: $0.y) }
            let order = FingerOrdering.indices(points, reference: reference)
            ids = order.map { touches[$0].id }
            initial = order.map { points[$0] }
            latest = initial
        }
        if touches.count < ids.count { return frame(true) }
        guard !invalid, Set(touches.map(\.id)) == Set(ids) else {
            invalid = true; return frame(true, nil, .cancelled)
        }
        latest = ids.compactMap { id in touches.first { $0.id == id }.map { PadPoint(x: $0.x, y: $0.y) } }
        let moved = zip(latest, initial).contains { pair in hypot(pair.0.x - pair.1.x, pair.0.y - pair.1.y) > 0.015 }
        if timing == .touchDown || live || moved {
            let phase: CalibrationPhase = live ? .changed : .began
            live = true
            return frame(true, latest, phase)
        }
        return frame(true)
    }
}

/// Latch suppression until every finger lifts, so dropping from three to two
/// contacts cannot resume a system drag halfway through a calibration gesture.
public struct ThreeFingerDragSuppression {
    public private(set) var active = false
    public init() {}
    public mutating func update(contactCount: Int, enabled: Bool) {
        active = enabled && (contactCount >= 3 || (active && contactCount > 0))
    }
    public mutating func reset() { active = false }
}
