import CoreText
import SwiftUI
import Testing
@testable import Zankyo

struct DisplayFontTests {
    @Test
    func bundledFontIsRegistered() {
        // Info.plist で読み込めていないと、名前で引いてもシステムの書体に置き換わる
        let font = CTFontCreateWithName(Font.displayFamily as CFString, 17, nil)
        #expect(CTFontCopyFamilyName(font) as String == Font.displayFamily)
    }

    @Test
    func licenseIsBundled() {
        // OFL はフォントと一緒にライセンス文を配ることを求める
        #expect(Bundle.main.url(forResource: "Cinzel-OFL", withExtension: "txt") != nil)
    }
}
