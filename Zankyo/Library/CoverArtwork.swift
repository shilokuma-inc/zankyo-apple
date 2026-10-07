import SwiftUI

/// 曲のジャケット画像。譜面 ZIP の画像（オフラインでも出せる）を優先し、無ければ取り込んだときの beatsaver の画像を取りに行く。
/// どちらも無いときは音符を出す。大きさと角の丸めは使う側で決める
struct CoverArtwork: View {
    /// 譜面 ZIP の画像
    let image: CGImage?
    /// beatsaver の画像
    let url: URL?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.quaternary)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
