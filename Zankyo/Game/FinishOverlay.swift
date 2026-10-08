import SwiftUI

/// 曲を最後まで遊んだときに、レーンの上に出す「FINISH」（フルコンボなら「FULL COMBO」）。
/// 上下の光る線が中央から左右へ伸び、文字が光りながら縮んで収まる。「視差効果を減らす」の設定では、大きさを変えずに浮かび上がらせる
struct FinishOverlay: View {
    let isFullCombo: Bool

    @State private var progress: CGFloat = 0
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let color = isFullCombo ? palette.anyDirection.color : palette.laser
        VStack(spacing: 14) {
            line(color)
            Text(isFullCombo ? "FULL COMBO" : "FINISH")
                .font(.system(size: 56, weight: .black, design: .rounded))
                .tracking(6)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(palette.ink)
                .shadow(color: palette.glow(color), radius: 12)
                .shadow(color: palette.glow(color, 0.6), radius: 32)
                .scaleEffect(reduceMotion ? 1 : 1.5 - 0.5 * progress)
            line(color)
            Text("タップで結果へ")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(palette.ink.opacity(0.7))
        }
        .opacity(Double(progress))
        .padding(.horizontal, 24)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.3) : .spring(duration: 0.6, bounce: 0.35)) {
                progress = 1
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isFullCombo ? "フルコンボ" : "曲が終わりました")
    }

    private func line(_ color: Color) -> some View {
        Capsule()
            .fill(color)
            .frame(width: 280 * progress, height: 3)
            .shadow(color: palette.glow(color), radius: 8)
    }
}

#Preview {
    VStack(spacing: 80) {
        FinishOverlay(isFullCombo: false)
        FinishOverlay(isFullCombo: true)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { PlayfieldBackdrop() }
    .appTheme(.cyberpunk)
}
