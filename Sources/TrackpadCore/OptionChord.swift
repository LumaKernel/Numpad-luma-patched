/// Right Command (0x10) + right Option (0x40), excluding left-side
/// counterparts, Shift and Control. Device-specific bits: IOLLEvent.h.
public struct RightModifierChord {
    private var bothDown = false
    public init() {}
    public mutating func reset() { bothDown = false }
    public mutating func update(flags: UInt64) -> Bool {
        let now = flags & 0x50 == 0x50 && flags & (0x28 | 0x20000 | 0x40000) == 0
        defer { bothDown = now }
        return now && !bothDown
    }
}
