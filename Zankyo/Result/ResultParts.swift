import SwiftUI

/// 結果画面の上の、遊んだ曲の情報（ジャケット・曲名・作曲者・難易度・遊び方）
struct SongBanner: View {
    let song: PlayedSong
    let cover: CGImage?
    let coverURL: URL?
    let style: PlayStyle

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 14) {
            CoverThumbnail(image: cover, url: coverURL)
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.headline)
                    .foregroundStyle(palette.ink)
                    .lineLimit(2)
                Text(song.artist)
                    .font(.subheadline)
                    .foregroundStyle(palette.ink.opacity(0.7))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    chip(song.difficulty)
                    chip(style.title)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(palette.laser)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay {
                RoundedRectangle(cornerRadius: 2).stroke(palette.laser.opacity(0.7), lineWidth: 1)
            }
    }
}

/// 大きく出すランク。動かさず、光らせず、文字の濃さだけで見せる
struct RankEmblem: View {
    let rank: Rank

    @Environment(\.palette) private var palette

    var body: some View {
        Text(rank.rawValue)
            .displayFont(.display(size: 96, weight: .bold))
            .foregroundStyle(palette.ink)
            .accessibilityLabel("ランク \(rank.rawValue)")
    }
}

/// 「ハイスコア更新」「フルコンボ」のバッジ。文字の前に自作の印を置き、角の小さい枠で囲む（光らせない）
struct ResultBadge<Mark: Shape>: View {
    let title: String
    /// 文字の前に置く印（`ResultMarks.swift`）
    let mark: Mark
    let color: NeonColor

    @Environment(\.palette) private var palette
    @ScaledMetric(relativeTo: .subheadline) private var markSize: CGFloat = 15

    var body: some View {
        Label {
            Text(title)
        } icon: {
            mark
                .frame(width: markSize, height: markSize)
        }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(palette.textColor(for: color))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 2).fill(color.color.opacity(0.12))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 2).stroke(color.color, lineWidth: 1)
            }
    }
}

/// 判定の内訳。ぴったり・早い・遅い・向き違い・ミスの数を、ノーツの数に対する棒で見せ、タイミングの傾向を目盛りで見せる
struct BreakdownPanel: View {
    let breakdown: ScoreBreakdown
    let style: PlayStyle
    let rules: ScoringRules
    let maxCombo: Int

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("判定の内訳")
                    .font(.headline)
                    .foregroundStyle(palette.laser)
                Spacer()
                Text("最大コンボ \(maxCombo) / \(breakdown.noteCount)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(palette.ink)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                row("ぴったり", breakdown.perfectCount, palette.laser)
                row("早い", breakdown.earlyCount, palette.right.color)
                row("遅い", breakdown.lateCount, palette.vertical.color)
                if style.usesDirection {
                    row("向き違い", breakdown.badCutCount, palette.anyDirection.color)
                }
                row("ミス", breakdown.missCount, palette.warning)
            }
            if style.breaksComboOnEmptySwing {
                Text("空振り \(breakdown.emptySwingCount) 回（コンボが切れた数）")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(palette.ink.opacity(0.75))
            }
            if let mean = breakdown.meanTimingError {
                TimingGauge(meanTimingError: mean, hitWindow: rules.hitWindow)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(palette.panel.opacity(0.85))
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(palette.ink.opacity(0.15), lineWidth: 1)
                }
        }
    }

    private func row(_ title: String, _ count: Int, _ color: Color) -> some View {
        let fraction = breakdown.noteCount > 0 ? CGFloat(count) / CGFloat(breakdown.noteCount) : 0
        return GridRow {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.ink)
            Rectangle()
                .fill(color.opacity(0.15))
                .frame(height: 8)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(color)
                            .frame(width: proxy.size.width * fraction)
                    }
                }
                .gridColumnAlignment(.leading)
                .accessibilityHidden(true)
            Text("\(count)")
                .font(.subheadline.monospacedDigit().weight(.bold))
                .foregroundStyle(palette.ink)
                .gridColumnAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 切ったタイミングの平均のずれ。真ん中がぴったりで、左が早い・右が遅い（直し方は点の内訳のアドバイスで伝える）
