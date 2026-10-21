import AppKit
import SwiftUI
import ApplicationServices
import Carbon
import CTrackpad
import TrackpadCore

final class AppController: NSObject, ObservableObject, NSApplicationDelegate {
    @Published private(set) var enabled = false
    @Published private(set) var trusted = AXIsProcessTrusted()
    @Published private(set) var deviceReady = false
    @Published private(set) var message = "트랙패드가 숫자 키패드로 바뀝니다."
    @Published private(set) var highlighted: UInt16?
    @Published private(set) var lastKey = "—"
    @Published private(set) var touches: [Touch] = []
    @Published var controlSide = KeypadLayout(rawValue: UserDefaults.standard.string(forKey: "controlSide") ?? "left") ?? .left {
        didSet {
            guard oldValue != controlSide else { return }
            UserDefaults.standard.set(controlSide.rawValue, forKey: "controlSide")
            configurationChanged()
        }
    }
    @Published var experimentalCalibration = UserDefaults.standard.bool(forKey: "experimentalCalibration") {
        didSet {
            UserDefaults.standard.set(experimentalCalibration, forKey: "experimentalCalibration")
            configurationChanged()
        }
    }
    @Published var keepCalibrationOnReactivate = UserDefaults.standard.object(forKey: "keepCalibrationOnReactivate") as? Bool ?? true {
        didSet { UserDefaults.standard.set(keepCalibrationOnReactivate, forKey: "keepCalibrationOnReactivate") }
    }
    @Published var fourFingerCalibration = UserDefaults.standard.bool(forKey: "fourFingerCalibration") {
        didSet {
            UserDefaults.standard.set(fourFingerCalibration, forKey: "fourFingerCalibration")
            calibrationGesture.reset(waitForLift: !touches.isEmpty)
            recognizer.reset(waitForLift: !touches.isEmpty)
        }
    }
    @Published private(set) var calibrationTransform = PadTransform.identity
    @Published private(set) var hasCalibration = false
    @Published private(set) var calibrationStatus = "아직 보정하지 않았습니다."
    var effectiveTransform: PadTransform { experimentalCalibration ? calibrationTransform : .identity }
    @Published var sound = UserDefaults.standard.object(forKey: "sound") as? Bool ?? false {
        didSet { UserDefaults.standard.set(sound, forKey: "sound") }
    }
    @Published var showGuide = UserDefaults.standard.object(forKey: "showGuide") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showGuide, forKey: "showGuide")
            if enabled { updateGuide() }
        }
    }
    private var item: NSStatusItem!
    private var panel: NSPanel?
    private var settingsWindow: NSWindow?
    private var calibrationGesture = CalibrationGesture()
    private let optionShortcut = ActivationShortcut()
    private let input = InputService()
    private var stream: TouchStream?
    private var recognizer = AnchoredTapRecognizer()
    private var centerFeedback = CenterCrossingFeedback()
    private var generation = 0
    private var permissionTimer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var previousApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configurationChanged()
        deviceReady = TPInitialize()
        if !deviceReady { message = String(cString: TPError()) }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenu()
        input.onEscape = { [weak self] in self?.disable() }
        input.onPhysicalClick = { [weak self] in
            guard let self else { return }
            self.recognizer.cancelCurrentTap()
            if self.experimentalCalibration && (self.touches.count == 3 ||
                (self.fourFingerCalibration && self.touches.count == 4)) {
                self.applyCalibration(self.touches.map { PadPoint(x: $0.x, y: $0.y) })
                self.calibrationGesture.reset(waitForLift: true)
            }
        }
        optionShortcut.action = { [weak self] in
            guard let self else { return }
            self.toggle()
        }
        optionShortcut.start()
        input.onFailure = { [weak self] in
            self?.disable()
            self?.message = "입력 감시가 중단되어 숫자판을 껐습니다. 다시 켜서 사용하세요."
        }
        previousApp = NSWorkspace.shared.frontmostApplication
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.processIdentifier != ProcessInfo.processInfo.processIdentifier { self?.previousApp = app }
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.disable() }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let wasTrusted = self.trusted
            self.trusted = AXIsProcessTrusted()
            if wasTrusted != self.trusted { self.updateMenu() }
            if self.trusted { self.optionShortcut.start() } else { self.optionShortcut.stop() }
            if self.enabled && !self.trusted { self.disable(); self.message = "손쉬운 사용 권한을 다시 허용해 주세요." }
            // Secure input must not leave the pointer trapped if Escape is unavailable.
            if self.enabled && IsSecureEventInputEnabled() { self.disable(); self.message = "보안 입력 중에는 숫자판이 일시 해제됩니다." }
        }
        if CommandLine.arguments.contains("--settings") { showSettings() }
        if CommandLine.arguments.contains("--smoke-test") { previewGuide() }
        if CommandLine.arguments.contains("--smoke-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { NSApp.terminate(nil) }
        }
    }

    @objc func toggle() {
        if enabled { disable(); return }
        trusted = AXIsProcessTrusted()
        guard trusted else {
            message = "손쉬운 사용 권한을 허용한 뒤 다시 켜 주세요."
            requestPermission(); return
        }
        guard !IsSecureEventInputEnabled() else { message = "보안 입력을 마친 뒤 다시 켜 주세요."; return }
        deviceReady = TPInitialize()
        guard deviceReady else { message = String(cString: TPError()); showSettings(); return }
        guard input.start() else {
            message = "입력 감시를 시작하지 못했습니다. 손쉬운 사용 권한 확인 후 앱을 다시 실행하세요."
            showSettings(); return
        }
        generation += 1
        let session = generation
        recognizer.reset()
        centerFeedback.reset()
        calibrationGesture.reset()
        // Ignore the click/finger used to enable the mode, including delayed framework frames.
        let readyAt = ProcessInfo.processInfo.systemUptime + 0.25
        stream = TouchStream { [weak self] touches, timestamp in
            guard let self, self.enabled, self.generation == session else { return }
            self.touches = touches
            self.input.updateTouches(touches)
            guard ProcessInfo.processInfo.systemUptime >= readyAt else {
                _ = self.recognizer.process(touches, at: timestamp, suppressInput: true)
                self.centerFeedback.reset(); self.calibrationGesture.reset(waitForLift: !touches.isEmpty); return
            }
            if self.experimentalCalibration {
                let frame = self.calibrationGesture.process(touches, at: timestamp, allowFour: self.fourFingerCalibration)
                if frame.consumed {
                    self.recognizer.reset(waitForLift: !touches.isEmpty)
                    self.centerFeedback.reset()
                    if let points = frame.points { self.applyCalibration(points) }
                    return
                }
            }
            let logicalTouches = touches.map { self.effectiveTransform.apply($0) }
            if self.centerFeedback.process(logicalTouches) { self.playHaptic() }
            let confirmedKey = self.recognizer.process(logicalTouches, at: timestamp)
            if self.recognizer.beganKey != nil { self.playHaptic() }
            if let key = confirmedKey {
                self.input.send(key)
                self.playHaptic()
                self.lastKey = key.label
                self.highlighted = key.id
                if self.sound { NSSound(named: "Tink")?.play() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
                    if self?.generation == session { self?.highlighted = nil }
                }
            }
        }
        guard stream?.start() == true else {
            stream = nil; input.stop(); message = String(cString: TPError()); return
        }
        if !keepCalibrationOnReactivate {
            calibrationTransform = .identity
            hasCalibration = false
            calibrationStatus = "기본 배치로 시작했습니다. 필요하면 다시 보정하세요."
            resetInputState()
        }
        enabled = true
        message = "숫자판 사용 중 · Esc로 해제"
        if NSApp.isActive {
            settingsWindow?.orderOut(nil)
            previousApp?.activate(options: [])
        }
        updateMenu(); updateGuide()
    }

    func disable() {
        enabled = false; generation += 1
        input.stop()
        stream?.stop(); stream = nil
        recognizer.reset(); centerFeedback.reset(); calibrationGesture.reset(); highlighted = nil; touches = []
        panel?.orderOut(nil)
        message = "숫자판이 꺼져 있습니다. 트랙패드를 평소처럼 사용하세요."
        if item != nil { updateMenu() }
    }

    private var calibrationKey: String {
        "calibration.similarity456.v1." + controlSide.rawValue
    }

    private func resetInputState() {
        recognizer = AnchoredTapRecognizer(layout: controlSide)
        recognizer.reset(waitForLift: !touches.isEmpty)
        centerFeedback = CenterCrossingFeedback(layout: controlSide)
        calibrationGesture.reset(waitForLift: !touches.isEmpty)
        highlighted = nil
    }

    private func configurationChanged() {
        if let data = UserDefaults.standard.data(forKey: calibrationKey),
           let saved = try? JSONDecoder().decode(PadTransform.self, from: data), saved.isSimilarity {
            calibrationTransform = saved; hasCalibration = true
            calibrationStatus = "저장된 보정이 준비되었습니다."
        } else {
            calibrationTransform = .identity; hasCalibration = false
            calibrationStatus = "아직 보정하지 않았습니다."
        }
        resetInputState()
    }

    private func applyCalibration(_ points: [PadPoint]) {
        do {
            let transform = try PadTransform.calibrating(points, layout: controlSide)
            calibrationTransform = transform; hasCalibration = true
            if let data = try? JSONEncoder().encode(transform) {
                UserDefaults.standard.set(data, forKey: calibrationKey)
            }
            calibrationStatus = "\(points.count)손가락 보정 적용됨 · 회전·이동·균일 크기 반영"
            resetInputState()
            playHaptic()
        } catch {
            calibrationStatus = error.localizedDescription
            resetInputState()
        }
    }

    func resetCalibration() {
        UserDefaults.standard.removeObject(forKey: calibrationKey)
        configurationChanged()
    }

    private func playHaptic() {
        if !TPHapticClick() {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    @objc func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func showSettings() {
        if enabled { disable() }
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 700),
                styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Trackpad Numpad 설정"
            window.contentView = NSHostingView(rootView: SettingsView(model: self))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func updateGuide() {
        guard showGuide else { panel?.orderOut(nil); return }
        if panel == nil {
            let created = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 360),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            created.contentView = NSHostingView(rootView: GuideView(model: self))
            created.isOpaque = false; created.backgroundColor = .clear
            created.hasShadow = true; created.level = .floating
            created.ignoresMouseEvents = true
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel = created
        }
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel?.setFrameOrigin(NSPoint(x: frame.maxX - 564, y: frame.minY + 24))
        }
        panel?.orderFrontRegardless()
    }

    @objc func previewGuide() {
        updateGuide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, !self.enabled else { return }
            self.panel?.orderOut(nil)
        }
    }

    private func updateMenu() {
        item.button?.image = NSImage(systemSymbolName: enabled ? "rectangle.grid.3x3.fill" : "rectangle.grid.3x3", accessibilityDescription: "Trackpad Numpad")
        item.button?.contentTintColor = enabled ? .systemMint : nil
        item.button?.toolTip = "Trackpad Numpad · 오른쪽 ⌘ + 오른쪽 ⌥로 전환"
        let menu = NSMenu()
        menu.addItem(withTitle: enabled ? "숫자판 끄기  오른쪽 ⌘⌥ / Esc" : "숫자판 켜기  오른쪽 ⌘⌥", action: #selector(toggle), keyEquivalent: "")
        menu.addItem(withTitle: "설정…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "키 배치 미리 보기", action: #selector(previewGuide), keyEquivalent: "")
        if !trusted {
            menu.addItem(withTitle: "손쉬운 사용 권한 허용…", action: #selector(requestPermission), keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(); return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        disable(); TPHapticShutdown(); permissionTimer?.invalidate()
    }
}
