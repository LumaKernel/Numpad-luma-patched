import Foundation
import Darwin

/// Accessibility screen zoom is handled outside ordinary application gestures.
/// Use its own preference API so the accessibility daemon receives the change.
final class ScreenZoomSuppression {
    private typealias Read = @convention(c) () -> Bool
    private typealias Write = @convention(c) (Bool) -> Void
    private struct Setting {
        let name: String
        let read: Read
        let write: Write
    }
    private let settings: [Setting]
    private let defaults = UserDefaults.standard
    private var originals: [String: Bool] = [:]
    private let journal = "screenZoomSuppression.restore.v1"
    private let synchronize: (@convention(c) () -> Void)?

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/UniversalAccess.framework/UniversalAccess", RTLD_LAZY | RTLD_LOCAL)
        settings = ["UATrackpadGestureZoom", "UAScrollZoom"].compactMap { name in
            guard let handle, let read = dlsym(handle, name + "IsEnabled"),
                  let write = dlsym(handle, name + "SetEnabled") else { return nil }
            return Setting(name: name, read: unsafeBitCast(read, to: Read.self),
                           write: unsafeBitCast(write, to: Write.self))
        }
        synchronize = handle.flatMap { dlsym($0, "UAPreferencesSynchronize") }
            .map { unsafeBitCast($0, to: (@convention(c) () -> Void).self) }
        // Recover the exact prior switches if a previous process quit abruptly.
        if let saved = defaults.dictionary(forKey: journal) as? [String: Bool] {
            originals = saved
            restore()
        }
    }

    func update(enabled: Bool) {
        guard enabled else { restore(); return }
        guard originals.isEmpty else { return }
        for setting in settings { originals[setting.name] = setting.read() }
        defaults.set(originals, forKey: journal)
        defaults.synchronize()
        for setting in settings where originals[setting.name] == true { setting.write(false) }
        synchronize?()
    }

    func restore() {
        guard !originals.isEmpty else { return }
        for setting in settings {
            if let original = originals[setting.name] { setting.write(original) }
        }
        synchronize?()
        originals.removeAll()
        defaults.removeObject(forKey: journal)
    }
    deinit { restore() }
}
