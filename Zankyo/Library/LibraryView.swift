import SwiftUI

/// 取り込み済みの曲の一覧。曲ごとの容量と合計を出し、スワイプか長押しで消せる
struct LibraryView: View {
    let library: LibraryStore
    let downloads: DownloadModel
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
                    LibraryRow(entry: entry, size: library.sizes[entry.hash] ?? 0)
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

/// 一覧の 1 曲。マッパー名と beatsaver の譜面ページへのリンクを必ず出す（Discussion #3 Q9）
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
                Link(destination: entry.pageURL) {
                    Label("マッパー: \(entry.mapperName)", systemImage: "arrow.up.right.square")
                        .font(.footnote)
                        .lineLimit(1)
                }
                // List の行の中では、スタイルを付けないと行全体がリンクとして反応する
                .buttonStyle(.borderless)
                .accessibilityHint("beatsaver の譜面ページを開きます")
                Text(LibraryView.format(size))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    LibraryView(library: LibraryStore(), downloads: DownloadModel(downloader: MapDownloader()), onSearch: {})
}
