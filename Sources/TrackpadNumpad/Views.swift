import SwiftUI
import ServiceManagement
import TrackpadCore

private let ink = Color.white.opacity(0.9)

private struct TrackpadMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct KeypadView: View {
    var highlighted: UInt16?
    var compact = false
    var layout: KeypadLayout = .left

    var body: some View {
        GeometryReader { geometry in
            let gap: CGFloat = compact ? 5 : 7
            let width = (geometry.size.width - gap * CGFloat(PadKey.columnCount - 1)) / CGFloat(PadKey.columnCount)
            let height = (geometry.size.height - gap * CGFloat(PadKey.rowCount - 1)) / CGFloat(PadKey.rowCount)
            ZStack(alignment: .topLeading) {
                ForEach(layout.keys) { key in
                    let active = highlighted == key.id
                    let operation = key.isOperation
                    RoundedRectangle(cornerRadius: compact ? 7 : 10)
                        .fill(active ? mint : Color.white.opacity(operation ? 0.09 : 0.035))
                        .overlay {
                            RoundedRectangle(cornerRadius: compact ? 7 : 10)
                                .strokeBorder(active ? mint : Color.white.opacity(0.065), lineWidth: 1)
                        }
                        .overlay {
                            Text(key.label)
                                .font(.system(size: compact ? 17 : 23, weight: .medium, design: .rounded))
                                .foregroundStyle(active ? Color.black.opacity(0.85) : ink)
                        }
                        .frame(width: width * CGFloat(key.columns) + gap * CGFloat(key.columns - 1),
                               height: height * CGFloat(key.rows) + gap * CGFloat(key.rows - 1))
                        .offset(x: CGFloat(key.column) * (width + gap), y: CGFloat(key.row) * (height + gap))
                        .animation(active || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                            ? nil : .easeOut(duration: 0.08), value: active)
                        .accessibilityLabel(key.label)
                }
            }
        }
    }
}

struct GuideView: View {
    @ObservedObject var model: AppController
    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    KeypadView(highlighted: model.highlighted, compact: true, layout: model.controlSide)
                        .transformEffect(model.effectiveTransform.inverse.screenTransform(size: geometry.size))
                        .animation(.easeOut(duration: (NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || model.calibrationTracking) ? 0 : 0.18), value: model.effectiveTransform)
                    ForEach(Array(model.touches.enumerated()), id: \.offset) { _, touch in
                        Circle().fill(mint.opacity(0.25))
                            .overlay(Circle().strokeBorder(mint.opacity(0.8), lineWidth: 1))
                            .frame(width: 18, height: 18)
                            .position(x: min(1, max(0, touch.x)) * geometry.size.width,
                                      y: (1 - min(1, max(0, touch.y))) * geometry.size.height)
                    }
                }
                .clipped()
            }
            .aspectRatio(PadGeometry.aspectRatio, contentMode: .fit)
            .padding(14)
            .background {
                TrackpadMaterial()
                    .overlay(Color.black.opacity(0.22))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.12), lineWidth: 1))
            Text(L("Press Esc to exit"))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
                .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
        }
        .padding(8)
        .overlay {
            OverlayDragSurface(began: { model.beginOverlayDrag() },
                moved: { model.moveOverlay(to: $0, pointer: $1) }, ended: { model.endOverlayDrag() })
        }
        .environment(\.colorScheme, .dark)
    }
}

private extension PadTransform {
    /// Convert bottom-left normalized coordinates to top-left view pixels.
    func screenTransform(size: CGSize) -> CGAffineTransform {
        guard size.width > 0, size.height > 0 else { return .identity }
        return CGAffineTransform(a: a, b: -c * size.height / size.width,
            c: -b * size.width / size.height, d: d,
            tx: size.width * (b + tx), ty: size.height * (1 - d - ty))
    }
}

