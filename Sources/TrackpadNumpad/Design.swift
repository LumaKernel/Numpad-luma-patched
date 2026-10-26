import AppKit
import SwiftUI
import TrackpadCore

// Shared visual language for onboarding, settings and the overlay.
let mint = Color(red: 0.43, green: 0.94, blue: 0.76)
let aqua = Color(red: 0.32, green: 0.70, blue: 0.98)
let canvas = Color(red: 0.045, green: 0.05, blue: 0.055)
var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

struct StatusPill: View {
    var granted: Bool
    var body: some View {
        HStack(spacing: 8) {
            if granted {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(mint)
                    .transition(.scale.combined(with: .opacity))
            } else {
                PulseDot(color: .orange)
            }
            Text(granted ? L("Access granted") : L("Waiting for access…"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(granted ? mint : .white.opacity(0.75))
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background((granted ? mint : Color.white).opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder((granted ? mint : Color.white).opacity(0.18), lineWidth: 1))
        .animation(.spring(response: 0.4, dampingFraction: 0.65), value: granted)
    }
}

struct LayoutCard: View {
    var layout: KeypadLayout
    var title: String
    var selected: Bool
    var padSize = CGSize(width: 270, height: 170)
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 14) {
                PadSurface(layout: layout, labelSize: 14, gap: 4, padding: 9, corner: 14)
                    .frame(width: padSize.width, height: padSize.height)
                HStack(spacing: 6) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? mint : .white.opacity(0.35))
                    Text(title).font(.system(size: 14, weight: .semibold))
                }
            }
            .padding(18)
            .background(.white.opacity(selected ? 0.07 : 0.03), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(selected ? mint.opacity(0.85) : .white.opacity(0.08), lineWidth: selected ? 1.5 : 1))
            .shadow(color: mint.opacity(selected ? 0.25 : 0), radius: 24)
            .scaleEffect(hover && !selected ? 1.02 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: selected)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hover)
    }
}

struct Keycap: View {
    var symbol: String
    var name: String
    var width: CGFloat
    var pressed = false
    var highlight = false
    var done = false
    var dim = false

    var body: some View {
        let active = pressed || done
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.black.opacity(0.55))
                .offset(y: 4)
            RoundedRectangle(cornerRadius: 9)
                .fill(active && highlight ? AnyShapeStyle(mint) :
                      AnyShapeStyle(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.17)], startPoint: .top, endPoint: .bottom)))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(active ? 0.0 : 0.1), lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    Text(symbol).font(.system(size: 14, weight: .medium)).padding(7)
                }
                .overlay(alignment: .bottomLeading) {
                    Text(name).font(.system(size: 9, weight: .medium)).padding(7)
                }
                .foregroundStyle(active && highlight ? Color.black.opacity(0.8) : .white.opacity(dim ? 0.45 : 0.92))
                .offset(y: pressed ? 3 : 0)
        }
        .frame(width: width, height: 54)
        .opacity(dim && !pressed ? 0.55 : 1)
        .overlay {
            if highlight && !active {
                PulseRing(corner: 11).padding(-3)
            }
        }
        .shadow(color: mint.opacity(active && highlight ? 0.6 : 0), radius: 18)
    }
}

struct PadSurface: View {
    var layout: KeypadLayout
    var revealed = Int.max
    var highlighted: UInt16?
    var target: UInt16?
    var touches: [CGPoint] = []
    var labelSize: CGFloat = 20
    var gap: CGFloat = 6
    var padding: CGFloat = 12
    var corner: CGFloat = 22

