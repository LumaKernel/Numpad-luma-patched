import AppKit
import ApplicationServices
import Carbon
import CTrackpad
import TrackpadCore

final class TouchStream {
    let receive: ([Touch], Double) -> Void
    init(receive: @escaping ([Touch], Double) -> Void) { self.receive = receive }

    func start() -> Bool {
        TPStart({ pointer, count, timestamp, context in
            guard let context else { return }
            let stream = Unmanaged<TouchStream>.fromOpaque(context).takeUnretainedValue()
            let touches = (0..<Int(count)).compactMap { index -> Touch? in
                guard let item = pointer?[index] else { return nil }
                return Touch(id: item.identifier, x: Double(item.x), y: Double(item.y))
            }
            // Framework-owned memory must be copied before this callback returns.
            DispatchQueue.main.async { stream.receive(touches, timestamp) }
        }, Unmanaged.passUnretained(self).toOpaque())
    }
    func stop() { TPStop() }
}

final class InputService {
    private var earlyTap: CFMachPort?
    private var earlySource: CFRunLoopSource?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var clicks = ClickFilter()
    private var lastTrackpadTouch = -Double.infinity
    private let screenZoom = ScreenZoomSuppression()
    private var threeFingerDrag = ThreeFingerDragSuppression()
    var blocksSystemGestures = false {
        didSet {
            screenZoom.update(enabled: blocksSystemGestures)
            if !blocksSystemGestures { threeFingerDrag.reset() }
        }
    }
    var onEscape: (() -> Void)?
    var onFailure: (() -> Void)?
    var onPhysicalClick: (() -> Void)?

    func updateTouches(_ touches: [Touch]) {
        if !touches.isEmpty { lastTrackpadTouch = ProcessInfo.processInfo.systemUptime }
        threeFingerDrag.update(contactCount: touches.count, enabled: blocksSystemGestures)
    }

    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel, .keyDown]
        // Quartz does not expose names for these WindowServer gesture events.
        // 29: gesture envelope, 30: Dock control/magnification, 31: fluid swipe.
        // See https://github.com/oomol-lab/dockswipe for the Dock event pathway.
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
            | SystemGestureFilter.eventMask
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<InputService>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    // Fail open: stop numpad instead of leaving input capture in a partial state.
                    service.onFailure?()
                    return Unmanaged.passUnretained(event)
                }
                if type == .keyDown {
                    if event.getIntegerValueField(.keyboardEventKeycode) == 53 {
                        service.onEscape?()
                        return nil
                    }
                    return Unmanaged.passUnretained(event)
                }
                if SystemGestureFilter.isGesture(type.rawValue) {
                    // Gate on mode, not asynchronous raw contact counts: the
                    // WindowServer can deliver the first gesture before touches.
                    return service.blocksSystemGestures ? nil : Unmanaged.passUnretained(event)
                }
                let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
                switch type {
                case .mouseMoved:
                    // Block all pointer movement while the keypad is active.
                    // The overlay drag uses its own NSWindow event handling.
                    return nil
                case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                    let allow = service.clicks.down(button: button,
                        pressure: event.getDoubleValueField(.mouseEventPressure),
                        recentTrackpadTouch: ProcessInfo.processInfo.systemUptime - service.lastTrackpadTouch < 0.25,
                        forceSuppress: service.threeFingerDrag.active)
                    if allow { service.onPhysicalClick?() }
                    return allow ? Unmanaged.passUnretained(event) : nil
                case .leftMouseUp, .rightMouseUp, .otherMouseUp:
                    return service.clicks.up(button: button) ? Unmanaged.passUnretained(event) : nil
                case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
                    return !service.threeFingerDrag.active && service.clicks.drag(button: button) ? Unmanaged.passUnretained(event) : nil
                default:
                    return nil
                }
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        guard let runSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port); return false
        }
        // Screen zoom can consume scroll/gesture packets before session taps.
        // Filter at the HID head as well, without moving ordinary key/click handling.
        let earlyMask = SystemGestureFilter.eventMask | (CGEventMask(1) << CGEventType.scrollWheel.rawValue)
        guard let early = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: earlyMask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<InputService>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    service.onFailure?()
                    return Unmanaged.passUnretained(event)
                }
                return service.blocksSystemGestures ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
            let earlyRunSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, early, 0) else {
                CFMachPortInvalidate(port); return false
        }
        earlyTap = early; earlySource = earlyRunSource
        CFRunLoopAddSource(CFRunLoopGetMain(), earlyRunSource, .commonModes)
        CGEvent.tapEnable(tap: early, enable: true)
        tap = port; source = runSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    func stop() {
        screenZoom.restore()
        if let earlyTap { CGEvent.tapEnable(tap: earlyTap, enable: false); CFMachPortInvalidate(earlyTap) }
        if let earlySource { CFRunLoopRemoveSource(CFRunLoopGetMain(), earlySource, .commonModes) }
        earlyTap = nil; earlySource = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
        clicks.reset(); lastTrackpadTouch = -Double.infinity
        threeFingerDrag.reset(); blocksSystemGestures = false
    }

    func send(_ key: PadKey) {
        let source = CGEventSource(stateID: .privateState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key.keyCode, keyDown: isDown)
            event?.flags = key.keyCode == 51 ? [] : .maskNumericPad
            event?.post(tap: .cghidEventTap)
        }
    }
    deinit { stop() }
}

