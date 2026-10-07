import SwiftUI

/// モーション入力を使えないときの案内。ユーザー向けの代替入力は用意しない（Discussion #3 Q3）ので、遊ぶために要るものだけを伝える
struct MotionRequirementView: View {
    let status: MotionInputStatus

    var body: some View {
        if let guidance = status.guidance {
            ContentUnavailableView {
                Label(guidance.title, systemImage: guidance.systemImage)
            } description: {
                Text(guidance.message)
            } actions: {
                if status == .notAuthorized, let url = Self.settingsURL {
                    Link("設定を開く", destination: url)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    /// アプリの設定画面。iOS 以外はアプリごとの設定画面を開く URL が無いので出さない
    private static var settingsURL: URL? {
        #if os(iOS)
        URL(string: UIApplication.openSettingsURLString)
        #else
        nil
        #endif
    }
}

/// 案内の文言
struct MotionGuidance: Hashable {
    let title: String
    let message: String
    let systemImage: String
}

extension MotionInputStatus {
    /// 使えないときの案内。使えるときは nil
    var guidance: MotionGuidance? {
        switch self {
        case .ready:
            nil
        case .unsupported:
            MotionGuidance(
                title: "対応イヤホンが必要です",
                message: "斬響は、頭の動きに対応したイヤホン（AirPods Pro・AirPods（第 3 世代以降）・AirPods Max など）のモーションセンサーで遊びます。",
                systemImage: "airpods.gen3"
            )
        case .notDetermined:
            MotionGuidance(
                title: "頭の動きを使います",
                message: "プレイを始めると、イヤホンの動きの取得を許可するか尋ねられます。許可すると遊べます。",
                systemImage: "figure.mind.and.body"
            )
        case .notAuthorized:
            MotionGuidance(
                title: "動きの取得が許可されていません",
                message: "設定で、斬響の「モーションとフィットネス」の利用を許可してください。",
                systemImage: "hand.raised"
            )
        case .disconnected:
            MotionGuidance(
                title: "イヤホンをつないでください",
                message: "頭の動きに対応したイヤホンをつなぐと遊べます。つないだまま耳に付けてください。",
                systemImage: "airpods.gen3"
            )
        }
    }
}

#Preview("非対応") {
    MotionRequirementView(status: .unsupported)
}

#Preview("許可なし") {
    MotionRequirementView(status: .notAuthorized)
}

#Preview("未接続") {
    MotionRequirementView(status: .disconnected)
}