    var body: some View {
        GeometryReader { geometry in
            let width = (geometry.size.width - gap * CGFloat(PadKey.columnCount - 1)) / CGFloat(PadKey.columnCount)
            let height = (geometry.size.height - gap * CGFloat(PadKey.rowCount - 1)) / CGFloat(PadKey.rowCount)
            // Reveal keys as a diagonal wave from the top-left corner.
            let order = layout.keys.sorted { ($0.row + $0.column, $0.row) < ($1.row + $1.column, $1.row) }
            ZStack(alignment: .topLeading) {
                ForEach(Array(order.enumerated()), id: \.element.id) { index, key in
                    KeyTile(key: key, shown: index < revealed, lit: highlighted == key.id,
                            target: target == key.id, labelSize: labelSize)
                        .frame(width: width * CGFloat(key.columns) + gap * CGFloat(key.columns - 1),
                               height: height * CGFloat(key.rows) + gap * CGFloat(key.rows - 1))
                        .offset(x: CGFloat(key.column) * (width + gap), y: CGFloat(key.row) * (height + gap))
                }
                ForEach(touches.indices, id: \.self) { index in
                    Circle().fill(mint.opacity(0.3))
                        .overlay(Circle().strokeBorder(mint, lineWidth: 1.5))
                        .frame(width: 22, height: 22)
                        .shadow(color: mint.opacity(0.8), radius: 10)
                        .position(x: touches[index].x * geometry.size.width, y: (1 - touches[index].y) * geometry.size.height)
                }
            }
        }
        .padding(padding)
        .background {
            RoundedRectangle(cornerRadius: corner)
                .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.09)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: corner).strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 26, y: 16)
        }
    }
}

struct KeyTile: View {
    var key: PadKey
    var shown: Bool
    var lit: Bool
    var target: Bool
    var labelSize: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(lit ? mint : Color.white.opacity(key.isOperation ? 0.09 : 0.045))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(lit ? mint : .white.opacity(0.07), lineWidth: 1))
            .overlay {
                Text(key.label)
                    .font(.system(size: labelSize, weight: .medium, design: .rounded))
                    .foregroundStyle(lit ? Color.black.opacity(0.85) : .white.opacity(0.9))
            }
            .overlay { if target { PulseRing(corner: 9).padding(-2) } }
            .shadow(color: mint.opacity(lit ? 0.7 : 0), radius: 14)
            .scaleEffect(shown ? (lit ? 0.94 : 1) : 0.55)
            .opacity(shown ? 1 : 0)
            .blur(radius: shown ? 0 : 6)
    }
}

struct PulseRing: View {
    var corner: CGFloat
    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = reduceMotion ? 0.5 : (sin(timeline.date.timeIntervalSinceReferenceDate * 4) + 1) / 2
            RoundedRectangle(cornerRadius: corner)
                .strokeBorder(mint.opacity(0.35 + 0.55 * phase), lineWidth: 1.5)
                .shadow(color: mint.opacity(0.5 * phase), radius: 8)
        }
        .allowsHitTesting(false)
    }
}

struct PulseDot: View {
    var color: Color
    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
            ZStack {
                Circle().fill(color.opacity(0.4 * (1 - phase))).frame(width: 8 + 10 * phase, height: 8 + 10 * phase)
                Circle().fill(color).frame(width: 8, height: 8)
            }
            .frame(width: 18, height: 18)
        }
    }
}

struct BlinkingCaret: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.55)) { timeline in
            let visible = reduceMotion || Int(timeline.date.timeIntervalSinceReferenceDate / 0.55) % 2 == 0
            RoundedRectangle(cornerRadius: 1).fill(mint).frame(width: 2, height: 26).opacity(visible ? 1 : 0)
        }
    }
}

struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.width * 0.38, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 7 * sin(animatableData * .pi * 4), y: 0))
    }
}

