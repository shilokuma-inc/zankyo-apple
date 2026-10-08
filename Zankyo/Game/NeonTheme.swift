import SwiftUI

/// テーマを選べるようになる前のプレイ画面の配色（いまのサイバーパンクの配色）。
/// 選んだテーマには追従しないので、新しいコードでは `@Environment(\.palette)` の `ThemePalette` を使う
///
/// 並行して開発中のブランチがまだ参照しているため、移行し終えるまで残す
@available(*, deprecated, message: "選んだテーマに追従しません。@Environment(\\.palette) の ThemePalette を使ってください")
enum NeonTheme {
    static var red: NeonColor { ThemePalette.cyberpunk.left }
    static var blue: NeonColor { ThemePalette.cyberpunk.right }
    static var violet: NeonColor { ThemePalette.cyberpunk.vertical }
    static var amber: NeonColor { ThemePalette.cyberpunk.anyDirection }

    static var laser: Color { ThemePalette.cyberpunk.laser }
    static var horizon: Color { ThemePalette.cyberpunk.horizon }
    static var spaceTop: Color { ThemePalette.cyberpunk.spaceTop }
    static var spaceBottom: Color { ThemePalette.cyberpunk.spaceBottom }

    static func noteColor(for direction: SwingDirection?) -> NeonColor {
        ThemePalette.cyberpunk.noteColor(for: direction)
    }
}
