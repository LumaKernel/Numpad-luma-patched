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
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var clicks = ClickFilter()
    private var lastTrackpadTouch = -Double.infinity
    var onEscape: (() -> Void)?
    var onFailure: (() -> Void)?
    var onPhysicalClick: (() -> Void)?

    func updateTouches(_ touches: [Touch]) {
        if !touches.isEmpty { lastTrackpadTouch = ProcessInfo.processInfo.systemUptime }
    }

    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel, .keyDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
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
                let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
                switch type {
                case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                    let allow = service.clicks.down(button: button,
                        pressure: event.getDoubleValueField(.mouseEventPressure),
                        recentTrackpadTouch: ProcessInfo.processInfo.systemUptime - service.lastTrackpadTouch < 0.25)
                    if allow { service.onPhysicalClick?() }
                    return allow ? Unmanaged.passUnretained(event) : nil
                case .leftMouseUp, .rightMouseUp, .otherMouseUp:
                    return service.clicks.up(button: button) ? Unmanaged.passUnretained(event) : nil
                case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
                    return service.clicks.drag(button: button) ? Unmanaged.passUnretained(event) : nil
                default:
                    return nil
                }
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        guard let runSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port); return false
        }
        tap = port; source = runSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
        clicks.reset(); lastTrackpadTouch = -Double.infinity
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

final class ActivationShortcut {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var chord = RightModifierChord()
    var action: (() -> Void)?

    func start() {
        guard tap == nil, AXIsProcessTrusted() else { return }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: CGEventMask(1) << CGEventType.flagsChanged.rawValue,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let shortcut = Unmanaged<ActivationShortcut>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    shortcut.chord.reset()
                    if let tap = shortcut.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                } else if type == .flagsChanged, shortcut.chord.update(flags: event.flags.rawValue) {
                    DispatchQueue.main.async { shortcut.action?() }
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
    deinit { stop() }
}

