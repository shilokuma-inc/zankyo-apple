import SwiftUI

/// 背景の光の演出（`PlayfieldLights`）のオン・オフ。設定画面で切り替え、プレイ画面と設定画面の見本が読む
enum BackgroundLightSetting {
    /// 保存先（`@AppStorage`）のキー
    static let storageKey = "play.backgroundLights"
    static let defaultValue = true
}

/// 設定画面の「背景の光の演出」の項目
struct BackgroundLightSettingsSection: View {
    @AppStorage(BackgroundLightSetting.storageKey) private var isOn = BackgroundLightSetting.defaultValue

    var body: some View {
        Section {
            Toggle("背景の光の演出", isOn: $isOn)
        } footer: {
            Text("プレイ中の背景を、曲のテンポや譜面の照明に合わせて光らせます。まぶしいときやノーツに集中したいときはオフにできます。端末の「視差効果を減らす」がオンのときは、点滅させずに光らせます。")
        }
    }
}
