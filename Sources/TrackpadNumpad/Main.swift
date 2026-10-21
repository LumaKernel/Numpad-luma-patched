import AppKit
import CTrackpad

@main
enum Main {
    static func main() {
        if CommandLine.arguments.contains("--test-haptic") {
            let success = TPHapticClick()
            TPHapticShutdown()
            print("Haptic pulse: \(success ? "OK" : "unavailable")")
            exit(success ? 0 : 1)
        }
        if CommandLine.arguments.contains("--diagnose") {
            let ready = TPInitialize()
            print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
            print("MultitouchSupport / default trackpad: \(ready ? "OK" : String(cString: TPError()))")
            print("Accessibility: \(AXIsProcessTrusted() ? "granted" : "not granted")")
            if ready {
                let started = TPStart({ _, _, _, _ in }, nil)
                print("Touch stream start: \(started ? "OK" : String(cString: TPError()))")
                TPStop()
                print("Touch stream stop: OK")
                if !started { exit(1) }
            }
            exit(ready ? 0 : 1)
        }
        let app = NSApplication.shared
        // A non-Dock app can keep the text cursor in the user's destination application.
        app.setActivationPolicy(.accessory)
        let delegate = AppController()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
