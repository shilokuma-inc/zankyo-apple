import SwiftUI

/// プレイ画面のボタン。角の小さい板に細い線で縁取る（`prominent` は色で塗りつぶす）。光らせず、押したときは薄くするだけにする
struct PlayButtonStyle: ButtonStyle {
    var prominent = false
    /// 縁取りと塗りの色。nil ならテーマのレーザーの色
    var color: Color?

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        let color = color ?? palette.laser
        return configuration.label
            .font(.headline)
            .foregroundStyle(prominent ? palette.onLaser : palette.ink)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background {
                RoundedRectangle(cornerRadius: 4)
                    .fill(prominent ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(0.06)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(color, lineWidth: prominent ? 0 : 1)
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
            .contentShape(.rect(cornerRadius: 4))
    }
}

/// 曲が始まる前と、再開する前のカウントダウン。数字を大きく出し、切り替わりは薄く入れ替えるだけにする
struct CountdownOverlay: View {
    let value: Int

    @Environment(\.palette) private var palette

    var body: some View {
        Text("\(value)")
            .displayFont(.display(size: 120, weight: .black).monospacedDigit())
            .foregroundStyle(palette.ink)
            .id(value)
            .transition(.opacity)
            .accessibilityLabel("\(value)")
    }
}

/// 一時停止中のメニュー。細い線で縁取った板の上に、再開・最初から・終了を並べる（片手の親指が届くよう画面下に置く）
struct PauseMenu: View {
    /// イヤホンが外れて止まったときの案内（nil なら出さない）
    let notice: String?
    let canResume: Bool
    let onResume: () -> Void
    /// 最初からやり直す（nil ならボタンを出さない）
    let onRestart: (() -> Void)?
    let onQuit: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 12) {
            Text("一時停止中")
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.ink)
            if let notice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(palette.ink.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            Button(action: onResume) {
                Label("再開", systemImage: "play.fill")
            }
            .buttonStyle(PlayButtonStyle(prominent: true))
            .disabled(!canResume)
            if let onRestart {
                Button(action: onRestart) {
                    Label("最初から", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(PlayButtonStyle())
            }
            Button(action: onQuit) {
                Label("終了", systemImage: "xmark")
            }
            .buttonStyle(PlayButtonStyle(color: palette.warning))
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(palette.panel.opacity(0.9))
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(palette.ink.opacity(0.2), lineWidth: 1)
                }
        }
    }
}

#Preview {
    VStack(spacing: 32) {
        CountdownOverlay(value: 3)
        PauseMenu(notice: "イヤホンが外れたので止めました。つなぎ直すと再開できます。", canResume: false, onResume: {}, onRestart: {}, onQuit: {})
    }
    .padding()
    .background { PlayfieldBackdrop() }
    .appTheme(.zankyo)
}
