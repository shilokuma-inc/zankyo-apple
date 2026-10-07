import SwiftUI

/// 曲のジャケット画像。譜面 ZIP の画像（オフラインでも出せる）を優先し、無ければ取り込んだときの beatsaver の画像を取りに行く。
/// どちらも無いときは音符を出す。大きさと角の丸めは使う側で決める
struct CoverArtwork: View {
    /// 譜面 ZIP の画像
    let image: CGImage?
    /// beatsaver の画像
    let url: URL?

    /// beatsaver から取った画像
    @State private var remoteImage: CGImage?

    var body: some View {
        Group {
            if let shown = image ?? remoteImage {
                Image(decorative: shown, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
            }
        }
        .task(id: url) {
            // 譜面 ZIP の画像があれば取りに行かない。外から来た画像なので、大きさを確かめて縮小してから使う
            guard image == nil, let url else { return }
            remoteImage = await CoverImageLoader().load(url)
        }
        .accessibilityHidden(true)
    }
}
