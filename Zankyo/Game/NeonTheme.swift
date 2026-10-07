import SwiftUI

/// プレイ画面のネオンの配色。Beat Saber にならい、暗い空間に赤と青の光を置く
///
/// ノーツは色を持たない（Discussion #3 Q4）ので、振る向きで色を決める。左右は Beat Saber の左右のセイバーと同じ赤と青、
/// 上下（うなずき）は紫、方向不問は黄にして、矢印を読む前に色でも向きの見当がつくようにする
enum NeonTheme {
    static let red = NeonColor(red: 1.0, green: 0.16, blue: 0.32)
    static let blue = NeonColor(red: 0.05, green: 0.6, blue: 1.0)
    static let violet = NeonColor(red: 0.75, green: 0.3, blue: 1.0)
    static let amber = NeonColor(red: 1.0, green: 0.76, blue: 0.1)

    /// 判定の線・グリッド・スコアの光
    static let laser = Color(red: 0.35, green: 0.95, blue: 1.0)
    /// 奥の地平の光
    static let horizon = Color(red: 0.6, green: 0.12, blue: 0.9)
    /// 空間の色（上が奥）
    static let spaceTop = Color(red: 0.07, green: 0.02, blue: 0.14)
    static let spaceBottom = Color(red: 0.01, green: 0.01, blue: 0.03)

    static func noteColor(for direction: SwingDirection?) -> NeonColor {
        switch direction {
        case .left: red
        case .right: blue
        case .up, .down: violet
        case nil: amber
        }
    }
}

/// ネオンの 1 色。光る面の明るい色と、影の側の暗い色を組で持つ
nonisolated struct NeonColor: Sendable, Hashable {
    let red: Double
    let green: Double
    let blue: Double

    var color: Color { Color(red: red, green: green, blue: blue) }
    /// 影の側の暗い色
    var deep: Color { Color(red: red * 0.3, green: green * 0.3, blue: blue * 0.3) }
}
