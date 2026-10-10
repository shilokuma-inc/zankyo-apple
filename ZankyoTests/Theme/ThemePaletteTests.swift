import SwiftUI
import Testing
@testable import Zankyo

struct AppThemeTests {
    @Test
    func storedNamesStayTheSame() {
        // 選んだテーマは rawValue で保存するので、名前が変わると既定のテーマに戻ってしまう
        #expect(AppTheme.allCases.map(\.rawValue) == ["zankyo", "wa"])
        #expect(AppTheme(rawValue: "unknown") == nil)
    }

    @Test(arguments: ["cyberpunk", "monochrome", "pop", "cute", "unknown"])
    func removedThemeFallsBackToZankyo(stored: String) throws {
        // 消したテーマを選んでいた人は、既定の斬響に戻る（RootView と同じ既定値で読む）
        let suiteName = "AppThemeTests.\(stored)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(stored, forKey: AppTheme.storageKey)
        let theme = AppStorage(wrappedValue: AppTheme.zankyo, AppTheme.storageKey, store: defaults)
        #expect(theme.wrappedValue == .zankyo)
    }

    @Test
    func waKeepsTheStoredChoice() throws {
        let suiteName = "AppThemeTests.wa"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("wa", forKey: AppTheme.storageKey)
        let theme = AppStorage(wrappedValue: AppTheme.zankyo, AppTheme.storageKey, store: defaults)
        #expect(theme.wrappedValue == .wa)
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
        // ノーツの矢印は、ノーツの色の平らな面の上に、明るさで選んだ墨か生成りの色で描く
        let palette = theme.palette
        for neon in [palette.left, palette.right, palette.vertical, palette.anyDirection] {
            #expect(Self.contrast(palette.markColor(for: neon), neon.color) >= 3)
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
        #expect(AppTheme.wa.palette.glow(.red, 0.5) == Color.red.opacity(0.5 * 0.6))
        #expect(AppTheme.zankyo.palette.glow(.red, 0.5) == Color.red.opacity(0))
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
