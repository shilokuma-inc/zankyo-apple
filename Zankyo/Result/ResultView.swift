import SwiftUI

/// プレイを終えたときの結果。操作（もう一度・閉じる）は片手の親指が届く画面下に置く
struct ResultView: View {
    let result: PlayResult
    let previousBest: PlayResult?
    let isNewRecord: Bool
    /// 点の内訳（nil なら出さない）
    var breakdown: ScoreBreakdown?
    /// もう一度遊ぶ（nil ならボタンを出さない）
    var onRetry: (() -> Void)?
    let onClose: () -> Void

    @State private var showsGuide = false

    var body: some View {
        VStack(spacing: 16) {
            ScrollView {
                VStack(spacing: 20) {
                    Text(result.rank.rawValue)
                        .font(.system(size: 96, weight: .black))
                        .foregroundStyle(.tint)
                        .accessibilityLabel("ランク \(result.rank.rawValue)")
                    VStack(spacing: 4) {
                        Text(result.score, format: .number)
                            .font(.largeTitle.monospacedDigit().bold())
                        Text(result.accuracy, format: .percent.precision(.fractionLength(1)))
                            .font(.title3.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if isNewRecord {
                        Label("ハイスコア更新", systemImage: "crown.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)
                    } else if let previousBest {
                        Text("ハイスコア \(previousBest.score)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if result.isFullCombo {
                        Text("フルコンボ")
                            .font(.headline)
                    }
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                        row("最大コンボ", "\(result.maxCombo)")
                        row("ヒット", "\(result.hitCount) / \(result.noteCount)")
                        row("ミス", "\(result.missCount)")
                    }
                    .font(.body.monospacedDigit())
                    if let breakdown {
                        BreakdownCard(breakdown: breakdown) { showsGuide = true }
                    } else {
                        Button("スコアの仕組み", systemImage: "questionmark.circle") { showsGuide = true }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
            }
            VStack(spacing: 8) {
                if let onRetry {
                    Button(action: onRetry) {
                        Text("もう一度").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button(action: onClose) {
                    Text("閉じる").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
        .padding()
        .sheet(isPresented: $showsGuide) {
            NavigationStack {
                ScoringGuideView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("閉じる") { showsGuide = false }
                        }
                    }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value)
        }
    }
}

/// 点の内訳。1 ノーツあたりの「振りの強さ」と「タイミング」の平均と、次に気をつけるとよいこと
private struct BreakdownCard: View {
    let breakdown: ScoreBreakdown
    let onShowGuide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("点の内訳（1 ノーツの平均）")
                .font(.headline)
            meter("振りの強さ", value: breakdown.averageSwing, max: CutScore.maxSwing)
            meter("タイミング", value: breakdown.averageAccuracy, max: CutScore.maxAccuracy)
            Text("ぴったり \(breakdown.perfectCount)・早い \(breakdown.earlyCount)・遅い \(breakdown.lateCount)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
            if let advice = breakdown.advice {
                Label(advice.message, systemImage: "lightbulb")
                    .font(.subheadline)
            }
            Button("スコアの仕組み", systemImage: "questionmark.circle", action: onShowGuide)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 16))
    }

    private func meter(_ title: String, value: Double, max: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.rounded())) / \(max)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            ProgressView(value: min(value, Double(max)), total: Double(max))
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ResultView(
        result: PlayResult(
            score: 18_420,
            maxScore: 21_850,
            maxCombo: 96,
            hitCount: 118,
            missCount: 2,
            noteCount: 120,
            playedAt: .now,
            scoringVersion: ScoringRules.version
        ),
        previousBest: nil,
        isNewRecord: true,
        onRetry: {},
        onClose: {}
    )
}
