import SwiftUI

/// 結果画面に出す曲の情報
struct PlayedSong: Hashable {
    let title: String
    let artist: String
    /// 難易度の表示名（Expert+ など）
    let difficulty: String
}

/// プレイを終えたときの結果。プレイ画面と同じ空間の上に、曲の情報・ランク・点数・判定の内訳・点の内訳とアドバイスを並べる（光らせない）。
/// 操作（もう一度・閉じる）は片手の親指が届く画面下に横に並べ、よく使う「もう一度」を右に置く
///
/// 順番に見せる演出や跳ねる動きは付けず、開いたときからすべてを出す
struct ResultView: View {
    let result: PlayResult
    let breakdown: ScoreBreakdown
    let previousBest: PlayResult?
    let isNewRecord: Bool
    /// 曲の情報（nil なら出さない）
    var song: PlayedSong?
    var cover: CGImage?
    var coverURL: URL?
    var style: PlayStyle = .directional
    /// 「早い・ぴったり・遅い」の区切りと、タイミングの目盛りの幅
    var rules = ScoringRules()
    /// もう一度遊ぶ（nil ならボタンを出さない）
    var onRetry: (() -> Void)?
    let onClose: () -> Void

    @State private var showsGuide = false

    @Environment(\.palette) private var palette

    /// 結果の上下の端を消すグラデーションの長さ。スクロールしていない位置で端が薄くならないよう、内容の上下にも同じだけ余白を取る
    private static let edgeFadeLength: CGFloat = 24

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                VStack(spacing: 14) {
                    if let song {
                        SongBanner(song: song, cover: cover, coverURL: coverURL, style: style)
                    }
                    RankEmblem(rank: result.rank)
                    scoreBlock
                    badges
                    BreakdownPanel(
                        breakdown: breakdown,
                        style: style,
                        rules: rules,
                        maxCombo: result.maxCombo
                    )
                    PointsPanel(breakdown: breakdown) { showsGuide = true }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
                .padding(.vertical, Self.edgeFadeLength)
            }
            .scrollIndicators(.hidden)
            .verticalEdgeFade(length: Self.edgeFadeLength)
            HStack(spacing: 12) {
                Button(action: onClose) {
                    Label("閉じる", systemImage: "xmark")
                }
                .buttonStyle(PlayButtonStyle())
                if let onRetry {
                    Button(action: onRetry) {
                        Label("もう一度", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(PlayButtonStyle(prominent: true))
                }
            }
            .padding([.horizontal, .bottom])
        }
        .background { PlayfieldBackdrop() }
        .preferredColorScheme(palette.colorScheme)
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

    private var scoreBlock: some View {
        VStack(spacing: 4) {
            Text(result.score, format: .number)
                .displayFont(.display(size: 46, weight: .bold).monospacedDigit())
                .foregroundStyle(palette.ink)
                .accessibilityLabel("スコア \(result.score)")
            Text("達成率 \(result.accuracy.formatted(.percent.precision(.fractionLength(1))))")
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(palette.laser)
            if let bestLine {
                Text(bestLine)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(palette.ink.opacity(0.75))
            }
        }
    }

    /// 前のハイスコアとの差。初めて遊んだ（前のハイスコアが無い）ときは出さない
    private var bestLine: String? {
        guard let previousBest else { return nil }
        let difference = result.score - previousBest.score
        let best = previousBest.score.formatted(.number)
        if isNewRecord {
            return "前のハイスコア \(best)（+\(difference.formatted(.number))）"
        }
        return difference == 0 ? "ハイスコア \(best)（同点）" : "ハイスコア \(best)（あと \((-difference).formatted(.number))）"
    }

    @ViewBuilder private var badges: some View {
        if isNewRecord || result.isFullCombo {
            HStack(spacing: 10) {
                if isNewRecord {
                    ResultBadge(title: "ハイスコア更新", systemImage: "crown.fill", color: palette.anyDirection)
                }
                if result.isFullCombo {
                    ResultBadge(title: "フルコンボ", systemImage: "sparkles", color: palette.right)
                }
            }
        }
    }
}

#Preview {
    ResultView(
        result: PlayResult(
            score: 18_420,
            maxScore: 21_850,
            maxCombo: 120,
            hitCount: 120,
            missCount: 0,
            noteCount: 120,
            playedAt: .now,
            scoringVersion: ScoringRules.version
        ),
        breakdown: ScoreBreakdown(
            judgements: (0..<120).map { index in
                let timingError = Double(index % 5 - 2) * 0.03
                let note = FaceNote(beat: Double(index), time: Double(index), direction: nil)
                return .hit(note, CutScore(peakRate: 3.6, timingError: timingError, rules: ScoringRules()), timingError: timingError)
            },
            rules: ScoringRules()
        ),
        previousBest: PlayResult(
            score: 16_900,
            maxScore: 21_850,
            maxCombo: 80,
            hitCount: 112,
            missCount: 8,
            noteCount: 120,
            playedAt: .now,
            scoringVersion: ScoringRules.version
        ),
        isNewRecord: true,
        song: PlayedSong(title: "歓喜の歌", artist: "ベートーヴェン", difficulty: "Expert+"),
        onRetry: {},
        onClose: {}
    )
    .appTheme(.zankyo)
}
