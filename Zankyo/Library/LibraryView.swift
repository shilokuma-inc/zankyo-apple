import SwiftUI

/// 取り込み済みの曲の一覧。曲ごとの容量と合計を出し、スワイプか長押しで消せる。曲を選ぶと難易度を選んで遊べる
///
/// ハートを付けた曲（お気に入り）だけに絞り込める。ハートは右へのスワイプ・長押しのメニュー・曲の詳細で付け外しする
///
/// 付属のサンプル楽曲も同じように並び、消せる。消したサンプル楽曲は「サンプル楽曲を戻す」で入れ直せる
struct LibraryView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all
        case favorites

        var id: Self { self }

        var title: String {
            switch self {
            case .all: "すべて"
            case .favorites: "お気に入り"
            }
        }
    }

    let library: LibraryStore
    let downloads: DownloadModel
    let motion: MotionMonitor
    let highScores: HighScoreStore
    let onSearch: () -> Void
    var samples = SampleSongInstaller()

    @State private var pendingDeletion: LibraryEntry?
    @State private var failedDeletion: LibraryEntry?
    /// 絞り込み。次に開いたときも同じにする
    @AppStorage("library.filter") private var filter: Filter = .all

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
                        if !samples.missingSongs(in: library).isEmpty {
                            Button("サンプル楽曲を戻す") { samples.restore(into: library) }
                                .buttonStyle(.bordered)
                        }
                    }
                } else {
                    list
                }
            }
            .navigationTitle("ライブラリ")
            .navigationDestination(for: LibraryEntry.self) { entry in
                SongDetailView(entry: entry, library: library, motion: motion, highScores: highScores)
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
                if entry.isSample {
                    Text("「\(entry.title)」を端末から消します。ライブラリの「サンプル楽曲を戻す」で元に戻せます。")
                } else {
                    Text("「\(entry.title)」の譜面と音源を端末から消します。もう一度遊ぶには取り込み直してください。")
                }
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

    private var visibleEntries: [LibraryEntry] {
        switch filter {
        case .all: library.entries
        case .favorites: library.favoriteEntries
        }
    }

    private var list: some View {
        List {
            Section {
                Picker("表示する曲", selection: $filter) {
                    ForEach(Filter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if visibleEntries.isEmpty {
                ContentUnavailableView {
                    Label("お気に入りはまだありません", systemImage: "heart")
                } description: {
                    Text("曲を右へスワイプするか、曲の画面のハートを押すと、ここに並びます。")
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(visibleEntries) { entry in
                        row(entry)
                    }
                } footer: {
                    // 合計は一覧の下（親指の近く）に出す
                    Text("\(visibleEntries.count) 曲・合計 \(Self.format(visibleEntries.reduce(0) { $0 + (library.sizes[$1.hash] ?? 0) }))")
                        .monospacedDigit()
                }
            }
            // 消したサンプル楽曲を戻す（すべての曲を出しているときだけ）
            let missing = samples.missingSongs(in: library)
            if filter == .all, !missing.isEmpty {
                Section {
                    Button("サンプル楽曲を戻す（\(missing.count) 曲）", systemImage: "arrow.uturn.backward") {
                        samples.restore(into: library)
                    }
                }
            }
        }
        .animation(.default, value: visibleEntries)
    }

    private func row(_ entry: LibraryEntry) -> some View {
        let isFavorite = library.isFavorite(entry)
        return NavigationLink(value: entry) {
            LibraryRow(entry: entry, size: library.sizes[entry.hash] ?? 0, isFavorite: isFavorite)
        }
        // List の標準の矢印はカードの外に出てしまうので消し、カードの中に出す
        .navigationLinkIndicatorVisibility(.hidden)
        .coverCardListRow()
        .swipeActions(edge: .leading) {
            Button(isFavorite ? "外す" : "お気に入り", systemImage: isFavorite ? "heart.slash" : "heart") {
                library.toggleFavorite(entry)
            }
            .tint(.pink)
            // 新しいアプリが書いた一覧を読んでいるときは保存できないので、付け外しさせない
            .disabled(library.isReadOnly)
        }
        .swipeActions {
            Button("消す", role: .destructive) { pendingDeletion = entry }
        }
        .contextMenu {
            Button(isFavorite ? "お気に入りから外す" : "お気に入りに追加", systemImage: isFavorite ? "heart.slash" : "heart") {
                library.toggleFavorite(entry)
            }
            .disabled(library.isReadOnly)
            Button("消す", systemImage: "trash", role: .destructive) { pendingDeletion = entry }
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
    let isFavorite: Bool

    /// ジャケット画像。サムネイルと背景の両方に使う
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

    /// 1 曲分のカード。`cover` は読み込んだジャケット画像（読み込み中・失敗時は nil）で、サムネイルと背景の両方に使う
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
