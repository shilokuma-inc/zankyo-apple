import SwiftUI

/// 取り込み済みの曲の一覧。曲ごとの容量と合計を出し、スワイプか長押しで消せる。曲を選ぶと難易度を選んで遊べる
struct LibraryView: View {
    let library: LibraryStore
    let downloads: DownloadModel
    let motion: MotionMonitor
    let highScores: HighScoreStore
    let onSearch: () -> Void

    @State private var pendingDeletion: LibraryEntry?
    @State private var failedDeletion: LibraryEntry?

    var body: some View {
        NavigationStack {
            Group {
                if library.entries.isEmpty {
                    ContentUnavailableView {
                        Label("取り込んだ曲はまだありません", systemImage: "music.note.list")
                    } description: {
                        Text("beatsaver で曲を検索して取り込むと、ここに並びます。")
                    } actions: {
                        Button("曲を検索する", action: onSearch)
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    list
                }
            }
            .navigationTitle("ライブラリ")
            .navigationDestination(for: LibraryEntry.self) { entry in
                SongDetailView(entry: entry, motion: motion, highScores: highScores)
            }
            .onAppear { library.refreshSizes() }
            .confirmationDialog(
                "この曲を消しますか？",
                isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                titleVisibility: .visible,
                presenting: pendingDeletion
            ) { entry in
                Button("消す", role: .destructive) { delete(entry) }
            } message: { entry in
                Text("「\(entry.title)」の譜面と音源を端末から消します。もう一度遊ぶには取り込み直してください。")
            }
            .alert(
                "消せませんでした",
                isPresented: Binding(get: { failedDeletion != nil }, set: { if !$0 { failedDeletion = nil } }),
                presenting: failedDeletion
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { entry in
                Text("「\(entry.title)」のファイルを消せませんでした。しばらくしてからもう一度試してください。")
            }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(library.entries) { entry in
                    NavigationLink(value: entry) {
                        LibraryRow(entry: entry, size: library.sizes[entry.hash] ?? 0)
                    }
                    // List の標準の矢印はカードの外に出てしまうので消し、カードの中に出す
                    .navigationLinkIndicatorVisibility(.hidden)
                    .coverCardListRow()
                    .swipeActions {
                        Button("消す", role: .destructive) { pendingDeletion = entry }
                    }
                    .contextMenu {
                        Button("消す", systemImage: "trash", role: .destructive) { pendingDeletion = entry }
                    }
                }
            } footer: {
                // 合計は一覧の下（親指の近く）に出す
                Text("\(library.entries.count) 曲・合計 \(Self.format(library.totalSize))")
                    .monospacedDigit()
            }
        }
    }

    private func delete(_ entry: LibraryEntry) {
        pendingDeletion = nil
        if library.delete(entry) {
            downloads.forget(hash: entry.hash)
        } else {
            failedDeletion = entry
        }
    }

    static func format(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }
}

/// 一覧の 1 曲。マッパー名を必ず出す（Discussion #3 Q9。譜面ページへのリンクは曲の詳細画面に出す）。
/// 背景にジャケット画像をぼかして敷き、曲ごとの色が行全体で分かるようにする
private struct LibraryRow: View {
    let entry: LibraryEntry
    let size: Int64

    var body: some View {
        // ジャケット画像は 1 回だけ取りに行き、サムネイルと背景の両方に使う
        AsyncImage(url: entry.coverURL) { phase in
            content(cover: phase.image)
        }
    }

    /// 1 曲分のカード。`cover` は読み込んだジャケット画像（読み込み中・失敗時は nil）で、サムネイルと背景の両方に使う
    private func content(cover: Image?) -> some View {
        HStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                thumbnail(cover)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.headline)
                        .lineLimit(2)
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
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .coverCard(cover)
    }

    /// 左に出すジャケット画像のサムネイル。画像が無いあいだは音符を出す
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
        .frame(width: 56, height: 56)
        .clipShape(.rect(cornerRadius: 8))
        .accessibilityHidden(true)
    }
}

#Preview {
    LibraryView(
        library: LibraryStore(),
        downloads: DownloadModel(downloader: MapDownloader()),
        motion: MotionMonitor(base: RecordedMotionInput(samples: [])),
        highScores: HighScoreStore(),
        onSearch: {}
    )
}