struct SnapGuideView: View {
    @ObservedObject var model: AppController
    var body: some View {
        GeometryReader { geometry in
            if let snap = model.overlaySnapPreview {
                let bounds = model.overlaySnapBounds
                Path { path in
                    if let x = snap.verticalGuide {
                        let local = x - bounds.minX
                        path.move(to: CGPoint(x: local, y: 0))
                        path.addLine(to: CGPoint(x: local, y: geometry.size.height))
                    }
                    if let y = snap.horizontalGuide {
                        let local = bounds.maxY - y
                        path.move(to: CGPoint(x: 0, y: local))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: local))
                    }
                }.stroke(mint.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(mint.opacity(0.35), lineWidth: 1)
                    .background(mint.opacity(0.035), in: RoundedRectangle(cornerRadius: 20))
                    .frame(width: snap.frame.width, height: snap.frame.height)
                    .position(x: snap.frame.midX - bounds.minX, y: bounds.maxY - snap.frame.midY)
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppController
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("NumpadLuma").font(.system(size: 23, weight: .semibold))
                Text(L("Right ⌘ + Right ⌥ to toggle · Esc to exit"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            TabView {
                generalSettings.tabItem { Text(L("General")) }
                regionSettings.tabItem { Text(L("Region")) }
                shortcutSettings.tabItem { Text(L("Shortcut")) }
                hapticSettings.tabItem { Text(L("Haptics")) }
                experimentalSettings.tabItem { Text(L("Experimental")) }
            }
            HStack {
                if !model.trusted {
                    Button(L("Allow Accessibility Access…")) { model.requestPermission() }
                }
                Spacer()
                Button(L("Preview Overlay")) { model.previewGuide() }
            }
            Text(L("Changes are saved automatically. Opening Settings turns off the keypad."))
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 580, height: 700)
        .background(Color(red: 0.10, green: 0.105, blue: 0.11))
        .environment(\.colorScheme, .dark)
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(L("Language"))
                    Spacer()
                    Picker(L("Language"), selection: $model.language) {
                        ForEach(AppLanguage.allCases, id: \.self) { language in
                            Text(language.name).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
                Divider()
                HStack {
                    Toggle(L("Start at Login"), isOn: Binding(
                        get: { model.loginItemEnabled },
                        set: { model.setLoginItem(enabled: $0) }
                    ))
                    .toggleStyle(.switch).tint(mint)
                    Spacer()
                    Text(loginItemStatusLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(loginItemStatusColor)
                }
                if model.loginItemStatus == .requiresApproval {
                    Button(L("Open Login Items in System Settings…")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .font(.system(size: 11))
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("Operator Position")).font(.headline)
                    Picker(L("Operator Position"), selection: $model.controlSide) {
                        Text(L("Left")).tag(KeypadLayout.left)
                        Text(L("Right")).tag(KeypadLayout.right)
                    }.pickerStyle(.segmented).labelsHidden()
                    KeypadView(highlighted: nil, compact: true, layout: model.controlSide)
                        .frame(height: 190).padding(14)
                        .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
                }
            Divider()
            HStack {
                Text(L("Overlay Position")).font(.system(size: 12))
                Spacer()
                Button(L("Reset to Bottom Center")) { model.resetOverlayPosition() }
            }
            Text(L("Click and drag the overlay to save its position. It moves out of the way when it would cover the focused input field."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }.padding(20)
    }

    private var regionSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Trackpad Region")).font(.headline)
            Text(L("Drag the edges or corners to limit the active area of your trackpad."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            RegionCropView(region: $model.padRegion, layout: model.controlSide)
                .frame(height: 280)
            HStack {
                if !model.padRegion.isFullPad {
                    let w = Int(model.padRegion.width * 100)
                    let h = Int(model.padRegion.height * 100)
                    Text("\(w)% × \(h)%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("Reset to Full Trackpad")) { model.resetPadRegion() }
                    .disabled(model.padRegion.isFullPad)
            }
            Spacer(minLength: 0)
        }.padding(20)
    }

    private var shortcutSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("Activation Shortcut")).font(.headline)
                Text(L("Choose a keyboard shortcut to toggle the keypad on and off."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                HStack {
                    Text(L("Current shortcut"))
                    Spacer()
                    Text(model.shortcutDisplay)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.1), lineWidth: 1))
                }
                Divider()
                ShortcutEditorView(shortcut: Binding(
                    get: { model.currentShortcut },
                    set: { model.setShortcut($0) }
                ))
                Divider()
                ShortcutRecorderView(shortcut: Binding(
                    get: { model.currentShortcut },
                    set: { model.setShortcut($0) }
                ))
                Divider()
                Button(L("Reset to Default (Right ⌘ + Right ⌥)")) {
                    model.setShortcut(.defaultShortcut)
                }
            }.padding(20)
        }
    }

    private var hapticSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle(L("Enable Haptics"), isOn: $model.hapticsEnabled)
                .font(.headline)
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                Text(L("Key Input")).font(.headline)
                Toggle(L("On touch down"), isOn: $model.hapticTouchDown)
                Toggle(L("When a tap is confirmed on release"), isOn: $model.hapticInputConfirmed)
                Divider()
                Text(L("Center Guide for 5")).font(.headline)
                Toggle(L("When entering the center"), isOn: $model.hapticFiveEnter)
                Toggle(L("When leaving the center"), isOn: $model.hapticFiveExit)
                Text(L("A stronger haptic marks the small center region."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Divider()
                Text(L("Experimental Calibration")).font(.headline)
                Toggle(L("When finger calibration is applied"), isOn: $model.hapticCalibration)
            }
            .disabled(!model.hapticsEnabled)
            Spacer(minLength: 0)
        }
        .toggleStyle(.switch).tint(mint)
        .padding(20)
    }

    private var loginItemStatusLabel: String {
        switch model.loginItemStatus {
        case .enabled: return L("Enabled")
        case .notRegistered: return L("Not registered")
        case .requiresApproval: return L("Requires approval in System Settings")
        case .notFound: return L("Unavailable (requires signed app bundle)")
        @unknown default: return L("Unknown")
        }
    }

    private var loginItemStatusColor: Color {
        switch model.loginItemStatus {
        case .enabled: return .green
        case .requiresApproval: return .orange
        case .notFound: return .red
        case .notRegistered: return .secondary
        @unknown default: return .secondary
        }
    }

    private var experimentalSettings: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $model.experimentalCalibration) {
                        HStack(spacing: 8) {
                            Text(L("Calibrate with Finger Positions")).fontWeight(.medium)
                            Text(L("Experimental")).font(.system(size: 10)).foregroundStyle(mint)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(mint.opacity(0.1), in: Capsule())
                        }
                    }.toggleStyle(.switch).tint(mint)
                    Text(L("With the keypad on, place three fingers together. Keep the middle finger at the center of 5 and use the outer fingers to adjust rotation and scale. Key shapes and proportions stay the same."))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 8) {
                        Picker(L("Apply Calibration"), selection: $model.calibrationTiming) {
                            Text(L("On Touch")).tag(CalibrationTiming.touchDown)
                            Text(L("On Release")).tag(CalibrationTiming.liftOff)
                        }.pickerStyle(.segmented)
                        Text(L("Defaults to On Touch. Drag with three or four fingers to move, rotate, and scale the layout live. macOS drag, zoom, and desktop-switching gestures are blocked during calibration."))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 12)
                    .disabled(!model.experimentalCalibration)
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(L("Keep Calibration Between Sessions"), isOn: $model.keepCalibrationOnReactivate)
                            .toggleStyle(.switch).tint(mint)
                        Text(L("Keep the last calibration when turning the keypad back on. Turn this off to start each session with the default layout. Applies to the next session."))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 12)
                    .disabled(!model.experimentalCalibration)
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(L("Enable Four-Finger Calibration"), isOn: $model.fourFingerCalibration)
                            .toggleStyle(.switch).tint(mint)
                        Text(L("Place four fingers together. The middle two align with × and − from left to right, adjusting position, rotation, and scale to match their key centers."))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    .disabled(!model.experimentalCalibration)
                    Text(L("The latest calibration applies to the entire layout and is saved separately for each operator position. Turn calibration off to return to the default layout."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .top) {
                        Text(model.calibrationStatus).font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Reset Calibration")) { model.resetCalibration() }.disabled(!model.hasCalibration)
                    }
                }
                .padding(20)
        }
    }
}

