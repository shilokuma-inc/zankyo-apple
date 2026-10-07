import SwiftUI

/// 音に合わせて首を振ってもらい、音と動きのずれを測る画面。操作は片手の親指が届く画面下に置く
struct CalibrationView: View {
    let model: CalibrationModel
    /// 頭の動きの見える化に使う
    let motion: MotionMonitor

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if model.isMeasuring {
                    // 測っている間は説明を引っ込め、振るタイミングの手がかりを大きく出す。頭の動きはプレイ中と同じく小さく出す
                    CalibrationCueView(cue: model.cue, cutTimes: model.cutTimes, now: { model.currentTime }, motion: motion)
                    controls
                } else if model.canMeasure {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            explanation
                            HeadIndicatorView(monitor: motion)
                            phaseContent
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    controls
                } else {
                    MotionRequirementView(status: model.input.status)
                }
            }
            .padding()
            .navigationTitle("キャリブレーション")
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("イヤホンを付けて、クリック音に合わせて首を振ってください。")
            Text("最初の 4 回の高い音は聞くだけ。続く低い音ごとに、左右か上下に 1 回ずつ振ります。")
                .foregroundStyle(.secondary)
            Text("測っている間は、上から降りてくる印が線に重なる瞬間に音が鳴ります。")
                .foregroundStyle(.secondary)
            Text("保存中のずれ: \(savedOffsetText)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var phaseContent: some View {
        switch model.phase {
        case .idle, .measuring:
            // 測っている間は `CalibrationCueView` が進み具合を出す
            EmptyView()
        case .finished(let result):
            VStack(alignment: .leading, spacing: 4) {
                Text("ずれ: \(Self.format(result.offset))")
                    .font(.title2.bold())
                Text(result.offset >= 0 ? "動きが音より遅れています。判定でこの分を補います。" : "動きが音より早くなっています。判定でこの分を補います。")
                Text("数えた振り: \(result.matchedCount) 回・ばらつき: \(Int((result.spread * 1_000).rounded())) ms")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            Text(message)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder private var controls: some View {
        switch model.phase {
        case .idle, .failed:
            Button(action: model.start) {
                Text(model.phase == .idle ? "測り始める" : "もう一度測る")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        case .measuring:
            Button(role: .cancel, action: model.cancel) {
                Text("中止").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        case .finished:
            VStack(spacing: 8) {
                Button(action: model.save) {
                    Text("保存する").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button(action: model.start) {
                    Text("もう一度測る").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
    }

    private var savedOffsetText: String {
        model.savedOffset.map(Self.format) ?? "未測定（0 ms として判定します）"
    }

    private static func format(_ offset: TimeInterval) -> String {
        let milliseconds = Int((offset * 1_000).rounded())
        return milliseconds > 0 ? "+\(milliseconds) ms" : "\(milliseconds) ms"
    }
}

#Preview {
    let motion = MotionMonitor(base: RecordedMotionInput(samples: []))
    CalibrationView(model: CalibrationModel(input: motion, metronome: SilentMetronome()), motion: motion)
}

/// プレビュー用。音を鳴らさず、今から 0.6 秒おきのクリックの時刻だけを返す
private final class SilentMetronome: Metronome {
    func start(bpm: Double, beats: Int) throws -> [TimeInterval] {
        let now = ProcessInfo.processInfo.systemUptime
        return (0..<beats).map { now + 0.5 + Double($0) * 60 / bpm }
    }

    func stop() {}
}
