import SwiftUI

/// 頭の動きの見える化。丸の中の点が正面からの向き、まわりの矢印が検出した振りの向き、棒が振りの強さ（印を超えると振りになる）
///
/// - `large`: キャリブレーションとプレイを始める前。状態の説明と「正面にする」を添える
/// - `compact`: プレイ中のヘッダー。丸と強さだけ
struct HeadIndicatorView: View {
    enum Style {
        case large
        case compact
    }

    let monitor: MotionMonitor
    var style: Style = .large
    /// 画面に出ている間、受け取る側がいなければ自分で取得して向きを見せる
    var previewsWhenIdle = true

    /// 丸の端に当たる向き（ラジアン）。これより大きく向くと端に留まる
    static let maxAngle = Double.pi / 4

    var body: some View {
        Group {
            switch style {
            case .large: large
            case .compact: compact
            }
        }
        .onAppear { if previewsWhenIdle { monitor.startPreview() } }
        .onDisappear { if previewsWhenIdle { monitor.stopPreview() } }
        .onChange(of: monitor.status) {
            // 接続されたら見せ始める
            if previewsWhenIdle { monitor.startPreview() }
        }
        .onChange(of: monitor.isActive) {
            // キャリブレーションを測り終えたときなど、受け取る側が止めたら見せ直す
            if previewsWhenIdle, !monitor.isActive { monitor.startPreview() }
        }
    }

    private var large: some View {
        VStack(spacing: 12) {
            HStack {
                StatusLabel(monitor: monitor)
                Spacer()
                Button("正面にする", systemImage: "scope", action: monitor.recenter)
                    .font(.footnote)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityHint("今の頭の向きを正面にします")
            }
            HeadDial(state: monitor.state, diameter: 140, arrowSize: 28)
                .padding(.vertical, 4)
            StrengthBar(strength: monitor.state.strength)
                .frame(height: 10)
            Text("首を振ると、検出した向きの矢印が光ります。棒が印を超えると「切った」とみなします。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 16))
    }

    private var compact: some View {
        VStack(spacing: 4) {
            HeadDial(state: monitor.state, diameter: 40, arrowSize: 10)
            StrengthBar(strength: monitor.state.strength)
                .frame(width: 56, height: 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("頭の動き")
        .accessibilityValue(monitor.state.highlightedDirection(at: monitor.state.lastSampleTime ?? 0).map(Self.name(of:)) ?? "")
    }

    static func name(of direction: SwingDirection) -> String {
        switch direction {
        case .up: "上"
        case .down: "下"
        case .left: "左"
        case .right: "右"
        }
    }
}

/// 丸と、正面からの向きを表す点、まわりの 4 方向の矢印
private struct HeadDial: View {
    let state: HeadMotionState
    let diameter: CGFloat
    let arrowSize: CGFloat

    var body: some View {
        let highlighted = state.highlightedDirection(at: state.lastSampleTime ?? 0)
        let radius = diameter / 2
        let offset = Self.offset(of: state.orientation, radius: radius)
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.4), lineWidth: 1.5)
            // 正面の十字
            Path { path in
                path.move(to: CGPoint(x: radius, y: radius * 0.6))
                path.addLine(to: CGPoint(x: radius, y: radius * 1.4))
                path.move(to: CGPoint(x: radius * 0.6, y: radius))
                path.addLine(to: CGPoint(x: radius * 1.4, y: radius))
            }
            .stroke(.secondary.opacity(0.4), lineWidth: 1)
            .frame(width: diameter, height: diameter)
            Circle()
                .fill(state.strength >= 1 ? Color.orange : Color.accentColor)
                .frame(width: diameter * 0.18, height: diameter * 0.18)
                .offset(x: offset.width, y: offset.height)
            ForEach(SwingDirection.allCases, id: \.self) { direction in
                Arrow(direction: direction, isLit: direction == highlighted, size: arrowSize)
                    .offset(Self.arrowOffset(direction, distance: radius + arrowSize * 0.75))
            }
        }
        .frame(width: diameter + arrowSize * 3, height: diameter + arrowSize * 3)
        .animation(.easeOut(duration: 0.08), value: state.orientation)
        .accessibilityHidden(true)
    }

    /// 向きを丸の中の位置にする。右を向くと右へ、上を向くと上へ動く
    static func offset(of orientation: HeadOrientation, radius: CGFloat) -> CGSize {
        let limit = HeadIndicatorView.maxAngle
        var x = orientation.yaw / limit
        var y = -orientation.pitch / limit
        let length = (x * x + y * y).squareRoot()
        if length > 1 {
            x /= length
            y /= length
        }
        return CGSize(width: x * radius, height: y * radius)
    }

    static func arrowOffset(_ direction: SwingDirection, distance: CGFloat) -> CGSize {
        switch direction {
        case .up: CGSize(width: 0, height: -distance)
        case .down: CGSize(width: 0, height: distance)
        case .left: CGSize(width: -distance, height: 0)
        case .right: CGSize(width: distance, height: 0)
        }
    }
}

private struct Arrow: View {
    let direction: SwingDirection
    let isLit: Bool
    let size: CGFloat

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .bold))
            // 振った向きは色だけで示す（膨らませない）
            .foregroundStyle(isLit ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
            .animation(.easeOut(duration: 0.12), value: isLit)
    }

    private var symbol: String {
        switch direction {
        case .up: "arrowtriangle.up.fill"
        case .down: "arrowtriangle.down.fill"
        case .left: "arrowtriangle.left.fill"
        case .right: "arrowtriangle.right.fill"
        }
    }
}

/// 振りの強さの棒。印（閾値）を超えると色が変わる
private struct StrengthBar: View {
    let strength: Double
    /// 棒の端に当たる強さ（閾値の何倍か）
    static let maxStrength = 2.0

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fraction = min(max(strength / Self.maxStrength, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(strength >= 1 ? Color.orange : Color.accentColor)
                    .frame(width: width * fraction)
                // 振りとみなす閾値の印
                Rectangle()
                    .fill(.primary.opacity(0.6))
                    .frame(width: 2)
                    .offset(x: width / Self.maxStrength - 1)
            }
        }
        .animation(.easeOut(duration: 0.08), value: strength)
        .accessibilityHidden(true)
    }
}

/// 接続と受け取りの状態
private struct StatusLabel: View {
    let monitor: MotionMonitor

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let receiving = monitor.isReceiving(at: ProcessInfo.processInfo.systemUptime)
            Label {
                Text(text(receiving: receiving))
                    .font(.footnote)
            } icon: {
                Circle()
                    .fill(receiving ? Color.green : monitor.status == .ready ? Color.yellow : Color.secondary)
                    .frame(width: 8, height: 8)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func text(receiving: Bool) -> String {
        if receiving { return "頭の動きを受け取っています" }
        switch monitor.status {
        case .ready:
            return "動きを待っています"
        case .notDetermined:
            return "始めると、動きの取得の許可を求めます"
        case .notAuthorized:
            return "動きの取得が許可されていません"
        case .unsupported:
            return "この端末では頭の動きを使えません"
        case .disconnected:
            #if os(visionOS)
            return "頭の向きの追跡を準備しています"
            #else
            return "イヤホンがつながっていません"
            #endif
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        HeadIndicatorView(monitor: MotionMonitor(base: RecordedMotionInput(samples: [])))
        HeadIndicatorView(monitor: MotionMonitor(base: RecordedMotionInput(samples: [])), style: .compact)
    }
    .padding()
}
