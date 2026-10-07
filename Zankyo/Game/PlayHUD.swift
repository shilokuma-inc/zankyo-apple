import SwiftUI

/// プレイ中のスコアとコンボ。暗い背景の上で読めるよう、白い数字を水色に光らせる
struct ScoreReadout: View {
    let score: Int
    let combo: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(score, format: .number)
                .font(.system(.largeTitle, design: .rounded, weight: .heavy).monospacedDigit())
                .foregroundStyle(.white)
                .shadow(color: NeonTheme.laser.opacity(0.8), radius: 8)
            Text("コンボ \(combo)")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(NeonTheme.laser)
        }
    }
}

/// 倍率。Beat Saber にならい、次の倍率までの進み具合をまわりのリングで見せる
struct MultiplierRing: View {
    let multiplier: Int
    /// 次の倍率までの進み具合（0〜1）
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.15), lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(NeonTheme.laser, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: NeonTheme.laser, radius: 6)
            Text("×\(multiplier)")
                .font(.system(.title3, design: .rounded, weight: .heavy).monospacedDigit())
                .foregroundStyle(.white)
        }
        .frame(width: 60, height: 60)
        .animation(.easeOut(duration: 0.2), value: progress)
    }
}