// MARK: - Custom Shortcut

struct CustomShortcut: Codable, Equatable {
    enum Kind: String, Codable {
        case rightModifierChord  // Original: Right ⌘ + Right ⌥
        case keyCombo            // Modifier flags + key code
        case modifierChord       // Device-specific modifier bits only (e.g. Right ⌘ + Right ⌥)
    }
    var kind: Kind
    var keyCode: UInt16      // Only used for .keyCombo
    var modifiers: UInt64    // CGEventFlags for .keyCombo; device-specific bits for .modifierChord; ignored for .rightModifierChord

    static let defaultShortcut = CustomShortcut(kind: .rightModifierChord, keyCode: 0, modifiers: 0)

    // Device-specific modifier bits from IOLLEvent.h
    static let deviceLeftControl:  UInt64 = 0x0001
    static let deviceLeftShift:    UInt64 = 0x0002
    static let deviceRightShift:   UInt64 = 0x0004
    static let deviceLeftCommand:  UInt64 = 0x0008
    static let deviceRightCommand: UInt64 = 0x0010
    static let deviceLeftOption:   UInt64 = 0x0020
    static let deviceRightOption:  UInt64 = 0x0040
    static let deviceRightControl: UInt64 = 0x2000
    static let deviceModifierMask: UInt64 = 0x0001 | 0x0002 | 0x0004 | 0x0008 | 0x0010 | 0x0020 | 0x0040 | 0x2000

    var displayString: String {
        switch kind {
        case .rightModifierChord:
            return "Right ⌘ + Right ⌥"
        case .modifierChord:
            return Self.modifierChordDisplay(modifiers)
        case .keyCombo:
            var parts: [String] = []
            let flags = CGEventFlags(rawValue: modifiers)
            if flags.contains(.maskControl) { parts.append("⌃") }
            if flags.contains(.maskAlternate) { parts.append("⌥") }
            if flags.contains(.maskShift) { parts.append("⇧") }
            if flags.contains(.maskCommand) { parts.append("⌘") }
            let keyName = Self.keyName(for: keyCode)
            parts.append(keyName)
            return parts.joined(separator: "")
        }
    }