struct ConfettiBurst: View {
    private struct Particle {
        var angle: Double, speed: Double, spin: Double, size: CGSize, color: Color
    }
    @State private var start = Date()
    @State private var particles: [Particle] = (0..<80).map { _ in
        Particle(angle: .random(in: -Double.pi * 0.95 ... -Double.pi * 0.05), speed: .random(in: 260...620),
                 spin: .random(in: -9...9), size: CGSize(width: .random(in: 5...9), height: .random(in: 9...15)),
                 color: [mint, aqua, .white, Color(red: 0.98, green: 0.82, blue: 0.4)].randomElement()!)
    }
    private let duration = 2.4

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let t = timeline.date.timeIntervalSince(start)
                    guard t < duration else { return }
                    for particle in particles {
                        let x = size.width / 2 + cos(particle.angle) * particle.speed * t
                        let y = size.height * 0.55 + sin(particle.angle) * particle.speed * t + 520 * t * t
                        var copy = context
                        copy.opacity = max(0, 1 - t / duration)
                        copy.translateBy(x: x, y: y)
                        copy.rotate(by: .radians(particle.spin * t))
                        copy.fill(Path(roundedRect: CGRect(x: -particle.size.width / 2, y: -particle.size.height / 2,
                                                           width: particle.size.width, height: particle.size.height), cornerRadius: 2),
                                  with: .color(particle.color))
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}

struct AuroraBackground: View {
    var step: OnboardingStep
    var body: some View {
        let tint = step == .permission ? aqua : mint
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                canvas
                Circle().fill(tint.opacity(0.30)).frame(width: 440).blur(radius: 120)
                    .offset(x: -200 + cos(t * 0.21) * 140, y: -180 + sin(t * 0.17) * 70)
                Circle().fill(aqua.opacity(0.20)).frame(width: 400).blur(radius: 130)
                    .offset(x: 240 + sin(t * 0.13) * 160, y: 160 + cos(t * 0.19) * 80)
                Circle().fill(Color.purple.opacity(0.10)).frame(width: 360).blur(radius: 140)
                    .offset(x: cos(t * 0.09) * 220, y: 240 + sin(t * 0.11) * 40)
                RadialGradient(colors: [.clear, .black.opacity(0.45)], center: .center, startRadius: 240, endRadius: 620)
            }
        }
        .animation(.easeInOut(duration: 0.8), value: step)
        .ignoresSafeArea()
    }
}

struct ProgressDots: View {
    var step: OnboardingStep
    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { item in
                Capsule()
                    .fill(item == step ? mint : .white.opacity(item.rawValue < step.rawValue ? 0.5 : 0.16))
                    .frame(width: item == step ? 22 : 6, height: 6)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: step)
    }
}

struct PrimaryButton: View {
    var title: String
    var systemImage: String?
    var enabled = true
    var compact = false
    var isDefault = true
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title).font(.system(size: compact ? 12 : 14, weight: .semibold))
                if let systemImage { Image(systemName: systemImage).font(.system(size: 12, weight: .bold)) }
            }
            .foregroundStyle(Color.black.opacity(enabled ? 0.85 : 0.45))
            .padding(.horizontal, compact ? 14 : 22).frame(height: compact ? 28 : 40)
            .background(enabled ? mint : mint.opacity(0.25), in: Capsule())
            .shadow(color: mint.opacity(enabled && hover ? 0.55 : 0.2), radius: hover ? 18 : 10)
            .scaleEffect(hover && enabled ? 1.03 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .keyboardShortcut(isDefault ? .defaultAction : nil)
        .onHover { hover = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hover)
        .animation(.easeOut(duration: 0.2), value: enabled)
    }
}

