import SwiftUI
import TrackpadCore

private let mint = Color(red: 0.43, green: 0.94, blue: 0.76)
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
            Text("Esc로 해제")
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
                Text("Trackpad Numpad").font(.system(size: 23, weight: .semibold))
                Text("오른쪽 ⌘ + 오른쪽 ⌥로 켜기·끄기 · Esc로 해제")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            TabView {
                generalSettings.tabItem { Text("일반") }
                hapticSettings.tabItem { Text("햅틱") }
                experimentalSettings.tabItem { Text("실험적") }
            }
            HStack {
                if !model.trusted {
                    Button("손쉬운 사용 권한 허용…") { model.requestPermission() }
                }
                Spacer()
                Button("오버레이 미리 보기") { model.previewGuide() }
            }
            Text("설정을 변경하면 자동 저장됩니다. 설정창을 열면 숫자판이 해제됩니다.")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 580, height: 700)
        .background(Color(red: 0.10, green: 0.105, blue: 0.11))
        .environment(\.colorScheme, .dark)
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("조작키 위치").font(.headline)
                    Picker("조작키 위치", selection: $model.controlSide) {
                        Text("왼쪽").tag(KeypadLayout.left)
                        Text("오른쪽").tag(KeypadLayout.right)
                    }.pickerStyle(.segmented).labelsHidden()
                    KeypadView(highlighted: nil, compact: true, layout: model.controlSide)
                        .frame(height: 190).padding(14)
                        .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
                }
            Divider()
            HStack {
                Text("오버레이 위치").font(.system(size: 12))
                Spacer()
                Button("하단 중앙으로 초기화") { model.resetOverlayPosition() }
            }
            Text("오버레이를 눌러 드래그하면 위치가 저장됩니다. 활성화할 때 입력창을 가리면 화면 안의 빈자리로 이동합니다.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }.padding(20)
    }

    private var hapticSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle("햅틱 사용", isOn: $model.hapticsEnabled)
                .font(.headline)
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                Text("숫자·조작키 입력").font(.headline)
                Toggle("손가락을 댈 때", isOn: $model.hapticTouchDown)
                Toggle("손가락을 떼어 입력이 확정될 때", isOn: $model.hapticInputConfirmed)
                Divider()
                Text("5 중심 안내").font(.headline)
                Toggle("중심 영역에 들어갈 때", isOn: $model.hapticFiveEnter)
                Toggle("중심 영역에서 벗어날 때", isOn: $model.hapticFiveExit)
                Text("작은 중심 영역을 지날 때 강한 햅틱을 줍니다.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Divider()
                Text("실험적 보정").font(.headline)
                Toggle("손가락 보정이 적용될 때", isOn: $model.hapticCalibration)
            }
            .disabled(!model.hapticsEnabled)
            Spacer(minLength: 0)
        }
        .toggleStyle(.switch).tint(mint)
        .padding(20)
    }

    private var experimentalSettings: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $model.experimentalCalibration) {
                        HStack(spacing: 8) {
                            Text("손가락 위치로 좌표 보정").fontWeight(.medium)
                            Text("실험적").font(.system(size: 10)).foregroundStyle(mint)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(mint.opacity(0.1), in: Capsule())
                        }
                    }.toggleStyle(.switch).tint(mint)
                    Text("숫자판을 켠 뒤 세 손가락을 동시에 대세요. 가운데 손가락을 5의 중심에 고정하고 양쪽 손가락으로 회전과 크기를 맞춥니다. 이동·회전·균일한 크기 조절을 적용하며 키 모양과 비율은 유지합니다.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("보정 시점", selection: $model.calibrationTiming) {
                            Text("닿을 때").tag(CalibrationTiming.touchDown)
                            Text("뗄 때").tag(CalibrationTiming.liftOff)
                        }.pickerStyle(.segmented)
                        Text("기본은 닿을 때입니다. 세 손가락 또는 네 손가락을 댄 채 드래그하면 배치가 이동·회전·크기에 실시간으로 따라옵니다. 보정 중에는 macOS 드래그·확대/축소·데스크탑 전환 제스처를 차단합니다.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 12)
                    .disabled(!model.experimentalCalibration)
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("다시 켤 때 보정 유지", isOn: $model.keepCalibrationOnReactivate)
                            .toggleStyle(.switch).tint(mint)
                        Text("켜면 마지막 보정을 이어 씁니다. 끄면 숫자판을 켤 때마다 기본 배치로 시작합니다. 변경은 다음 활성화부터 적용됩니다.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 12)
                    .disabled(!model.experimentalCalibration)
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("4손가락 보정 추가", isOn: $model.fourFingerCalibration)
                            .toggleStyle(.switch).tint(mint)
                        Text("네 손가락을 동시에 대면 가운데 두 손가락을 왼쪽부터 ×·−에 맞춥니다. 두 키의 중앙이 손가락에 오도록 이동·회전·균일한 크기 조절을 적용합니다.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    .disabled(!model.experimentalCalibration)
                    Text("마지막 보정이 전체 배치에 적용됩니다. 조작키 방향별로 저장하며, 기능을 끄면 기본 배치로 돌아갑니다.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .top) {
                        Text(model.calibrationStatus).font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Button("보정 초기화") { model.resetCalibration() }.disabled(!model.hasCalibration)
                    }
                }
                .padding(20)
        }
    }
}
