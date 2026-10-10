import SwiftUI

/// 設定で選ぶアプリのテーマ。選んだテーマは `rawValue` で保存するので、case の名前を変えない（変えると既定のテーマに戻る）
///
/// 以前あったサイバーパンク・モノクロ・ポップ・キュート（`cyberpunk` / `monochrome` / `pop` / `cute`）は消した。
/// それらを保存していた人は、`@AppStorage` が知らない値として既定値（`RootView` の斬響）を返すので、斬響に戻る
nonisolated enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case zankyo
    case wa

    /// 選んだテーマの保存先（`@AppStorage`）のキー
    static let storageKey = "appearance.theme"

    var id: Self { self }

    var title: String {
        switch self {
        case .zankyo: "斬響"
        case .wa: "和"
        }
    }

    var summary: String {
        switch self {
        case .zankyo: "生成りの地に墨のノーツと朱の差し色"
        case .wa: "漆黒に朱と藍のノーツ、金の判定線"
        }
    }

    var palette: ThemePalette {
        switch self {
        case .zankyo: .zankyo
        case .wa: .wa
        }
    }
}

extension View {
    /// テーマの配色・アクセントカラー・明るさ・書体を、この View の下すべてに効かせる
    func appTheme(_ theme: AppTheme) -> some View {
        let palette = theme.palette
        return environment(\.palette, palette)
            .tint(palette.accent)
            .fontDesign(palette.fontDesign)
            .preferredColorScheme(palette.colorScheme)
    }
}

nonisolated extension ThemePalette {
    /// 既定のテーマ。生成りの紙に墨で描き、差し色は朱の 1 色に絞る。ノーツは朱（左）・墨（右）・鈍色（上下）・黄土（方向不問）の濃淡で分け、
    /// 赤と青のネオンにはしない。光はにじませず、線で形を立たせる
    static let zankyo = ThemePalette(
        colorScheme: .light,
        accent: Color(red: 0.8, green: 0.24, blue: 0.14),
        fontDesign: .serif,
        spaceTop: Color(red: 0.95, green: 0.93, blue: 0.88),
        spaceBottom: Color(red: 0.88, green: 0.85, blue: 0.78),
        horizon: Color(red: 0.7, green: 0.66, blue: 0.6),
        laser: Color(red: 0.13, green: 0.12, blue: 0.11),
        onLaser: Color(red: 0.97, green: 0.95, blue: 0.9),
        core: Color(red: 0.08, green: 0.07, blue: 0.06),
        ink: Color(red: 0.1, green: 0.09, blue: 0.08),
        panel: Color(red: 0.97, green: 0.95, blue: 0.9),
        warning: Color(red: 0.75, green: 0.2, blue: 0.12),
        left: NeonColor(red: 0.82, green: 0.25, blue: 0.15, shade: 0.55),
        right: NeonColor(red: 0.22, green: 0.2, blue: 0.19, shade: 0.55),
        vertical: NeonColor(red: 0.55, green: 0.53, blue: 0.5, shade: 0.55),
        anyDirection: NeonColor(red: 0.78, green: 0.58, blue: 0.25, shade: 0.55),
        noteOutline: Color(red: 0.1, green: 0.09, blue: 0.08).opacity(0.7),
        glowIntensity: 0
    )

    /// 漆器にならい、黒地を朱で照らし、朱（左）と藍（右）のノーツを置く。判定の線とスコアは金にして、文字は生成りにする
    static let wa = ThemePalette(
        colorScheme: .dark,
        accent: Color(red: 0.9, green: 0.3, blue: 0.2),
        fontDesign: .serif,
        spaceTop: Color(red: 0.12, green: 0.1, blue: 0.09),
        spaceBottom: Color(red: 0.03, green: 0.025, blue: 0.02),
        horizon: Color(red: 0.85, green: 0.28, blue: 0.18),
        laser: Color(red: 0.93, green: 0.78, blue: 0.45),
        onLaser: Color(red: 0.1, green: 0.08, blue: 0.06),
        core: Color(red: 0.98, green: 0.96, blue: 0.9),
        ink: Color(red: 0.97, green: 0.94, blue: 0.87),
        panel: .black,
        warning: Color(red: 0.95, green: 0.3, blue: 0.2),
        left: NeonColor(red: 0.92, green: 0.25, blue: 0.18),
        right: NeonColor(red: 0.22, green: 0.44, blue: 0.88),
        vertical: NeonColor(red: 0.62, green: 0.4, blue: 0.82),
        anyDirection: NeonColor(red: 0.93, green: 0.72, blue: 0.3),
        noteOutline: Color(red: 0.97, green: 0.94, blue: 0.87).opacity(0.5),
        glowIntensity: 0.6
    )
}