    static func modifierChordDisplay(_ bits: UInt64) -> String {
        var parts: [String] = []
        if bits & deviceLeftControl  != 0 { parts.append("Left ⌃") }
        if bits & deviceRightControl != 0 { parts.append("Right ⌃") }
        if bits & deviceLeftShift    != 0 { parts.append("Left ⇧") }
        if bits & deviceRightShift   != 0 { parts.append("Right ⇧") }
        if bits & deviceLeftOption   != 0 { parts.append("Left ⌥") }
        if bits & deviceRightOption  != 0 { parts.append("Right ⌥") }
        if bits & deviceLeftCommand  != 0 { parts.append("Left ⌘") }
        if bits & deviceRightCommand != 0 { parts.append("Right ⌘") }
        return parts.isEmpty ? "?" : parts.joined(separator: " + ")
    }

    static func deviceModifierCount(_ bits: UInt64) -> Int {
        var n = 0; var b = bits & deviceModifierMask
        while b != 0 { n += 1; b &= b - 1 }
        return n
    }

    static func keyName(for keyCode: UInt16) -> String {
        // Use Carbon's TISCopyCurrentKeyboardInputSource for layout-aware names.
        if let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
           let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let layout = unsafeBitCast(layoutData, to: CFData.self)
            let layoutPointer = CFDataGetBytePtr(layout)!
            var deadKeyState: UInt32 = 0
            var length: Int = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layoutPointer.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { $0 },
                keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, 4, &length, &chars)
            if status == noErr, length > 0 {
                return String(utf16CodeUnits: chars, count: length).uppercased()
            }
        }
        return "Key\(keyCode)"
    }

    static func load() -> CustomShortcut {
        guard let data = UserDefaults.standard.data(forKey: "activationShortcut"),
              let shortcut = try? JSONDecoder().decode(CustomShortcut.self, from: data) else {
            return .defaultShortcut
        }
        return shortcut
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: "activationShortcut")
    }
}

final class ActivationShortcut {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var chord = RightModifierChord()
    private var modifierChordActive = false
    var shortcut = CustomShortcut.load() {
        didSet {
            shortcut.save()
            chord.reset()
            modifierChordActive = false
        }
    }
    var action: (() -> Void)?

    func start() {
        guard tap == nil, AXIsProcessTrusted() else { return }
        let flagsMask = CGEventMask(1) << CGEventType.flagsChanged.rawValue
        let keyMask = CGEventMask(1) << CGEventType.keyDown.rawValue
        let eventMask: CGEventMask = switch shortcut.kind {
        case .rightModifierChord, .modifierChord:
            flagsMask
        case .keyCombo:
            keyMask | flagsMask
        }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: eventMask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let shortcutObj = Unmanaged<ActivationShortcut>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    shortcutObj.chord.reset()
                    shortcutObj.modifierChordActive = false
                    if let tap = shortcutObj.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                switch shortcutObj.shortcut.kind {
                case .rightModifierChord:
                    if type == .flagsChanged, shortcutObj.chord.update(flags: event.flags.rawValue) {
                        DispatchQueue.main.async { shortcutObj.action?() }
                    }
                case .modifierChord:
                    if type == .flagsChanged {
                        let current = event.flags.rawValue & CustomShortcut.deviceModifierMask
                        let required = shortcutObj.shortcut.modifiers
                        let matched = current == required
                        if matched && !shortcutObj.modifierChordActive {
                            DispatchQueue.main.async { shortcutObj.action?() }
                        }
                        shortcutObj.modifierChordActive = matched
                    }
                case .keyCombo:
                    if type == .keyDown {
                        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                        let modifierMask: UInt64 = CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue
                            | CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskControl.rawValue
                        let currentMods = event.flags.rawValue & modifierMask
                        let expectedMods = shortcutObj.shortcut.modifiers & modifierMask
                        if keyCode == shortcutObj.shortcut.keyCode && currentMods == expectedMods {
                            DispatchQueue.main.async { shortcutObj.action?() }
                        }
                    }
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port); return
        }
        self.tap = port; self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    func stop() {
        if let tap { CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; chord.reset()
    }

    func restart() {
        stop()
        start()
    }

    deinit { stop() }
}
