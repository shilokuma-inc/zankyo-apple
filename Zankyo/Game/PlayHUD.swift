import SwiftUI

/// プレイ中のスコアとコンボ。光らせず、文字の色の数字だけで見せる
struct ScoreReadout: View {
    let score: Int
    let combo: Int
    /// コンボを切った空振りの数。増えるたびに、コンボの横に「空振り」と出す
    var emptySwings = 0

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // ヘッダーにはジャケット・頭の動き・倍率も並ぶので、桁が増えたら縮めて 1 行に収める
            Text(score, format: .number)
                .displayFont(.display(.largeTitle, weight: .black).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(palette.ink)
            HStack(spacing: 8) {
                Text("コンボ \(combo)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(palette.laser)
                // コンボが切れた理由を、コンボのすぐ横に出す
                if emptySwings > 0 {
                    EmptySwingEffect()
                        .id(emptySwings)
                }
            }
        }
        // ミスでもコンボは 0 に戻るので、VoiceOver には空振りで切れたことを読み上げて区別できるようにする
        .onChange(of: emptySwings) { previous, current in
            if current > previous {
                AccessibilityNotification.Announcement("空振り。コンボが切れました").post()
            }
        }
    }
}

/// 倍率。Beat Saber にならい、次の倍率までの進み具合をまわりのリングで見せる
struct MultiplierRing: View {
    let multiplier: Int
    /// 次の倍率までの進み具合（0〜1）
    let progress: Double

    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            Circle()
                .stroke(palette.ink.opacity(0.15), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(palette.laser, style: StrokeStyle(lineWidth: 3, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            Text("×\(multiplier)")
                .displayFont(.display(.title3, weight: .bold).monospacedDigit())
                .foregroundStyle(palette.ink)
        }
        .frame(width: 60, height: 60)
        .animation(.easeOut(duration: 0.2), value: progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("倍率 \(multiplier)")
    }
}

/// プレイ中の曲のジャケット画像。ノーツの邪魔にならないよう、スコアの横に小さく出す
struct CoverThumbnail: View {
    let image: CGImage?
    let url: URL?

    @Environment(\.palette) private var palette

    var body: some View {
        CoverArtwork(image: image, url: url)
            .frame(width: 56, height: 56)
            .clipShape(.rect(cornerRadius: 2))
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(palette.ink.opacity(0.25), lineWidth: 1)
            }
    }
}
