import SwiftUI

/// テーマの配色。プレイ画面（奥の空間・レーン・ノーツ・文字）の色と、アプリ全体の明るさ・アクセントカラー・書体をまとめて持つ
///
/// View は `@Environment(\.palette)` で受け取る。ノーツは色を持たない（Discussion #3 Q4）ので、振る向きで色を決める。
/// 左右は Beat Saber の左右のセイバーにならって別の色にし、レーンの左右の縁にも同じ色を使う
nonisolated struct ThemePalette: Sendable, Hashable {
    /// 画面の明るさ。プレイ画面とアプリ全体の両方に使う
    let colorScheme: ColorScheme
    /// ボタン・選択中のタブなどの色（`.tint`）。白い文字を載せても、画面の背景の上でも読める濃さにする
    let accent: Color
    /// アプリ全体の書体（`.fontDesign`）。プレイ画面・結果画面の数字と欧文の見出しは、テーマによらず同梱の欧文フォント（`Font.display`）で描く
    let fontDesign: Font.Design

    /// 空間の色（上が奥）
    let spaceTop: Color
    let spaceBottom: Color
    /// 奥の地平の光
    let horizon: Color
    /// 判定の線・グリッド・スコアの光
    let laser: Color
    /// `laser` で塗った面の上の文字
    let onLaser: Color
    /// 判定の線と斬撃の芯
    let core: Color
    /// 空間の上に置く文字
    let ink: Color
    /// 一時停止メニューなどの板と、画面を暗く（明るく）覆う色。不透明度は置く場所で決める
    let panel: Color
    /// ミス・向き違い・終了の色
    let warning: Color
    /// 振る向きごとのノーツの色
    let left: NeonColor
    let right: NeonColor
    /// 上下（うなずき）
    let vertical: NeonColor
    /// 方向不問
    let anyDirection: NeonColor
    /// ノーツの縁取り
    let noteOutline: Color
    /// 光（にじみ）の強さ。0 で光らせない（明るい空間で光をにじませると濁るため）
    let glowIntensity: Double

    func noteColor(for direction: SwingDirection?) -> NeonColor {
        switch direction {
        case .left: left
        case .right: right
        case .up, .down: vertical
        case nil: anyDirection
        }
    }

    /// 光（影）に使う色。テーマの光の強さを掛ける
    func glow(_ color: Color, _ opacity: Double = 1) -> Color {
        color.opacity(opacity * glowIntensity)
    }

    /// ノーツの上に描く矢印の色。明るい色のノーツには墨の側、暗い色のノーツには生成りの側の色を載せ、どの色のノーツでも矢印が読めるようにする
    func markColor(for neon: NeonColor) -> Color {
        let (light, dark) = colorScheme == .dark ? (ink, panel) : (panel, ink)
        return neon.luminance > 0.5 ? dark : light
    }

    /// ノーツの色で書く文字の色。明るい空間では光る側の色だと背景に溶けて読めないので、影の側の色にする
    func textColor(for neon: NeonColor) -> Color {
        colorScheme == .dark ? neon.color : neon.deep
    }
}

/// ネオンの 1 色。光る面の明るい色と、影の側の暗い色を組で持つ
nonisolated struct NeonColor: Sendable, Hashable {
    let red: Double
    let green: Double
    let blue: Double
    /// 影の側の暗さ（明るい色に掛ける割合）
    let shade: Double

    init(red: Double, green: Double, blue: Double, shade: Double = 0.3) {
        self.red = red
        self.green = green
        self.blue = blue
        self.shade = shade
    }

    var color: Color { Color(red: red, green: green, blue: blue) }
    /// 影の側の暗い色
    var deep: Color { Color(red: red * shade, green: green * shade, blue: blue * shade) }
    /// 明るさの目安（0〜1。sRGB の値をそのまま重み付けして足す）
    var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }
}

extension EnvironmentValues {
    /// 選んでいるテーマの配色
    @Entry var palette: ThemePalette = .zankyo
}
