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
                Capsule().stroke(palette.laser.opacity(0.7), lineWidth: 1)
            }
    }
}

/// 大きく光るランク。現れるときは大きく光ってから縮んで収まり、その後はゆっくり光を明滅させる（「視差効果を減らす」では明滅させない）
struct RankEmblem: View {
    let rank: Rank
    let isShown: Bool

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let color = rankColor
        Text(rank.rawValue)
            .font(.system(size: 96, weight: .black, design: .rounded))
            .foregroundStyle(palette.ink)
            .shadow(color: palette.glow(color), radius: 6)
            .phaseAnimator(reduceMotion || !isShown ? [1.0] : [1.0, 0.55]) { content, phase in
                content
                    .shadow(color: palette.glow(color, phase), radius: 24)
                    .shadow(color: palette.glow(color, 0.6 * phase), radius: 48)
            } animation: { _ in
                .easeInOut(duration: 1.4)
            }
            .scaleEffect(isShown || reduceMotion ? 1 : 2.2)
            .opacity(isShown ? 1 : 0)
            .accessibilityLabel("ランク \(rank.rawValue)")
    }

    /// ランクの光の色。上のランクほど目立つ色にする
    private var rankColor: Color {
        switch rank {
        case .rankSS: palette.anyDirection.color
        case .rankS: palette.laser
        case .rankA: palette.right.color
        case .rankB: palette.vertical.color
        case .rankC, .rankD, .rankE: palette.warning
        }
    }
}

/// 「ハイスコア更新」「フルコンボ」の光るバッジ
struct ResultBadge: View {
    let title: String
    let systemImage: String
    let color: NeonColor

    @Environment(\.palette) private var palette

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(.subheadline, design: .rounded, weight: .heavy))
            .foregroundStyle(palette.textColor(for: color))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                Capsule().fill(color.color.opacity(0.15))
            }
            .overlay {
                Capsule().stroke(color.color, lineWidth: 1.5)
            }
            .shadow(color: palette.glow(color.color, 0.8), radius: 10)
    }
}

/// 数え上がる点数。`value` を動かしたアニメーションの途中の値を、整数にして出す
struct CountingNumber: View, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(Int(value.rounded()), format: .number)
    }
}

/// 判定の内訳。ぴったり・早い・遅い・向き違い・ミスの数を、ノーツの数に対する棒で見せ、タイミングの傾向を目盛りで見せる
struct BreakdownPanel: View {
    let breakdown: PlayBreakdown
    let style: PlayStyle
    let rules: ScoringRules
    let maxCombo: Int
    /// 棒の伸び具合（0〜1）。現れるときに伸ばす
    let progress: CGFloat

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("判定の内訳")
                    .font(.system(.headline, design: .rounded, weight: .heavy))
                    .foregroundStyle(palette.laser)
                Spacer()
                Text("最大コンボ \(maxCombo) / \(breakdown.noteCount)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(palette.ink)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                row("ぴったり", breakdown.perfect, palette.laser)
                row("早い", breakdown.early, palette.right.color)
                row("遅い", breakdown.late, palette.vertical.color)
                if style.usesDirection {
                    row("向き違い", breakdown.badCut, palette.anyDirection.color)
                }
                row("ミス", breakdown.miss, palette.warning)
            }
            if style.breaksComboOnEmptySwing {
                Text("空振り \(breakdown.emptySwing) 回（コンボが切れた数）")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(palette.ink.opacity(0.75))
            }
            if let mean = breakdown.meanTimingError {
                TimingGauge(meanTimingError: mean, hitWindow: rules.hitWindow, progress: progress)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(palette.panel.opacity(0.55))
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(palette.laser.opacity(0.45), lineWidth: 1)
                }
        }
    }

    private func row(_ title: String, _ count: Int, _ color: Color) -> some View {
        let fraction = breakdown.noteCount > 0 ? CGFloat(count) / CGFloat(breakdown.noteCount) : 0
        return GridRow {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.ink)
            Capsule()
                .fill(color.opacity(0.15))
                .frame(height: 8)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(color)
                            .frame(width: proxy.size.width * fraction * progress)
                            .shadow(color: palette.glow(color, 0.8), radius: 4)
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

/// 切ったタイミングの平均のずれ。真ん中がぴったりで、左が早い・右が遅い。ずれが大きいときはキャリブレーションを勧める
struct TimingGauge: View {
    /// 平均のずれ（秒。負なら早い）
    let meanTimingError: TimeInterval
    /// 目盛りの端に当たるずれ（判定の時間窓）
    let hitWindow: TimeInterval
    let progress: CGFloat

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
            if abs(meanTimingError) > TimingTendency.calibrationHintThreshold {
                Text("ずれが大きいときは、キャリブレーションで合わせられます")
                    .font(.caption)
                    .foregroundStyle(palette.ink.opacity(0.75))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var gauge: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let ratio = hitWindow > 0 ? min(max(meanTimingError / hitWindow, -1), 1) : 0
            ZStack {
                Capsule()
                    .fill(palette.ink.opacity(0.12))
                    .frame(height: 6)
                Rectangle()
                    .fill(palette.ink.opacity(0.5))
                    .frame(width: 2, height: 18)
                Circle()
                    .fill(palette.laser)
                    .frame(width: 14, height: 14)
                    .shadow(color: palette.glow(palette.laser), radius: 6)
                    .offset(x: (width / 2 - 7) * CGFloat(ratio) * progress)
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
