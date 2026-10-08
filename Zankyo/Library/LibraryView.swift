import SwiftUI

/// 取り込み済みの曲の一覧。曲ごとの容量と合計を出し、スワイプか長押しで消せる。曲を選ぶと難易度を選んで遊べる
///
/// 右上の「選択」で曲を複数選び、画面下のボタンでまとめて消せる
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

    /// 開いている曲。一覧の行はボタンにして、選んでいる間は開かずに選び替える（行を作り直さないので、ジャケット画像を読み直さない）
    @State private var path: [LibraryEntry] = []
    /// まとめて消す曲を選んでいる
    @State private var isSelecting = false
    /// 選んでいる曲（`hash`）
    @State private var selection: Set<String> = []
    /// 消すか確かめている曲（スワイプ・長押しのメニューから）
    @State private var pendingDeletion: [LibraryEntry]?
    /// 選んだ曲を消すか確かめている（確認は画面下のボタンから出す）
    @State private var isConfirmingSelectedDeletion = false
    /// 消せなかった曲
    @State private var failedDeletion: [LibraryEntry]?
    /// 絞り込み。次に開いたときも同じにする
    @AppStorage("library.filter") private var filter: Filter = .all

    var body: some View {
        NavigationStack(path: $path) {
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
            .toolbar { selectionToolbar }
            .navigationDestination(for: LibraryEntry.self) { entry in
                SongDetailView(entry: entry, library: library, motion: motion, highScores: highScores)
            }
            .onAppear { library.refreshSizes() }
            .onChange(of: library.entries) {
                // 一覧から無くなった曲は選ばない。曲が無くなったら選ぶのを終える
                selection.formIntersection(library.entries.map(\.hash))
                if library.entries.isEmpty {
                    setSelecting(false)
                }
            }
            .confirmationDialog(
                Text(Self.deletionTitle(pendingDeletion ?? [])),
                isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                titleVisibility: .visible,
                presenting: pendingDeletion
            ) { targets in
                Button(targets.count == 1 ? "消す" : "\(targets.count) 曲を消す", role: .destructive) { delete(targets) }
            } message: { targets in
                Text(Self.deletionMessage(targets))
            }
            .alert(
                "消せませんでした",
                isPresented: Binding(get: { failedDeletion != nil }, set: { if !$0 { failedDeletion = nil } }),
                presenting: failedDeletion
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { failed in
                let what = failed.count == 1 ? "「\(failed[0].title)」" : "\(failed.count) 曲"
                Text("\(what)のファイルを消せませんでした。しばらくしてからもう一度試してください。")
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
                // 選んでいる間は絞り込みを変えない（見えていない曲を選んだまま消さないため）
                .disabled(isSelecting)
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
            // 消したサンプル楽曲を戻す（すべての曲を出しているときだけ。選んでいる間は出さない）
            let missing = samples.missingSongs(in: library)
            if filter == .all, !missing.isEmpty, !isSelecting {
                Section {
                    Button("サンプル楽曲を戻す（\(missing.count) 曲）", systemImage: "arrow.uturn.backward") {
                        samples.restore(into: library)
                    }
                }
            }
        }
        .animation(.default, value: visibleEntries)
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                deleteBar
            }
        }
    }

    /// 選ぶ状態の切り替えと、すべて選ぶ・選択を解除
    @ToolbarContentBuilder private var selectionToolbar: some ToolbarContent {
        if !library.entries.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                Button(isSelecting ? "完了" : "選択") { setSelecting(!isSelecting) }
                    // 新しいアプリが書いた一覧を読んでいるときは消せないので、選ばせない
                    .disabled(!isSelecting && library.isReadOnly)
            }
            if isSelecting {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isAllSelected ? "選択を解除" : "すべて選択") {
                        selection = isAllSelected ? [] : Set(visibleEntries.map(\.hash))
                    }
                    .disabled(visibleEntries.isEmpty)
                }
            }
        }
    }

    /// 選んだ曲をまとめて消すボタン。片手の親指が届く画面下に置き、確認もこのボタンから出す
    private var deleteBar: some View {
        let targets = selectedEntries
        return Button(role: .destructive) {
            isConfirmingSelectedDeletion = true
        } label: {
            Label(targets.isEmpty ? "消す曲を選んでください" : "\(targets.count) 曲を消す", systemImage: "trash")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .controlSize(.large)
        .disabled(targets.isEmpty)
        .confirmationDialog(Text(Self.deletionTitle(targets)), isPresented: $isConfirmingSelectedDeletion, titleVisibility: .visible) {
            Button("\(targets.count) 曲を消す", role: .destructive) { delete(targets) }
        } message: {
            Text(Self.deletionMessage(targets))
        }
        .padding()
        .background(.bar)
    }

    /// 選んでいる曲（一覧の並び）
    private var selectedEntries: [LibraryEntry] {
        visibleEntries.filter { selection.contains($0.hash) }
    }

    private var isAllSelected: Bool {
        !visibleEntries.isEmpty && visibleEntries.allSatisfy { selection.contains($0.hash) }
    }

    private func setSelecting(_ isSelecting: Bool) {
        self.isSelecting = isSelecting
        selection = []
    }

    private func toggleSelection(_ entry: LibraryEntry) {
        if selection.contains(entry.hash) {
            selection.remove(entry.hash)
        } else {
            selection.insert(entry.hash)
        }
    }

    private func row(_ entry: LibraryEntry) -> some View {
        let isFavorite = library.isFavorite(entry)
        let isSelected = selection.contains(entry.hash)
        return Button {
            if isSelecting {
                toggleSelection(entry)
            } else {
                path.append(entry)
            }
        } label: {
            LibraryRow(
                entry: entry,
                size: library.sizes[entry.hash] ?? 0,
                isFavorite: isFavorite,
                isSelected: isSelecting ? isSelected : nil
            )
        }
        // 文字をボタンの色にしない
        .buttonStyle(.plain)
        .coverCardListRow()
        .accessibilityAddTraits(isSelecting && isSelected ? .isSelected : [])
        .accessibilityHint(isSelecting ? (isSelected ? "選ぶのをやめます" : "まとめて消す曲に選びます") : "難易度を選んで遊びます")
        // 選んでいる間は、1 曲ずつの操作（スワイプ・長押しのメニュー）を出さない
        .swipeActions(edge: .leading) {
            if !isSelecting {
                Button(isFavorite ? "外す" : "お気に入り", systemImage: isFavorite ? "heart.slash" : "heart") {
                    library.toggleFavorite(entry)
                }
                .tint(.pink)
                // 新しいアプリが書いた一覧を読んでいるときは保存できないので、付け外しさせない
                .disabled(library.isReadOnly)
            }
        }
        .swipeActions {
            if !isSelecting {
                Button("消す", role: .destructive) { pendingDeletion = [entry] }
            }
        }
        .contextMenu {
            if !isSelecting {
                Button(isFavorite ? "お気に入りから外す" : "お気に入りに追加", systemImage: isFavorite ? "heart.slash" : "heart") {
                    library.toggleFavorite(entry)
                }
                .disabled(library.isReadOnly)
                Button("消す", systemImage: "trash", role: .destructive) { pendingDeletion = [entry] }
            }
        }
    }

    /// 曲を消す。消せなかった曲は知らせ、選んでいる間なら選んだまま残して（もう一度消せるように）、消せたら選ぶのを終える
    private func delete(_ targets: [LibraryEntry]) {
        pendingDeletion = nil
        let failed = library.delete(targets)
        let failedHashes = Set(failed.map(\.hash))
        for entry in targets where !failedHashes.contains(entry.hash) {
            downloads.forget(hash: entry.hash)
        }
        if isSelecting {
            selection = failedHashes
            if failed.isEmpty {
                setSelecting(false)
            }
        }
        if !failed.isEmpty {
            failedDeletion = failed
        }
    }

    /// 消すか確かめるときの見出し
    static func deletionTitle(_ targets: [LibraryEntry]) -> String {
        targets.count == 1 ? "この曲を消しますか？" : "\(targets.count) 曲を消しますか？"
    }

    /// 消すか確かめるときの説明。サンプル楽曲は「サンプル楽曲を戻す」で戻せることも伝える
    static func deletionMessage(_ targets: [LibraryEntry]) -> String {
        if targets.count == 1, let entry = targets.first {
            return entry.isSample
                ? "「\(entry.title)」を端末から消します。ライブラリの「サンプル楽曲を戻す」で元に戻せます。"
                : "「\(entry.title)」の譜面と音源を端末から消します。もう一度遊ぶには取り込み直してください。"
        }
        if targets.allSatisfy(\.isSample) {
            return "選んだ \(targets.count) 曲を端末から消します。ライブラリの「サンプル楽曲を戻す」で元に戻せます。"
        }
        let samples = targets.contains(where: \.isSample) ? "サンプル楽曲は「サンプル楽曲を戻す」で元に戻せます。" : ""
        return "選んだ \(targets.count) 曲の譜面と音源を端末から消します。もう一度遊ぶには取り込み直してください。\(samples)"
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
    /// まとめて消す曲を選んでいる間は、選んだかどうか。ふつうの一覧では nil
    let isSelected: Bool?

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
            trailingMark
        }
        .coverCard(cover)
        .overlay {
            if isSelected == true {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(.tint, lineWidth: 3)
            }
        }
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