struct QuietButton: View {
    var title: String
    var action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(hover ? 0.9 : 0.5))
                .padding(.horizontal, 14).frame(height: 34)
                .background(.white.opacity(hover ? 0.08 : 0), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Structured shortcut editor

private enum ShortcutMode: Int {
    case modifiersOnly = 0
    case modifierPlusKey = 1
}

struct ShortcutEditorView: View {
    @Binding var shortcut: CustomShortcut
    var onRecordingChanged: ((Bool) -> Void)?
    @State private var mode: ShortcutMode
    // Modifier-only: device-specific bits
    @State private var deviceBits: UInt64
    // Modifier+key: generic modifier flags + keyCode
    @State private var genericMods: UInt64
    @State private var keyCode: UInt16
    @State private var recordingKey = false
    @State private var keyMonitor: Any?

    init(shortcut: Binding<CustomShortcut>, onRecordingChanged: ((Bool) -> Void)? = nil) {
        self._shortcut = shortcut
        self.onRecordingChanged = onRecordingChanged
        let s = shortcut.wrappedValue
        switch s.kind {
        case .rightModifierChord:
            _mode = State(initialValue: .modifiersOnly)
            _deviceBits = State(initialValue: CustomShortcut.deviceRightCommand | CustomShortcut.deviceRightOption)
            _genericMods = State(initialValue: 0)
            _keyCode = State(initialValue: 0)
        case .modifierChord:
            _mode = State(initialValue: .modifiersOnly)
            _deviceBits = State(initialValue: s.modifiers)
            _genericMods = State(initialValue: 0)
            _keyCode = State(initialValue: 0)
        case .keyCombo:
            _mode = State(initialValue: .modifierPlusKey)
            _deviceBits = State(initialValue: 0)
            _genericMods = State(initialValue: s.modifiers)
            _keyCode = State(initialValue: s.keyCode)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker(L("Shortcut type"), selection: $mode) {
                Text(L("Modifiers only")).tag(ShortcutMode.modifiersOnly)
                Text(L("Modifier + Key")).tag(ShortcutMode.modifierPlusKey)
            }.pickerStyle(.segmented)

            if mode == .modifiersOnly {
                modifierOnlyEditor
            } else {
                modifierPlusKeyEditor
            }
        }
    }

    // MARK: Modifier-only editor

    private var modifierOnlyEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Select 2 or more modifier keys:"))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                deviceBitToggle("Left ⌃",  CustomShortcut.deviceLeftControl)
                deviceBitToggle("Right ⌃", CustomShortcut.deviceRightControl)
                deviceBitToggle("Left ⇧",  CustomShortcut.deviceLeftShift)
                deviceBitToggle("Right ⇧", CustomShortcut.deviceRightShift)
                deviceBitToggle("Left ⌥",  CustomShortcut.deviceLeftOption)
                deviceBitToggle("Right ⌥", CustomShortcut.deviceRightOption)
                deviceBitToggle("Left ⌘",  CustomShortcut.deviceLeftCommand)
                deviceBitToggle("Right ⌘", CustomShortcut.deviceRightCommand)
            }
            if CustomShortcut.deviceModifierCount(deviceBits) >= 2 {
                HStack {
                    Spacer()
                    PrimaryButton(title: L("Apply"), compact: true, isDefault: false) {
                        shortcut = CustomShortcut(kind: .modifierChord, keyCode: 0, modifiers: deviceBits)
                    }
                }
            } else {
                Text(L("Select at least 2 modifiers."))
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
    }

    private func deviceBitToggle(_ label: String, _ bit: UInt64) -> some View {
        let on = deviceBits & bit != 0
        return Button {
            deviceBits ^= bit
        } label: {
            HStack(spacing: 6) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .foregroundStyle(on ? mint : .white.opacity(0.4))
                Text(label).font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4).padding(.horizontal, 8)
            .background(on ? mint.opacity(0.08) : .white.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(on ? mint.opacity(0.3) : .white.opacity(0.06), lineWidth: 1))
        }.buttonStyle(.plain)
    }

    // MARK: Modifier+Key editor

    private var modifierPlusKeyEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Modifiers:"))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                genericModToggle("⌃", CGEventFlags.maskControl.rawValue)
                genericModToggle("⌥", CGEventFlags.maskAlternate.rawValue)
                genericModToggle("⇧", CGEventFlags.maskShift.rawValue)
                genericModToggle("⌘", CGEventFlags.maskCommand.rawValue)
            }
            HStack {
                Text(L("Key:")).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                if recordingKey {
                    Text(L("Press a key…"))
                        .font(.system(size: 12)).foregroundStyle(mint)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(mint.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    Button(L("Cancel")) { stopKeyRecording() }
                        .font(.system(size: 11)).foregroundStyle(.orange)
                } else {
                    Text(keyCode > 0 || genericMods != 0 ? CustomShortcut.keyName(for: keyCode) : "–")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    Button(L("Change…")) { startKeyRecording() }
                        .font(.system(size: 11)).foregroundStyle(mint)
                }
            }
            if genericMods != 0 {
                HStack {
                    Spacer()
                    PrimaryButton(title: L("Apply"), compact: true, isDefault: false) {
                        shortcut = CustomShortcut(kind: .keyCombo, keyCode: keyCode, modifiers: genericMods)
                    }
                }
            } else {
                Text(L("Select at least 1 modifier."))
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
    }

    private func genericModToggle(_ label: String, _ flag: UInt64) -> some View {
        let on = genericMods & flag != 0
        return Button {
            genericMods ^= flag
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 36, height: 28)
                .background(on ? mint.opacity(0.15) : .white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(on ? mint.opacity(0.4) : .white.opacity(0.08), lineWidth: 1))
                .foregroundStyle(on ? mint : .white.opacity(0.5))
        }.buttonStyle(.plain)
    }

    private func startKeyRecording() {
        recordingKey = true
        onRecordingChanged?(true)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 { stopKeyRecording(); return nil }
            keyCode = event.keyCode
            stopKeyRecording()
            return nil
        }
    }

    private func stopKeyRecording() {
        recordingKey = false
        onRecordingChanged?(false)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

// MARK: - Quick recorder (convenience)

struct ShortcutRecorderView: View {
    @Binding var shortcut: CustomShortcut
    var onRecordingChanged: ((Bool) -> Void)?
    @State private var recording = false
    @State private var keyMonitor: Any?
    @State private var flagsMonitor: Any?
    @State private var peakDeviceBits: UInt64 = 0
    @State private var liveDisplay = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("Record new shortcut"))
                Spacer()
                Button(recording ? L("Cancel") : L("Record…")) {
                    if recording { stopRecording() } else { startRecording() }
                }
                .foregroundStyle(recording ? .orange : mint)
            }
            if recording {
                Text(liveDisplay.isEmpty ? L("Press modifiers together, or modifier + key…") : liveDisplay)
                    .font(.system(size: 12))
                    .foregroundStyle(mint)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(mint.opacity(0.3), lineWidth: 1))
            }
        }
    }

    private func startRecording() {
        recording = true
        onRecordingChanged?(true)
        peakDeviceBits = 0
        liveDisplay = ""
        // Monitor modifier key changes to support modifier-only shortcuts.
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
            let bits = UInt64(event.modifierFlags.rawValue) & CustomShortcut.deviceModifierMask
            let count = CustomShortcut.deviceModifierCount(bits)
            if count >= 2 {
                peakDeviceBits = bits
                liveDisplay = CustomShortcut.modifierChordDisplay(bits)
            }
            // Modifier released after a valid combo was seen → confirm.
            if count < CustomShortcut.deviceModifierCount(peakDeviceBits) && peakDeviceBits != 0 {
                shortcut = CustomShortcut(kind: .modifierChord, keyCode: 0, modifiers: peakDeviceBits)
                stopRecording()
                return nil
            }
            return event
        }
        // Monitor key presses for modifier + key combos.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let modifierMask: UInt64 = CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue
                | CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskControl.rawValue
            let mods = UInt64(event.modifierFlags.rawValue) & modifierMask
            guard mods != 0 else { return event }
            if event.keyCode == 53 { stopRecording(); return nil }
            shortcut = CustomShortcut(kind: .keyCombo, keyCode: event.keyCode, modifiers: mods)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        onRecordingChanged?(false)
        peakDeviceBits = 0
        liveDisplay = ""
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        keyMonitor = nil
        flagsMonitor = nil
    }
}

