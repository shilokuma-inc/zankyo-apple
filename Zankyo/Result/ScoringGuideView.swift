import SwiftUI

/// スコアの仕組みと、ハイスコアを狙うコツの説明。数値はスコアの計算の係数（`ScoringRules`・`ScoreKeeper`・`Rank`）から作るので、
/// 係数を調整しても説明とずれない
struct ScoringGuideView: View {
    var rules = ScoringRules()

    var body: some View {
        List {
            Section {
                Text(overview)
                LabeledContent("振りの強さ（最大 \(CutScore.maxSwing) 点）") {
                    Text(swingDescription)
                }
                LabeledContent("タイミング（最大 \(CutScore.maxAccuracy) 点）") {
                    Text("ノーツが線に重なった瞬間に振ると満点です。ずれるほど下がり、±\(Self.milliseconds(rules.hitWindow)) ミリ秒で 0 点になります。")
                }
            } header: {
                Text("1 ノーツの点")
            } footer: {
                Text("100 点と 80 点の違いは、ほとんどが振りの速さの違いです。タイミングの差は最大でも \(CutScore.maxAccuracy) 点です。")
            }
            .labeledContentStyle(.guideItem)

            Section("点の例") {
                ForEach(Self.examples, id: \.title) { example in
                    HStack {
                        Text(example.title)
                        Spacer()
                        Text("\(example.score.swing) + \(example.score.accuracy) = \(example.score.total) 点")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                ForEach(Self.multiplierSteps, id: \.from) { step in
                    LabeledContent("×\(step.from) → ×\(step.to)", value: "続けて \(step.count) 回切る")
                }
                Text("ミス・向き違いで倍率が 1 段下がり、続けた数は数え直しになります。ヘドバンでは、ノーツの無いところで振る（空振り）とコンボが切れ、倍率も 1 段下がります。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("倍率")
            } footer: {
                Text("1 ノーツの点に、そのときの倍率を掛けて足していきます。最大は ×\(ScoreKeeper.maxMultiplier) です。")
            }

            Section {
                Text("判定の表示の「早い・遅い」は、ぴったり（±\(Self.milliseconds(rules.perfectWindow)) ミリ秒以内）からどちらにずれたかです。")
            } header: {
                Text("早い・ぴったり・遅い")
            }

            Section {
                ForEach(Rank.allCases, id: \.self) { rank in
                    LabeledContent(rank.rawValue, value: rank == .rankE ? "それ未満" : "達成率 \(Int((rank.minimumAccuracy * 100).rounded()))% 以上")
                }
            } header: {
                Text("ランク")
            } footer: {
                Text("達成率は、すべてのノーツを満点で切り続けたときの点に対する割合です。")
            }

            Section("ハイスコアのコツ") {
                tip("短く素早く振る", "大きくゆっくり振るより、首を小さく速く振るほうが振りの強さの点が高くなります。")
                tip("線に重なる瞬間に振る", "「早い」「遅い」が続くときは、そのぶん待つ・早めに振ると直せます。")
                tip("キャリブレーションで測る", "イヤホンの遅れを測って保存すると、タイミングが合いやすくなります。")
                tip("コンボを切らない", "ミスするたびに倍率が下がります。×\(ScoreKeeper.maxMultiplier) を保つことがいちばん点に効きます。")
            }
        }
        .navigationTitle("スコアの仕組み")
    }

    private var overview: String {
        "1 つのノーツは最大 \(CutScore.maxTotal) 点です。"
            + "「振りの強さ（最大 \(CutScore.maxSwing) 点）」と「タイミング（最大 \(CutScore.maxAccuracy) 点）」の合計で決まります。"
    }

    private var swingDescription: String {
        let perSecond = Self.degrees(rules.fullSwingRate)
        let perExample = Self.degrees(rules.fullSwingRate * Self.examplePeriod)
        return "首を振る速さで決まります。1 秒に約 \(perSecond)° の速さ（\(Self.examplePeriodText) で約 \(perExample)° 振るくらい）で満点です。"
    }

    private func tip(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - 係数から作る値

    /// 振りの速さの例に使う時間（秒）
    static let examplePeriod: TimeInterval = 0.2
    static var examplePeriodText: String { "\(examplePeriod.formatted(.number.precision(.fractionLength(0...1)))) 秒" }

    static func degrees(_ radians: Double) -> Int {
        Int((radians * 180 / .pi).rounded())
    }

    static func milliseconds(_ seconds: TimeInterval) -> Int {
        Int((seconds * 1_000).rounded())
    }

    /// 点の例。実際の計算（`CutScore`）で求める
    static var examples: [(title: String, score: CutScore)] {
        let rules = ScoringRules()
        let full = rules.fullSwingRate
        return [
            ("速く振って、ぴったり", CutScore(peakRate: full, timingError: 0, rules: rules)),
            ("速く振って、少しずれた", CutScore(peakRate: full, timingError: rules.hitWindow / 2, rules: rules)),
            ("少しゆっくり、ぴったり", CutScore(peakRate: full * 0.8, timingError: 0, rules: rules)),
            ("ゆっくり、少しずれた", CutScore(peakRate: full * 0.5, timingError: rules.hitWindow / 2, rules: rules))
        ]
    }

    /// 倍率の 1 段。`from` 倍から `count` 回続けて切ると `to` 倍になる
    struct MultiplierStep {
        let from: Int
        let to: Int
        let count: Int
    }

    /// 倍率の段の上がり方（小さい倍率から）
    static var multiplierSteps: [MultiplierStep] {
        ScoreKeeper.multiplierSteps.keys.sorted().compactMap { from in
            ScoreKeeper.multiplierSteps[from].map { MultiplierStep(from: from, to: from * 2, count: $0) }
        }
    }
}

/// 説明の項目。見出しの下に説明文を折り返して出す
private struct GuideItemLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            configuration.label.font(.headline)
            configuration.content
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private extension LabeledContentStyle where Self == GuideItemLabeledContentStyle {
    static var guideItem: Self { GuideItemLabeledContentStyle() }
}

#Preview {
    NavigationStack {
        ScoringGuideView()
    }
}
