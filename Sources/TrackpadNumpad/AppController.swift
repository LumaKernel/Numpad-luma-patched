import AppKit
import SwiftUI
import ApplicationServices
import Carbon
import QuartzCore
import CTrackpad
import TrackpadCore

final class AppController: NSObject, ObservableObject, NSApplicationDelegate, NSWindowDelegate {
    @Published private(set) var enabled = false
    @Published private(set) var trusted = AXIsProcessTrusted()
    @Published private(set) var deviceReady = false
    @Published private(set) var message = "트랙패드가 숫자 키패드로 바뀝니다."
    @Published private(set) var highlighted: UInt16?
    @Published private(set) var lastKey = "—"
    @Published private(set) var touches: [Touch] = []
    @Published private(set) var overlaySnapPreview: OverlaySnapResult?
    @Published private(set) var overlaySnapBounds = CGRect.zero
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
            input.blocksSystemGestures = enabled && experimentalCalibration
            configurationChanged()
        }
    }
    @Published var calibrationTiming = CalibrationTiming(rawValue: UserDefaults.standard.string(forKey: "calibrationTiming") ?? "touchDown") ?? .touchDown {
        didSet {
            UserDefaults.standard.set(calibrationTiming.rawValue, forKey: "calibrationTiming")
            configurationChanged()
        }
    }
    @Published private(set) var calibrationTracking = false
    private var calibrationBaseline: (transform: PadTransform, has: Bool, status: String)?
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
    @Published var hapticsEnabled = UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(hapticsEnabled, forKey: "hapticsEnabled") }
    }
    @Published var hapticTouchDown = UserDefaults.standard.object(forKey: "hapticTouchDown") as? Bool ?? true {
        didSet { UserDefaults.standard.set(hapticTouchDown, forKey: "hapticTouchDown") }
    }
    @Published var hapticInputConfirmed = UserDefaults.standard.object(forKey: "hapticInputConfirmed") as? Bool ?? true {
        didSet { UserDefaults.standard.set(hapticInputConfirmed, forKey: "hapticInputConfirmed") }
    }
    @Published var hapticFiveEnter = UserDefaults.standard.object(forKey: "hapticFiveEnter") as? Bool ?? true {
        didSet { UserDefaults.standard.set(hapticFiveEnter, forKey: "hapticFiveEnter") }
    }
    @Published var hapticFiveExit = UserDefaults.standard.object(forKey: "hapticFiveExit") as? Bool ?? true {
        didSet { UserDefaults.standard.set(hapticFiveExit, forKey: "hapticFiveExit") }
    }
    @Published var hapticCalibration = UserDefaults.standard.object(forKey: "hapticCalibration") as? Bool ?? true {
        didSet { UserDefaults.standard.set(hapticCalibration, forKey: "hapticCalibration") }
    }
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
    private var snapPanel: OverlayPanel?
    private var settingsWindow: NSWindow?
    private var calibrationGesture = InteractiveCalibrationGesture()
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
    private var activationInput: FocusedInput?
    private var screenObserver: NSObjectProtocol?
    private var overlayDragging = false
    private var previewRevision = 0

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
            if let panel = self.panel, panel.isVisible, panel.frame.contains(NSEvent.mouseLocation) { return }

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
            if let panel = self?.panel, panel.isVisible, panel.alphaValue > 0.01 {
                panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
                panel.orderFrontRegardless()
            }
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
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.panel?.isVisible == true, !self.overlayDragging else { return }
            self.updateGuide()
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
        activationInput = FocusedInput.capture(applicationPID: NSApp.isActive ? previousApp?.processIdentifier : nil)
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
            if self.overlayDragging {
                self.recognizer.reset(waitForLift: !touches.isEmpty)
                self.centerFeedback.reset()
                self.calibrationGesture.reset(waitForLift: !touches.isEmpty)
                return
            }
            guard ProcessInfo.processInfo.systemUptime >= readyAt else {
                _ = self.recognizer.process(touches, at: timestamp, suppressInput: true)
                self.centerFeedback.reset(); self.calibrationGesture.reset(); return
            }
            if self.experimentalCalibration {
                let frame = self.calibrationGesture.process(touches, at: timestamp, allowFour: self.fourFingerCalibration, timing: self.calibrationTiming, reference: self.calibrationBaseline?.transform ?? self.calibrationTransform)
                if frame.consumed {
                    self.recognizer.reset(waitForLift: !touches.isEmpty)
                    self.centerFeedback.reset()
                    self.handleCalibration(frame)
                    return
                }
            }
            let logicalTouches = touches.map { self.effectiveTransform.apply($0) }
            let centerEvents = self.centerFeedback.processEvents(logicalTouches)
            if (self.hapticFiveEnter && centerEvents.contains(.entered)) ||
                (self.hapticFiveExit && centerEvents.contains(.exited)) {
                self.playHaptic(strong: true)
            }
            let confirmedKey = self.recognizer.process(logicalTouches, at: timestamp)
            if self.hapticTouchDown && self.recognizer.beganKey != nil { self.playHaptic() }
            if let key = confirmedKey {
                self.input.send(key)
                if self.hapticInputConfirmed { self.playHaptic() }
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
        input.blocksSystemGestures = experimentalCalibration
        message = "숫자판 사용 중 · Esc로 해제"
        if NSApp.isActive {
            settingsWindow?.orderOut(nil)
            NSApp.setActivationPolicy(.accessory)
            previousApp?.activate(options: [])
        }
        updateMenu(); updateGuide()
    }

    func disable() {
        if calibrationTracking { persistCalibration() }
        calibrationTracking = false; calibrationBaseline = nil
        enabled = false; generation += 1
        snapPanel?.orderOut(nil); overlaySnapPreview = nil; overlayDragging = false
        input.stop()
        stream?.stop(); stream = nil
        recognizer.reset(); centerFeedback.reset(); calibrationGesture.reset(); highlighted = nil; touches = []
        previewRevision += 1
        activationInput = nil
        hideOverlay()
        message = "숫자판이 꺼져 있습니다. 트랙패드를 평소처럼 사용하세요."
        if item != nil { updateMenu() }
    }

    private var calibrationKey: String {
        "calibration.similarity456.v1." + controlSide.rawValue
    }

    private func resetInputState() {
        calibrationTracking = false; calibrationBaseline = nil
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

    private func persistCalibration() {
        guard hasCalibration, let data = try? JSONEncoder().encode(calibrationTransform) else { return }
        UserDefaults.standard.set(data, forKey: calibrationKey)
    }

    private func handleCalibration(_ frame: InteractiveCalibrationFrame) {
        guard let phase = frame.phase else { return }
        switch phase {
        case .began, .changed:
            if calibrationBaseline == nil {
                calibrationBaseline = (calibrationTransform, hasCalibration, calibrationStatus)
            }
            calibrationTracking = true
            if let points = frame.points {
                applyCalibration(points, persist: false, feedback: phase == .began, resetGesture: false, preserveOrder: true)
            }
        case .ended:
            if let points = frame.points {
                applyCalibration(points, persist: true, feedback: !calibrationTracking, resetGesture: false, preserveOrder: true)
            }
            calibrationTracking = false; calibrationBaseline = nil
        case .cancelled:
            if let baseline = calibrationBaseline {
                calibrationTransform = baseline.transform; hasCalibration = baseline.has; calibrationStatus = baseline.status
            }
            calibrationTracking = false; calibrationBaseline = nil
        }
    }

    private func applyCalibration(_ points: [PadPoint], persist: Bool = true, feedback: Bool = true,
                                  resetGesture: Bool = true, preserveOrder: Bool = false) {
        do {
            let transform = try PadTransform.calibrating(points, layout: controlSide, preserveOrder: preserveOrder, reference: calibrationBaseline?.transform ?? calibrationTransform)
            calibrationTransform = transform; hasCalibration = true
            if persist { persistCalibration() }
            calibrationStatus = persist ? "\(points.count)손가락 보정 적용됨 · 회전·이동·균일 크기 반영" : "\(points.count)손가락을 따라 보정 중"
            if resetGesture { resetInputState() }
            if feedback && hapticCalibration { playHaptic() }
        } catch {
            calibrationStatus = error.localizedDescription
            if resetGesture { resetInputState() }
        }
    }

    func resetCalibration() {
        UserDefaults.standard.removeObject(forKey: calibrationKey)
        configurationChanged()
    }

    private func playHaptic(strong: Bool = false) {
        guard hapticsEnabled else { return }
        if !(strong ? TPHapticCenter() : TPHapticClick()) {
            NSHapticFeedbackManager.defaultPerformer.perform(strong ? .generic : .alignment, performanceTime: .now)
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
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func overlayScreen() -> NSScreen? {
        if enabled, let rect = activationInput?.field ?? activationInput?.caret {
            let best = NSScreen.screens.max { intersectionArea($0.frame, rect) < intersectionArea($1.frame, rect) }
            if let best, intersectionArea(best.frame, rect) > 0 { return best }
        }
        if let stored = UserDefaults.standard.dictionary(forKey: "overlayPosition"),
           let number = stored["screen"] as? NSNumber,
           let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber) == number }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func intersectionArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let rect = a.intersection(b)
        return rect.isNull ? 0 : rect.width * rect.height
    }

    private func preferredOverlayOrigin(screen: NSScreen, size: CGSize) -> CGPoint? {
        guard let stored = UserDefaults.standard.dictionary(forKey: "overlayPosition"),
              let x = stored["x"] as? Double, let y = stored["y"] as? Double, x.isFinite, y.isFinite else { return nil }
        let bounds = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        return CGPoint(x: bounds.minX + min(1, max(0, x)) * max(0, bounds.width - size.width),
                       y: bounds.minY + min(1, max(0, y)) * max(0, bounds.height - size.height))
    }

    private func updateGuide() {
        guard showGuide, let screen = overlayScreen() else { hideOverlay(); return }
        if panel == nil {
            let created = OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 360),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            created.title = "Trackpad Numpad 오버레이"
            created.contentView = NSHostingView(rootView: GuideView(model: self))
            created.isOpaque = false; created.backgroundColor = .clear
            created.hasShadow = true
            created.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
            created.ignoresMouseEvents = false
            created.hidesOnDeactivate = false
            created.becomesKeyOnlyIfNeeded = true
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel = created
        }
        guard let panel else { return }
        let size = OverlayPlacement.clamp(CGRect(origin: .zero, size: CGSize(width: 540, height: 360)), to: screen.visibleFrame).size
        let target = OverlayPlacement.place(size: size,
            preferredOrigin: preferredOverlayOrigin(screen: screen, size: size), on: screen.visibleFrame,
            avoiding: enabled ? activationInput?.field : nil, caret: enabled ? activationInput?.caret : nil)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        previewRevision += 1
        if !panel.isVisible {
            panel.alphaValue = reduceMotion ? 1 : 0
            panel.setFrame(reduceMotion ? target : target.offsetBy(dx: 0, dy: -6), display: true)
            panel.orderFrontRegardless()
        } else if !screen.visibleFrame.contains(panel.frame) {
            // Never animate through the gap between monitors or beyond a small display.
            panel.setFrame(target, display: true)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.18
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
    }

    private func hideOverlay() {
        guard let panel, panel.isVisible else { return }
        let revision = previewRevision
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.10
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, (!self.enabled || !self.showGuide), self.previewRevision == revision else { return }
            panel.orderOut(nil)
        }
    }

    func beginOverlayDrag() {
        overlayDragging = true; previewRevision += 1
        recognizer.cancelCurrentTap()
        overlaySnapPreview = nil
    }

    func moveOverlay(to origin: CGPoint, pointer: CGPoint) {
        guard let panel else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? panel.screen ?? NSScreen.main
        guard let screen else { return }
        if overlaySnapBounds != screen.visibleFrame { overlaySnapPreview = nil }
        let result = OverlaySnap.align(CGRect(origin: origin, size: panel.frame.size), on: screen.visibleFrame, previous: overlaySnapPreview)
        overlaySnapBounds = screen.visibleFrame
        overlaySnapPreview = result
        panel.setFrame(result.frame, display: true)
        if result.hasGuides {
            if snapPanel == nil {
                let guides = OverlayPanel(contentRect: screen.visibleFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                guides.contentView = NSHostingView(rootView: SnapGuideView(model: self))
                guides.isOpaque = false; guides.backgroundColor = .clear
                guides.hasShadow = false; guides.ignoresMouseEvents = true; guides.hidesOnDeactivate = false
                guides.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) - 1)
                guides.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                snapPanel = guides
            }
            snapPanel?.setFrame(screen.visibleFrame, display: true)
            snapPanel?.orderFrontRegardless()
        } else { snapPanel?.orderOut(nil) }
    }

    func endOverlayDrag() {
        overlayDragging = false; previewRevision += 1
        snapPanel?.orderOut(nil); overlaySnapPreview = nil
        if let panel, let screen = panel.screen ?? NSScreen.main {
            let bounds = screen.visibleFrame.insetBy(dx: 12, dy: 12)
            let frame = OverlayPlacement.clamp(panel.frame, to: screen.visibleFrame)
            panel.setFrame(frame, display: true)
            let x = (frame.minX - bounds.minX) / max(1, bounds.width - frame.width)
            let y = (frame.minY - bounds.minY) / max(1, bounds.height - frame.height)
            UserDefaults.standard.set(["x": Double(x), "y": Double(y),
                "screen": screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber ?? 0], forKey: "overlayPosition")
        }
        if !enabled { schedulePreviewHide() }
    }

    func resetOverlayPosition() {
        UserDefaults.standard.removeObject(forKey: "overlayPosition")
        if panel?.isVisible == true {
            updateGuide()
            if !enabled { schedulePreviewHide() }
        }
    }

    private func schedulePreviewHide() {
        let revision = previewRevision
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, !self.enabled, !self.overlayDragging, self.previewRevision == revision else { return }
            self.hideOverlay()
        }
    }

    @objc func previewGuide() {
        updateGuide()
        schedulePreviewHide()
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === settingsWindow {
            NSApp.setActivationPolicy(.accessory)
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
