import SwiftUI

/// 取り込み済みの曲の一覧。曲ごとの容量と合計を出し、スワイプか長押しで消せる。曲を選ぶと難易度を選んで遊べる
struct LibraryView: View {
    let library: LibraryStore
    let downloads: DownloadModel
    let input: any MotionInput
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
                SongDetailView(entry: entry, input: input, highScores: highScores)
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

/// 一覧の 1 曲。マッパー名を必ず出す（Discussion #3 Q9。譜面ページへのリンクは曲の詳細画面に出す）
private struct LibraryRow: View {
    let entry: LibraryEntry
    let size: Int64

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: entry.coverURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
            }
            .frame(width: 56, height: 56)
            .clipShape(.rect(cornerRadius: 8))
            .accessibilityHidden(true)
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
        .padding(.vertical, 4)
    }
}

#Preview {
    LibraryView(
        library: LibraryStore(),
        downloads: DownloadModel(downloader: MapDownloader()),
        input: RecordedMotionInput(samples: []),
        highScores: HighScoreStore(),
        onSearch: {}
    )
}
