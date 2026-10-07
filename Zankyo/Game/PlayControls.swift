import SwiftUI

/// プレイ画面のボタン。暗い空間に光る線で縁取ったカプセルにする（`prominent` は光で塗りつぶす）
struct NeonButtonStyle: ButtonStyle {
    var prominent = false
    var color: Color = NeonTheme.laser

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded, weight: .heavy))
            .foregroundStyle(prominent ? Color.black : Color.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background {
                Capsule()
                    .fill(prominent ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(0.12)))
            }
            .overlay {
                Capsule()
                    .stroke(color, lineWidth: prominent ? 0 : 1.5)
            }
            .shadow(color: color.opacity(isEnabled ? 0.7 : 0), radius: configuration.isPressed ? 4 : 10)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(.capsule)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 曲が始まる前と、再開する前のカウントダウン。光る数字を大きく出す
struct CountdownOverlay: View {
    let value: Int

    var body: some View {
        Text("\(value)")
            .font(.system(size: 120, weight: .black, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .shadow(color: NeonTheme.laser, radius: 16)
            .shadow(color: NeonTheme.laser.opacity(0.6), radius: 32)
            .id(value)
            .transition(.scale(scale: 1.6).combined(with: .opacity))
            .accessibilityLabel("\(value)")
    }
}

/// 一時停止中のメニュー。暗い板に、再開・最初から・終了を並べる（片手の親指が届くよう画面下に置く）
struct PauseMenu: View {
    /// イヤホンが外れて止まったときの案内（nil なら出さない）
    let notice: String?
    let canResume: Bool
    let onResume: () -> Void
    /// 最初からやり直す（nil ならボタンを出さない）
    let onRestart: (() -> Void)?
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("一時停止中")
                .font(.system(.title3, design: .rounded, weight: .heavy))
                .foregroundStyle(NeonTheme.laser)
                .shadow(color: NeonTheme.laser.opacity(0.8), radius: 8)
            if let notice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            Button(action: onResume) {
                Label("再開", systemImage: "play.fill")
            }
            .buttonStyle(NeonButtonStyle(prominent: true))
            .disabled(!canResume)
            if let onRestart {
                Button(action: onRestart) {
                    Label("最初から", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(NeonButtonStyle())
            }
            Button(action: onQuit) {
                Label("終了", systemImage: "xmark")
            }
            .buttonStyle(NeonButtonStyle(color: NeonTheme.red.color))
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(.black.opacity(0.7))
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(NeonTheme.laser.opacity(0.5), lineWidth: 1)
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
    .preferredColorScheme(.dark)
}
