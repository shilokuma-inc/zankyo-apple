import SwiftUI

/// 上下（うなずき）の振りの閾値を変えるスライダー。頭の動きの表示（`HeadIndicatorView`）の下に置き、うなずいて確かめながら変えられるようにする
///
/// 変えた値はすぐに表示と検出（`MotionMonitor.detection`）に反映し、保存する。左右の閾値は変えない
struct SwingSensitivityView: View {
    let monitor: MotionMonitor
    var store = SwingSensitivityStore()

    private static let defaultThreshold = CutDetector.Configuration().pitchThreshold

    var body: some View {
        let threshold = monitor.detection.pitchThreshold
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("上下の振りの閾値")
                    .font(.headline)
                Spacer()
                Text("\(threshold, specifier: "%.1f") rad/s")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: pitchThreshold, in: SwingSensitivityStore.pitchThresholdRange, step: 0.1) {
                Text("上下の振りの閾値")
            } minimumValueLabel: {
                Text("軽く")
            } maximumValueLabel: {
                Text("強く")
            }
            .accessibilityValue("\(threshold, specifier: "%.1f") ラジアン毎秒")
            Text("小さくするほど、軽いうなずきで「切った」とみなします（左右は \(monitor.detection.yawThreshold, specifier: "%.1f") rad/s）。プレイの判定にも使います。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if abs(threshold - Self.defaultThreshold) > 0.01 {
                Button("既定の \(Self.defaultThreshold, specifier: "%.1f") rad/s に戻す") {
                    store.reset()
                    monitor.detection.pitchThreshold = Self.defaultThreshold
                }
                .font(.footnote)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 16))
    }

    /// スライダーの刻み（0.1）で丸めてから反映・保存する（浮動小数の誤差で 1.5000000000000002 のような値を残さない）
    private var pitchThreshold: Binding<Double> {
        Binding(get: { monitor.detection.pitchThreshold }, set: { value in
            let rounded = (value * 10).rounded() / 10
            monitor.detection.pitchThreshold = rounded
            store.save(pitchThreshold: rounded)
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
