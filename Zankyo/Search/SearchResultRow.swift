import SwiftUI

/// 検索結果の 1 曲。マッパー名と beatsaver の譜面ページへのリンクを必ず出す（Discussion #3 Q9）。行の下に取り込みボタンを置く。
/// 背景にジャケット画像をぼかして敷き、曲ごとの色が行全体で分かるようにする
struct SearchResultRow: View {
    let map: BeatsaverMap
    let downloads: DownloadModel

    var body: some View {
        // ジャケット画像は 1 回だけ取りに行き、サムネイルと背景の両方に使う
        AsyncImage(url: map.latestVersion?.coverURL) { phase in
            content(cover: phase.image)
        }
    }

    private func content(cover: Image?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail(cover)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                if !map.metadata.songAuthorName.isEmpty {
                    Text(map.metadata.songAuthorName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Link(destination: map.pageURL) {
                    Label("マッパー: \(map.mapperName)", systemImage: "arrow.up.right.square")
                        .font(.footnote)
                        .lineLimit(1)
                }
                // List の行の中では、スタイルを付けないと行全体がリンクやボタンとして反応する
                .buttonStyle(.borderless)
                .accessibilityHint("beatsaver の譜面ページを開きます")
                if !difficulties.isEmpty {
                    Text(difficulties)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                DownloadControl(
                    state: downloads.state(for: map),
                    isBlocked: downloads.isDownloading || map.latestVersion == nil,
                    onStart: { downloads.start(map) },
                    onCancel: { downloads.cancel() }
                )
                .padding(.top, 4)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { CoverBackdrop(cover: cover) }
        .clipShape(.rect(cornerRadius: 20))
    }

    private func thumbnail(_ cover: Image?) -> some View {
        Group {
            if let cover {
                cover.resizable().scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(.rect(cornerRadius: 8))
        .accessibilityHidden(true)
    }

    /// 曲名。譜面に曲名が無ければマップ名を出す
    private var title: String {
        let song = [map.metadata.songName, map.metadata.songSubName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return song.isEmpty ? map.name : song
    }

    /// 遊ぶ対象の Standard の難易度を易しい順に並べたもの
    private var difficulties: String {
        let order = ["Easy", "Normal", "Hard", "Expert", "ExpertPlus"]
        let names = Set(
            (map.latestVersion?.difficulties ?? [])
                .filter { $0.characteristic == "Standard" }
                .map(\.difficulty)
        )
        return order.filter(names.contains)
            .map { $0 == "ExpertPlus" ? "Expert+" : $0 }
            .joined(separator: " / ")
    }
}

/// 検索結果の行の背景。ジャケット画像を大きくぼかし、文字が読めるように薄くして画面の背景色の上に重ねる
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
