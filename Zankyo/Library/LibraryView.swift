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
    /// 曲の試聴。各行のジャケットを押すと試聴し、試聴している行の縁を光らせる
    let preview: SongPreviewCenter
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
                        .alert(
                            "試聴できません",
                            isPresented: Binding(get: { preview.error != nil }, set: { if !$0 { preview.error = nil } })
                        ) {
                            Button("OK", role: .cancel) {}
                        } message: {
                            Text(preview.error ?? "")
                        }
                }
            }
            .navigationTitle("ライブラリ")
            .navigationDestination(for: LibraryEntry.self) { entry in
                SongDetailView(entry: entry, library: library, preview: preview, motion: motion, highScores: highScores)
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
            LibraryRow(
                entry: entry,
                size: library.sizes[entry.hash] ?? 0,
                isFavorite: isFavorite,
                isPreviewing: preview.isPlaying(entry.hash),
                isLoadingPreview: preview.isLoading(entry.hash)
            ) {
                preview.toggle(entry)
            }
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
        // 消す曲の試聴は、ファイルを消す前に止める
        if preview.isPlaying(entry.hash) || preview.isLoading(entry.hash) {
            preview.stop()
        }
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
    /// この曲を試聴している（カードの縁を光らせる）
    let isPreviewing: Bool
    /// 試聴のために音源を読んでいる
    let isLoadingPreview: Bool
    /// ジャケットを押したとき（試聴を始める・止める）
    let onTogglePreview: () -> Void

    @Environment(\.palette) private var palette

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
        .overlay {
            if isPreviewing {
                PreviewGlow(color: palette.accent)
            }
        }
    }

    /// 左に出すジャケット画像のサムネイル。押すと試聴を始め・止める（行のほかの部分は曲の詳細へのリンク）。画像が無いあいだは音符を出す
    private func thumbnail(_ cover: Image?) -> some View {
        Button(action: onTogglePreview) {
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
            .overlay { previewBadge }
        }
        // 行のタップ（曲の詳細を開く）と分ける
        .buttonStyle(.borderless)
        .accessibilityLabel(isPreviewing || isLoadingPreview ? "試聴を止める" : "試聴する")
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

/// 試聴している曲のカードの縁の光。ゆっくり明滅させる（視差効果を減らす設定では明滅させない）
private struct PreviewGlow: View {
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            border(intensity: 1)
        } else {
            PhaseAnimator([0.45, 1.0]) { intensity in
                border(intensity: intensity)
            } animation: { _ in
                .easeInOut(duration: 0.9)
            }
        }
    }

    private func border(intensity: Double) -> some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(color, lineWidth: 2.5)
            // 行の上下の余白（6pt）より広げると、隣の行との境で光が切れて角ばって見えるので、その中に収める
            .shadow(color: color.opacity(0.9 * intensity), radius: 2 + 2 * intensity)
            .shadow(color: color.opacity(0.7 * intensity), radius: 5 * intensity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#Preview {
    LibraryView(
        library: LibraryStore(),
        downloads: DownloadModel(downloader: MapDownloader()),
        preview: SongPreviewCenter(),
        motion: MotionMonitor(base: RecordedMotionInput(samples: [])),
        highScores: HighScoreStore(),
        onSearch: {}
    )
}
