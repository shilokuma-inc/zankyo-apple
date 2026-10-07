import SwiftUI

extension View {
    /// ジャケット画像をぼかして敷いた角丸のカードにする。曲ごとの色がカード全体で分かるようにする（検索結果とライブラリの一覧で共通）。
    /// `cover` は読み込んだジャケット画像で、読み込み中・失敗時は nil（画面の背景色だけのカードになる）
    func coverCard(_ cover: Image?) -> some View {
        padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { CoverBackdrop(cover: cover) }
            .clipShape(.rect(cornerRadius: 20))
    }

    /// `coverCard` を並べる List の行の設定。カードの色を見せるため、行の背景と区切り線を消し、カードの間を空ける
    func coverCardListRow() -> some View {
        listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

/// カードの背景。ジャケット画像を大きくぼかし、文字が読めるように薄くして画面の背景色の上に重ねる
private struct CoverBackdrop: View {
    let cover: Image?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.background)
            if let cover {
                Color.clear
                    .overlay {
                        cover.resizable().scaledToFill()
                    }
                    .clipped()
                    // ぼかすと色が混ざってくすむので、彩度を上げて曲の色を残す
                    .saturation(1.6)
                    // 端まで色を残すため、ぼかしで縁が透けないようにする
                    .blur(radius: 24, opaque: true)
                    .opacity(0.5)
            }
        }
        .accessibilityHidden(true)
    }
}
