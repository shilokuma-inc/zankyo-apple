import SwiftUI

extension Font {
    /// 同梱の欧文フォント（Cinzel。SIL Open Font License 1.1、`Cinzel-OFL.txt`）のファミリー名。
    /// iOS / visionOS は Info.plist の `UIAppFonts`、macOS は `ATSApplicationFontsPath` で読み込む
    static let displayFamily = "Cinzel"

    /// スコア・倍率・カウントダウン・ランクなどの数字と、欧文の見出し（FINISH など）の書体。
    /// 欧文フォントに無い和文は、システムの書体で描かれる。View には `.font` ではなく `displayFont(_:)` で付ける
    static func display(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .custom(displayFamily, fixedSize: size).weight(weight)
    }

    /// 文字の大きさの設定に合わせて大きさが変わる `display(size:weight:)`
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        .custom(displayFamily, size: style.defaultSize, relativeTo: style).weight(weight)
    }
}

private extension Font.TextStyle {
    /// 文字の大きさが標準のときの大きさ（iOS の既定値）
    var defaultSize: CGFloat {
        switch self {
        case .extraLargeTitle: 36
        case .extraLargeTitle2: 28
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
    }
}

extension View {
    /// `Font.display` の書体で描く。テーマの書体（`.fontDesign`）が効いていると、SwiftUI は名前で指定したフォントも
    /// システムの書体に置き換えてしまうので、ここでは外す
    func displayFont(_ font: Font) -> some View {
        self.font(font).fontDesign(nil)
    }
}
