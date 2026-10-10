import SwiftUI

/// 設定で選ぶアプリのテーマ。選んだテーマは `rawValue` で保存するので、case の名前を変えない（変えると既定のテーマに戻る）
nonisolated enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case zankyo
    case cyberpunk
    case monochrome
    case pop
    case cute
    case wa

    /// 選んだテーマの保存先（`@AppStorage`）のキー
    static let storageKey = "appearance.theme"

    var id: Self { self }

    var title: String {
        switch self {
        case .zankyo: "斬響"
        case .cyberpunk: "サイバーパンク"
        case .monochrome: "モノクロ"
        case .pop: "ポップ"
        case .cute: "キュート"
        case .wa: "和"
        }
    }

    var summary: String {
        switch self {
        case .zankyo: "生成りの地に墨のノーツと朱の差し色"
        case .cyberpunk: "暗い空間に赤と青のネオンが光る"
        case .monochrome: "白い紙に墨の線。色に頼らず矢印で読む"
        case .pop: "レモン色の空間に原色のノーツと黒い縁取り"
        case .cute: "淡いピンクとラベンダーにパステルのノーツ"
        case .wa: "漆黒に朱と藍のノーツ、金の判定線"
        }
    }

    var palette: ThemePalette {
        switch self {
        case .zankyo: .zankyo
        case .cyberpunk: .cyberpunk
        case .monochrome: .monochrome
        case .pop: .pop
        case .cute: .cute
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

    /// Beat Saber にならい、暗い空間に赤と青の光を置く。上下は紫、方向不問は黄にして、矢印を読む前に色でも向きの見当がつくようにする
    static let cyberpunk = ThemePalette(
        colorScheme: .dark,
        accent: Color(red: 1.0, green: 0.2, blue: 0.6),
        fontDesign: .default,
        spaceTop: Color(red: 0.07, green: 0.02, blue: 0.14),
        spaceBottom: Color(red: 0.01, green: 0.01, blue: 0.03),
        horizon: Color(red: 0.6, green: 0.12, blue: 0.9),
        laser: Color(red: 0.35, green: 0.95, blue: 1.0),
        onLaser: .black,
        core: .white,
        ink: .white,
        panel: .black,
        warning: Color(red: 1.0, green: 0.16, blue: 0.32),
        left: NeonColor(red: 1.0, green: 0.16, blue: 0.32),
        right: NeonColor(red: 0.05, green: 0.6, blue: 1.0),
        vertical: NeonColor(red: 0.75, green: 0.3, blue: 1.0),
        anyDirection: NeonColor(red: 1.0, green: 0.76, blue: 0.1),
        noteOutline: .white.opacity(0.5),
        glowIntensity: 1
    )

    /// 白い紙に墨の線。ノーツは濃さだけで分け、白い矢印で向きを読ませる。光はにじませない
    static let monochrome = ThemePalette(
        colorScheme: .light,
        accent: Color(white: 0.1),
        fontDesign: .default,
        spaceTop: Color(white: 0.98),
        spaceBottom: Color(white: 0.86),
        horizon: Color(white: 0.55),
        laser: Color(white: 0.08),
        onLaser: .white,
        core: Color(white: 0.08),
        ink: Color(white: 0.05),
        panel: .white,
        warning: Color(white: 0.35),
        left: NeonColor(red: 0.1, green: 0.1, blue: 0.1),
        right: NeonColor(red: 0.42, green: 0.42, blue: 0.42),
        vertical: NeonColor(red: 0.26, green: 0.26, blue: 0.26),
        anyDirection: NeonColor(red: 0.58, green: 0.58, blue: 0.58),
        noteOutline: .white.opacity(0.6),
        glowIntensity: 0
    )

    /// レモン色の空間に、原色のノーツを黒い縁取りで描く。光はにじませず、縁取りで形を立たせる
    static let pop = ThemePalette(
        colorScheme: .light,
        accent: Color(red: 0.88, green: 0.1, blue: 0.5),
        fontDesign: .rounded,
        spaceTop: Color(red: 1.0, green: 0.97, blue: 0.75),
        spaceBottom: Color(red: 1.0, green: 0.86, blue: 0.42),
        horizon: Color(red: 1.0, green: 0.4, blue: 0.7),
        laser: Color(red: 0.88, green: 0.1, blue: 0.5),
        onLaser: .white,
        core: Color(red: 0.13, green: 0.1, blue: 0.18),
        ink: Color(red: 0.13, green: 0.1, blue: 0.18),
        panel: .white,
        warning: Color(red: 0.85, green: 0.12, blue: 0.18),
        left: NeonColor(red: 1.0, green: 0.3, blue: 0.3, shade: 0.55),
        right: NeonColor(red: 0.15, green: 0.55, blue: 1.0, shade: 0.55),
        vertical: NeonColor(red: 0.2, green: 0.75, blue: 0.35, shade: 0.55),
        anyDirection: NeonColor(red: 0.6, green: 0.3, blue: 0.95, shade: 0.55),
        noteOutline: Color(red: 0.13, green: 0.1, blue: 0.18),
        glowIntensity: 0
    )

    /// 淡いピンクとラベンダーの空間に、パステルのノーツを白く縁取る。光は弱めにふんわりにじませる
    static let cute = ThemePalette(
        colorScheme: .light,
        accent: Color(red: 0.92, green: 0.28, blue: 0.58),
        fontDesign: .rounded,
        spaceTop: Color(red: 1.0, green: 0.93, blue: 0.97),
        spaceBottom: Color(red: 0.94, green: 0.88, blue: 1.0),
        horizon: Color(red: 1.0, green: 0.62, blue: 0.82),
        laser: Color(red: 0.88, green: 0.25, blue: 0.52),
        onLaser: .white,
        core: .white,
        ink: Color(red: 0.4, green: 0.2, blue: 0.36),
        panel: .white,
        warning: Color(red: 0.85, green: 0.22, blue: 0.4),
        left: NeonColor(red: 1.0, green: 0.45, blue: 0.64, shade: 0.72),
        right: NeonColor(red: 0.38, green: 0.64, blue: 1.0, shade: 0.72),
        vertical: NeonColor(red: 0.68, green: 0.5, blue: 1.0, shade: 0.72),
        anyDirection: NeonColor(red: 1.0, green: 0.66, blue: 0.28, shade: 0.72),
        noteOutline: .white,
        glowIntensity: 0.6
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
