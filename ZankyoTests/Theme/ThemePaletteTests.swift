import SwiftUI
import Testing
@testable import Zankyo

struct AppThemeTests {
    @Test
    func storedNamesStayTheSame() {
        // 選んだテーマは rawValue で保存するので、名前が変わると既定のテーマに戻ってしまう
        #expect(AppTheme.allCases.map(\.rawValue) == ["zankyo", "cyberpunk", "monochrome", "pop", "cute", "wa"])
        #expect(AppTheme(rawValue: "unknown") == nil)
    }

    @Test
    func zankyoIsTheDefaultTheme() {
        // 保存していないときは、プレイ画面もアプリ全体も斬響で描く
        #expect(EnvironmentValues().palette == ThemePalette.zankyo)
        #expect(AppTheme.zankyo.palette == ThemePalette.zankyo)
    }

    @Test
    func zankyoUsesInkOnPaperWithoutGlow() {
        // 生成りの地に墨で描き、光はにじませない（Beat Saber の暗い空間のネオンと分ける）
        let palette = AppTheme.zankyo.palette
        #expect(palette.colorScheme == .light)
        #expect(palette.glowIntensity == 0)
        #expect(palette.fontDesign == .serif)
    }

    @Test
    func cyberpunkKeepsThePreviousNeonColors() {
        // サイバーパンクは、テーマを選べるようにする前のプレイ画面と同じ配色にする
        let palette = AppTheme.cyberpunk.palette
        #expect(palette.left == NeonColor(red: 1.0, green: 0.16, blue: 0.32))
        #expect(palette.right == NeonColor(red: 0.05, green: 0.6, blue: 1.0))
        #expect(palette.vertical == NeonColor(red: 0.75, green: 0.3, blue: 1.0))
        #expect(palette.anyDirection == NeonColor(red: 1.0, green: 0.76, blue: 0.1))
        #expect(palette.laser == Color(red: 0.35, green: 0.95, blue: 1.0))
        #expect(palette.horizon == Color(red: 0.6, green: 0.12, blue: 0.9))
        #expect(palette.spaceTop == Color(red: 0.07, green: 0.02, blue: 0.14))
        #expect(palette.spaceBottom == Color(red: 0.01, green: 0.01, blue: 0.03))
        #expect(palette.colorScheme == .dark)
        #expect(palette.glowIntensity == 1)
    }
}

struct ThemePaletteTests {
    @Test(arguments: AppTheme.allCases)
    func noteColorFollowsSwingDirection(theme: AppTheme) {
        let palette = theme.palette
        #expect(palette.noteColor(for: .left) == palette.left)
        #expect(palette.noteColor(for: .right) == palette.right)
        #expect(palette.noteColor(for: .up) == palette.vertical)
        #expect(palette.noteColor(for: .down) == palette.vertical)
        #expect(palette.noteColor(for: nil) == palette.anyDirection)
        // 矢印を読む前に色でも向きの見当がつくよう、向きごとに色を分ける
        #expect(Set([palette.left, palette.right, palette.vertical, palette.anyDirection]).count == 4)
    }

    @Test(arguments: AppTheme.allCases)
    func textOnPlayfieldIsReadable(theme: AppTheme) {
        let palette = theme.palette
        for background in [palette.spaceTop, palette.spaceBottom] {
            // スコアや判定の点数
            #expect(Self.contrast(palette.ink, background) >= 4.5)
            // 判定の線・コンボ・ボタンの縁取り
            #expect(Self.contrast(palette.laser, background) >= 3)
            // ミス・向き違い
            #expect(Self.contrast(palette.warning, background) >= 3)
        }
        // 光で塗りつぶしたボタン（再開など）の文字
        #expect(Self.contrast(palette.onLaser, palette.laser) >= 3)
        // キャリブレーションの「振る」（画面の上に大きく出す）
        #expect(Self.contrast(palette.textColor(for: palette.anyDirection), palette.spaceTop) >= 3)
    }

    @Test(arguments: AppTheme.allCases)
    func arrowsStandOutOnNotes(theme: AppTheme) {
        // ノーツの矢印は白で、一段暗くした面（影の側の色）の上に描く
        let palette = theme.palette
        for neon in [palette.left, palette.right, palette.vertical, palette.anyDirection] {
            #expect(Self.contrast(.white, neon.deep) >= 3)
        }
    }

    @Test(arguments: AppTheme.allCases)
    func accentWorksForButtonsAndText(theme: AppTheme) {
        // `.borderedProminent` の白い文字と、画面の背景の上の文字・アイコンの両方で読める濃さにする
        let palette = theme.palette
        let background: Color = palette.colorScheme == .dark ? .black : .white
        #expect(Self.contrast(.white, palette.accent) >= 3)
        #expect(Self.contrast(palette.accent, background) >= 3)
    }

    @Test
    func glowFollowsIntensity() {
        #expect(AppTheme.cyberpunk.palette.glow(.red, 0.5) == Color.red.opacity(0.5))
        #expect(AppTheme.monochrome.palette.glow(.red, 0.5) == Color.red.opacity(0))
    }

    /// WCAG の相対輝度のコントラスト比（1〜21）
    private static func contrast(_ first: Color, _ second: Color) -> Double {
        let luminances = [first, second].map(luminance).sorted()
        return (luminances[1] + 0.05) / (luminances[0] + 0.05)
    }

    private static func luminance(_ color: Color) -> Double {
        let resolved = color.resolve(in: EnvironmentValues())
        return 0.2126 * Double(resolved.linearRed) + 0.7152 * Double(resolved.linearGreen) + 0.0722 * Double(resolved.linearBlue)
    }
}
