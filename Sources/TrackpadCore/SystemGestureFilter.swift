/// WindowServer gesture envelope, Dock-control and fluid-touch events. These
/// raw Quartz values are separate from AppKit's NSEvent.EventType values.
public enum SystemGestureFilter {
    public static let eventTypes: [UInt32] = [29, 30, 31]
    public static let eventMask: UInt64 = eventTypes.reduce(0) { $0 | (1 << $1) }
    public static func isGesture(_ type: UInt32) -> Bool { eventTypes.contains(type) }
}