// MARK: - Region Crop View

private enum DragHandle: Hashable {
    case topLeft, topRight, bottomLeft, bottomRight
    case top, bottom, leading, trailing
}

struct RegionCropView: View {
    @Binding var region: PadRegion
    var layout: KeypadLayout

    @State private var activeHandle: DragHandle?
    @State private var dragStart: PadRegion?
    @State private var padSize: CGSize = .zero

    private let handleSize: CGFloat = 14
    private let edgeHitSize: CGFloat = 10
    private let minRegionFraction = 0.1

    var body: some View {
        GeometryReader { geometry in
            let pad = padRect(in: geometry.size)
            // Trackpad background
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.08), lineWidth: 1))
                .frame(width: pad.width, height: pad.height)
                .position(x: pad.midX, y: pad.midY)

            // Dimmed area outside region
            let crop = cropRect(in: pad)
            dimOverlay(pad: pad, crop: crop)

            // Keypad preview inside crop
            KeypadView(highlighted: nil, compact: true, layout: layout)
                .frame(width: crop.width - 4, height: crop.height - 4)
                .position(x: crop.midX, y: crop.midY)
                .allowsHitTesting(false)

            // Crop border
            Rectangle()
                .strokeBorder(mint, lineWidth: 2)
                .frame(width: crop.width, height: crop.height)
                .position(x: crop.midX, y: crop.midY)

            // Corner handles
            cornerHandle(.topLeft, at: CGPoint(x: crop.minX, y: crop.minY))
            cornerHandle(.topRight, at: CGPoint(x: crop.maxX, y: crop.minY))
            cornerHandle(.bottomLeft, at: CGPoint(x: crop.minX, y: crop.maxY))
            cornerHandle(.bottomRight, at: CGPoint(x: crop.maxX, y: crop.maxY))

            // Edge handles
            edgeHandle(.top, at: CGPoint(x: crop.midX, y: crop.minY), horizontal: true)
            edgeHandle(.bottom, at: CGPoint(x: crop.midX, y: crop.maxY), horizontal: true)
            edgeHandle(.leading, at: CGPoint(x: crop.minX, y: crop.midY), horizontal: false)
            edgeHandle(.trailing, at: CGPoint(x: crop.maxX, y: crop.midY), horizontal: false)

            Color.clear
                .onAppear { padSize = pad.size }
                .onChange(of: geometry.size) { _ in padSize = padRect(in: geometry.size).size }
        }
        .contentShape(Rectangle())
    }

    private func padRect(in size: CGSize) -> CGRect {
        let aspect = PadGeometry.aspectRatio
        let padW = min(size.width - 16, (size.height - 16) * aspect)
        let padH = padW / aspect
        return CGRect(x: (size.width - padW) / 2, y: (size.height - padH) / 2, width: padW, height: padH)
    }

    private func cropRect(in pad: CGRect) -> CGRect {
        // Trackpad Y is bottom-up, view Y is top-down
        let x = pad.minX + region.minX * pad.width
        let y = pad.minY + (1 - region.maxY) * pad.height
        let w = region.width * pad.width
        let h = region.height * pad.height
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func dimOverlay(pad: CGRect, crop: CGRect) -> some View {
        Canvas { context, _ in
            var path = Path(pad)
            path.addPath(Path(crop))
            context.fill(path, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))
        }
        .allowsHitTesting(false)
    }

    private func cornerHandle(_ handle: DragHandle, at point: CGPoint) -> some View {
        Circle()
            .fill(mint)
            .frame(width: handleSize, height: handleSize)
            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
            .position(point)
            .gesture(dragGesture(handle))
            .onHover { inside in
                if inside {
                    switch handle {
                    case .topLeft, .bottomRight: NSCursor.crosshair.push()
                    case .topRight, .bottomLeft: NSCursor.crosshair.push()
                    default: break
                    }
                } else { NSCursor.pop() }
            }
    }

    private func edgeHandle(_ handle: DragHandle, at point: CGPoint, horizontal: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(mint.opacity(0.8))
            .frame(width: horizontal ? 28 : 6, height: horizontal ? 6 : 28)
            .position(point)
            .gesture(dragGesture(handle))
            .onHover { inside in
                if inside {
                    if horizontal { NSCursor.resizeUpDown.push() } else { NSCursor.resizeLeftRight.push() }
                } else { NSCursor.pop() }
            }
    }

    private func dragGesture(_ handle: DragHandle) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStart == nil { dragStart = region }
                guard let start = dragStart else { return }
                updateRegion(handle: handle, translation: value.translation, start: start, geometry: value)
            }
            .onEnded { _ in
                dragStart = nil
            }
    }

    private func updateRegion(handle: DragHandle, translation: CGSize, start: PadRegion, geometry: DragGesture.Value) {
        guard padSize.width > 0, padSize.height > 0 else { return }

        let dx = translation.width / padSize.width
        // View Y is top-down, trackpad Y is bottom-up
        let dy = -translation.height / padSize.height

        var minX = start.minX
        var minY = start.minY
        var maxX = start.maxX
        var maxY = start.maxY

        switch handle {
        case .topLeft:
            minX = start.minX + dx
            maxY = start.maxY + dy  // top in view = maxY in trackpad coords
        case .topRight:
            maxX = start.maxX + dx
            maxY = start.maxY + dy
        case .bottomLeft:
            minX = start.minX + dx
            minY = start.minY + dy
        case .bottomRight:
            maxX = start.maxX + dx
            minY = start.minY + dy
        case .top:
            maxY = start.maxY + dy
        case .bottom:
            minY = start.minY + dy
        case .leading:
            minX = start.minX + dx
        case .trailing:
            maxX = start.maxX + dx
        }

        // Enforce minimum size and bounds
        minX = max(0, min(minX, maxX - minRegionFraction))
        minY = max(0, min(minY, maxY - minRegionFraction))
        maxX = min(1, max(maxX, minX + minRegionFraction))
        maxY = min(1, max(maxY, minY + minRegionFraction))

        region = PadRegion(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }
}
