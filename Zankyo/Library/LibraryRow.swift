import SwiftUI

/// 一覧の 1 曲。マッパー名を必ず出す（Discussion #3 Q9。譜面ページへのリンクは曲の詳細画面に出す）。
/// `List` の標準の行に、ジャケットのサムネイルと曲の情報を並べる
struct LibraryRow: View {
    let entry: LibraryEntry
    let size: Int64
    let isFavorite: Bool
    /// まとめて消す曲を選んでいる間は、選んだかどうか。ふつうの一覧では nil
    let isSelected: Bool?
    /// この曲を試聴している（サムネイルの印を停止にする）
    let isPreviewing: Bool
    /// 試聴のために音源を読んでいる
    let isLoadingPreview: Bool
    /// ジャケットを押したとき（試聴を始める・止める）
    let onTogglePreview: () -> Void

    /// ジャケット画像（サムネイル）
    @State private var cover: CGImage?

    var body: some View {
        content(cover: cover.map { Image(decorative: $0, scale: 1) })
            .task(id: entry.hash) {
                // 取り込んだ譜面 ZIP の画像を先に使う（オフラインの電車の中でも出せる）。無ければ取り込んだときの beatsaver の画像を取りに行く
                if let local = await LocalMapStore().loadListCover(hash: entry.hash) {
                    cover = local
                } else if let url = entry.coverURL {
                    cover = await CoverImageLoader().load(url)
                }
            }
    }

    /// 1 曲分の行。`cover` は読み込んだジャケット画像（読み込み中・失敗時は nil）
    private func content(cover: Image?) -> some View {
        HStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                thumbnail(cover)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(entry.title)
                            .font(.headline)
                            .lineLimit(2)
                        if isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.subheadline)
                                .foregroundStyle(.pink)
                                .accessibilityLabel("お気に入り")
                        }
                    }
                    if !entry.songAuthorName.isEmpty {
                        Text(entry.songAuthorName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    // 行全体が曲の詳細へのリンクなので、譜面ページへのリンクは詳細画面に置く（行の中に置くと、行をタップしたつもりで開いてしまう）
                    Text("マッパー: \(entry.mapperName)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(LibraryView.format(size))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            trailingMark
        }
        // 行の余白も押せるようにする（行全体が曲の詳細を開くボタン）
        .contentShape(.rect)
    }

    /// 右端の印。ふつうは開けることを示す矢印、選んでいる間は選んだかどうかの丸
    @ViewBuilder private var trailingMark: some View {
        if let isSelected {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .accessibilityHidden(true)
        } else {
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    /// 左に出すジャケット画像のサムネイル。ふつうの一覧では押すと試聴を始め・止める（行のほかの部分は曲の詳細を開く）。
    /// まとめて消す曲を選んでいる間は、行のどこを押しても選ぶ・外すにするので、試聴のボタンにしない
    @ViewBuilder private func thumbnail(_ cover: Image?) -> some View {
        if isSelected == nil {
            Button(action: onTogglePreview) {
                artwork(cover)
                    .overlay { previewBadge }
            }
            // 行のタップ（曲の詳細を開く）と分ける
            .buttonStyle(.borderless)
            .accessibilityLabel(isPreviewing || isLoadingPreview ? "試聴を止める" : "試聴する")
        } else {
            artwork(cover)
                .accessibilityHidden(true)
        }
    }

    /// ジャケット画像。画像が無いあいだは音符を出す
    private func artwork(_ cover: Image?) -> some View {
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
        .frame(width: 56, height: 56)
        .clipShape(.rect(cornerRadius: 8))
    }

    /// サムネイルの上の試聴の印。読んでいる間は回る
    private var previewBadge: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.5))
            if isLoadingPreview {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            } else {
                Image(systemName: isPreviewing ? "stop.fill" : "play.fill")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}
