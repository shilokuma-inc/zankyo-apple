import SwiftUI

/// 振りの閾値を変えるスライダー。頭の動きの表示（`HeadIndicatorView`）の下に置き、頭を振って確かめながら変えられるようにする
///
/// 変えるのは今の遊び方の閾値（ヘドバンは振りの速さ、向きを合わせて切る遊び方は上下（うなずき）の閾値。左右は変えない）。
/// 変えた値はすぐに表示と検出（`MotionMonitor.detection`）に反映し、保存する
struct SwingSensitivityView: View {
    let monitor: MotionMonitor
    var store = SwingSensitivityStore()

    var body: some View {
        let style = monitor.detection.style
        let threshold = monitor.detection.adjustableThreshold(for: style)
        let defaultThreshold = SwingSensitivityStore.defaultThreshold(for: style)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.title(for: style))
                    .font(.headline)
                Spacer()
                Text("\(threshold, specifier: "%.1f") rad/s")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: binding(for: style), in: SwingSensitivityStore.thresholdRange, step: 0.1) {
                Text(Self.title(for: style))
            } minimumValueLabel: {
                Text("軽く")
            } maximumValueLabel: {
                Text("強く")
            }
            .accessibilityValue("\(threshold, specifier: "%.1f") ラジアン毎秒")
            Text(explanation(for: style))
                .font(.footnote)
                .foregroundStyle(.secondary)
            if abs(threshold - defaultThreshold) > 0.01 {
                Button("既定の \(defaultThreshold, specifier: "%.1f") rad/s に戻す") {
                    store.resetThreshold(for: style)
                    monitor.detection.setAdjustableThreshold(defaultThreshold, for: style)
                }
                .font(.footnote)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 16))
    }

    private static func title(for style: PlayStyle) -> String {
        switch style {
        case .headbang: "振りの閾値"
        case .directional: "上下の振りの閾値"
        }
    }

    private func explanation(for style: PlayStyle) -> String {
        switch style {
        case .headbang:
            return "小さくするほど、軽い振りで「切った」とみなします。向きは問いません。プレイの判定にも使います。"
        case .directional:
            let yaw = monitor.detection.directional.yawThreshold.formatted(.number.precision(.fractionLength(1)))
            return "小さくするほど、軽いうなずきで「切った」とみなします（左右は \(yaw) rad/s）。プレイの判定にも使います。"
        }
    }

    /// スライダーの刻み（0.1）で丸めてから反映・保存する（浮動小数の誤差で 1.5000000000000002 のような値を残さない）
    private func binding(for style: PlayStyle) -> Binding<Double> {
        Binding(get: { monitor.detection.adjustableThreshold(for: style) }, set: { value in
            let rounded = (value * 10).rounded() / 10
            monitor.detection.setAdjustableThreshold(rounded, for: style)
            store.save(threshold: rounded, for: style)
        })
    }
}

#Preview {
    SwingSensitivityView(
        monitor: MotionMonitor(base: RecordedMotionInput(samples: [])),
        store: SwingSensitivityStore(suiteName: "Preview.SwingSensitivity")
    )
    .padding()
}