struct TimingGauge: View {
    /// 平均のずれ（秒。負なら早い）
    let meanTimingError: TimeInterval
    /// 目盛りの端に当たるずれ（判定の時間窓）
    let hitWindow: TimeInterval

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("タイミング")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.ink)
                Spacer()
                Text(summary)
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundStyle(palette.laser)
            }
            gauge
                .frame(height: 18)
                .accessibilityHidden(true)
            HStack {
                Text("早い")
                Spacer()
                Text("ぴったり")
                Spacer()
                Text("遅い")
            }
            .font(.caption2)
            .foregroundStyle(palette.ink.opacity(0.6))
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private var gauge: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let ratio = hitWindow > 0 ? min(max(meanTimingError / hitWindow, -1), 1) : 0
            ZStack {
                Rectangle()
                    .fill(palette.ink.opacity(0.12))
                    .frame(height: 6)
                Rectangle()
                    .fill(palette.ink.opacity(0.5))
                    .frame(width: 2, height: 18)
                Circle()
                    .fill(palette.laser)
                    .frame(width: 14, height: 14)
                    .offset(x: (width / 2 - 7) * CGFloat(ratio))
            }
            .frame(width: width, height: proxy.size.height)
        }
    }

    /// 「平均 23ms 早い」のような傾向の文
    private var summary: String {
        let milliseconds = Int((abs(meanTimingError) * 1_000).rounded())
        switch TimingTendency(meanTimingError: meanTimingError) {
        case .onTime: return "平均 \(milliseconds)ms・ちょうど"
        case .early: return "平均 \(milliseconds)ms 早め"
        case .late: return "平均 \(milliseconds)ms 遅め"
        }
    }
}

/// 点の内訳。1 ノーツあたりの「振りの強さ」と「タイミング」の点の平均を棒で見せ、次に気をつけるとよいことと、スコアの仕組みへの入り口を置く
struct PointsPanel: View {
    let breakdown: ScoreBreakdown
    let onShowGuide: () -> Void

    @Environment(\.palette) private var palette
    /// アドバイスの前に置く墨の点の大きさ
    @ScaledMetric(relativeTo: .subheadline) private var adviceMarkSize: CGFloat = 13

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("点の内訳（1 ノーツの平均）")
                .font(.headline)
                .foregroundStyle(palette.laser)
            meter("振りの強さ", value: breakdown.averageSwing, max: CutScore.maxSwing, color: palette.right.color)
            meter("タイミング", value: breakdown.averageAccuracy, max: CutScore.maxAccuracy, color: palette.vertical.color)
            if let advice = breakdown.advice {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    InkDropMark()
                        .foregroundStyle(palette.textColor(for: palette.anyDirection))
                        .frame(width: adviceMarkSize, height: adviceMarkSize)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                        .accessibilityHidden(true)
                    Text(advice.message)
                        .font(.subheadline)
                        .foregroundStyle(palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            Button(action: onShowGuide) {
                Label("スコアの仕組み", systemImage: "questionmark.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.laser)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4).stroke(palette.laser.opacity(0.7), lineWidth: 1)
                    }
                    .contentShape(.rect(cornerRadius: 4))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(palette.panel.opacity(0.85))
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(palette.ink.opacity(0.15), lineWidth: 1)
                }
        }
    }

    private func meter(_ title: String, value: Double, max: Int, color: Color) -> some View {
        let fraction = max > 0 ? CGFloat(min(value, Double(max)) / Double(max)) : 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.ink)
                Spacer()
                Text("\(Int(value.rounded())) / \(max)")
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundStyle(palette.ink)
            }
            Rectangle()
                .fill(color.opacity(0.15))
                .frame(height: 8)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(color)
                            .frame(width: proxy.size.width * fraction)
                    }
                }
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}
