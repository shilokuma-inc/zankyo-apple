import SwiftUI

/// 音に合わせて首を振ってもらい、音と動きのずれを測る画面。操作は片手の親指が届く画面下に置く
struct CalibrationView: View {
    let model: CalibrationModel
    /// 頭の動きの見える化に使う
    let motion: MotionMonitor

    @Environment(\.palette) private var palette

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if model.canMeasure || model.isMeasuring {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            explanation
                            // 測り終えた結果は、頭の動きの表示に押し出されて隠れないよう先に出す
                            phaseContent
                            HeadIndicatorView(monitor: motion)
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
        // 測っている間は、プレイ画面と同じく全面に出す
        .measuringCover(isPresented: measuringPresented) { measuringContent }
    }

    /// 測り終える・中止すると閉じる
    private var measuringPresented: Binding<Bool> {
        Binding(get: { model.isMeasuring }, set: { isPresented in
            if !isPresented, model.isMeasuring { model.cancel() }
        })
    }

    /// 測っている間の画面。プレイ画面と同じ空間に、振るタイミングの手がかりと中止だけを置く。
    /// 頭の動きはプレイ中と同じく小さく出す
    private var measuringContent: some View {
        VStack(spacing: 16) {
            CalibrationCueView(cue: model.cue, cutTimes: model.cutTimes, now: { model.currentTime }, motion: motion)
            Button(role: .cancel, action: model.cancel) {
                Text("中止").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding([.horizontal, .bottom])
        }
        .padding(.top)
        .background { PlayfieldBackdrop() }
        .preferredColorScheme(palette.colorScheme)
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("イヤホンを付けて、クリック音に合わせて首を振ってください。")
            Text("最初の 4 回の高い音は聞くだけ。続く低い音ごとに、左右か上下に 1 回ずつ振ります。")
                .foregroundStyle(.secondary)
            Text("測っている間はプレイ画面と同じく、上から降りてくる印が判定の線に重なる瞬間に音が鳴ります。")
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

private extension View {
    /// 測っている間の画面を全面に出す。macOS には全面のモーダルが無いのでシートにする（`SongDetailView` のプレイ画面と同じ）
    func measuringCover<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(macOS)
        sheet(isPresented: isPresented) {
            content()
                .frame(minWidth: 420, minHeight: 640)
                .interactiveDismissDisabled()
        }
        #else
        fullScreenCover(isPresented: isPresented, content: content)
        #endif
    }
}
