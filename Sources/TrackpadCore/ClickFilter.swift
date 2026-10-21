/// Preserve each button's down/up/drag decision, including pressure-zero mouseUp.
public struct ClickFilter {
    private var passed: [Int: Bool] = [:]
    public init() {}
    public mutating func reset() { passed.removeAll() }
    public mutating func down(button: Int, pressure: Double, recentTrackpadTouch: Bool, forceSuppress: Bool = false) -> Bool {
        let allow = !forceSuppress && (pressure > 0 || !recentTrackpadTouch)
        passed[button] = allow
        return allow
    }
    public mutating func up(button: Int) -> Bool { passed.removeValue(forKey: button) ?? true }
    public func drag(button: Int) -> Bool { passed[button] ?? true }
}
