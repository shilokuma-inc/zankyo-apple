import SwiftUI

/// 曲を最後まで遊んだときに、レーンの上に出す「FINISH」（フルコンボなら「FULL COMBO」）。
/// 文字を上下の細い線で挟み、短いフェードで出すだけにする（光らせず、大きさも変えない）。フルコンボは線の色で分ける
struct FinishOverlay: View {
    let isFullCombo: Bool

    @State private var isShown = false
    @Environment(\.palette) private var palette

    var body: some View {
        let color = isFullCombo ? palette.anyDirection.color : palette.laser
        VStack(spacing: 14) {
            line(color)
            Text(isFullCombo ? "FULL COMBO" : "FINISH")
                .displayFont(.display(size: 56, weight: .black))
                .tracking(6)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(palette.ink)
            line(color)
            Text("タップで結果へ")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(palette.ink.opacity(0.7))
        }
        .opacity(isShown ? 1 : 0)
        .padding(.horizontal, 24)
        .onAppear {
            withAnimation(.easeOut(duration: 0.25)) {
                isShown = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isFullCombo ? "フルコンボ" : "曲が終わりました")
    }

    private func line(_ color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: 280, height: 1.5)
    }
}

#Preview {
    VStack(spacing: 80) {
        FinishOverlay(isFullCombo: false)
        FinishOverlay(isFullCombo: true)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { PlayfieldBackdrop() }
    .appTheme(.zankyo)
}
