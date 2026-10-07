import SwiftUI

/// 取り込んだ曲の詳細。難易度を選ぶと、ノーツと音源を用意してプレイ画面を出す。遊ぶ前に曲を試聴できる
struct SongDetailView: View {
    let motion: MotionMonitor
    let highScores: HighScoreStore

    @State private var model: SongDetailModel
    /// 難易度を選んでからの準備。画面を離れたら取り消す
    @State private var preparation: Task<Void, Never>?
    /// 試聴の準備（音源のデコード）。画面を離れたら取り消し、鳴らしていれば止める
    @State private var previewTask: Task<Void, Never>?

    init(entry: LibraryEntry, motion: MotionMonitor, highScores: HighScoreStore) {
        self.motion = motion
        self.highScores = highScores
        _model = State(initialValue: SongDetailModel(entry: entry))
    }

    var body: some View {
        content
            .navigationTitle(model.entry.title)
            .task { await model.load() }
            .onDisappear {
                preparation?.cancel()
                preparation = nil
                previewTask?.cancel()
                previewTask = nil
                model.stopPreview()
            }
            .alert(
                "遊べません",
                isPresented: Binding(get: { model.playError != nil }, set: { if !$0 { model.playError = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.playError ?? "")
            }
            .playCover(item: $model.play) { setup in
                PlayScreen(setup: setup, motion: motion, highScores: highScores) {
                    model.play = nil
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("譜面を読み込んでいます")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView("譜面を読み込めません", systemImage: "exclamationmark.triangle", description: Text(message))
        case .ready(let info):
            List {
                Section {
                    SongHeader(entry: model.entry, info: info, cover: model.cover) {
                        PreviewButton(isPlaying: model.isPreviewing, isLoading: model.isLoadingPreview) {
                            previewTask?.cancel()
                            previewTask = Task { await model.togglePreview() }
                        }
                        .disabled(model.isLoadingPreview || model.preparing != nil)
                    }
                }
                ForEach(model.difficultyGroups, id: \.characteristic) { group in
                    Section(group.characteristic.displayName) {
                        ForEach(group.difficulties, id: \.self) { difficulty in
                            difficultyRow(difficulty)
                        }
                    }
                }
            }
        }
    }

    private func difficultyRow(_ difficulty: DifficultyInfo) -> some View {
        let key = ScoreKey(mapHash: model.entry.hash, characteristic: difficulty.characteristic, difficulty: difficulty.difficulty)
        return Button {
            preparation?.cancel()
            preparation = Task { await model.prepare(difficulty) }
        } label: {
            HStack {
                Text(difficulty.difficulty.displayName)
                    .font(.headline)
                Spacer()
                if model.preparing == difficulty {
                    ProgressView()
                } else if let best = highScores.best(for: key) {
                    Text("\(best.rank.rawValue)  \(best.score)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .disabled(model.preparing != nil)
        .accessibilityHint("この難易度で遊びます")
    }
}

/// ジャケット画像・アーティスト・マッパー（beatsaver の譜面ページへのリンク。Discussion #3 Q9）。曲名は画面の見出しに出す。
/// `accessory`（試聴のボタン）は文字の下に置く
private struct SongHeader<Accessory: View>: View {
    let entry: LibraryEntry
    let info: SongInfo
    let cover: CGImage?
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            CoverArtwork(image: cover, url: entry.coverURL)
                .frame(width: 112, height: 112)
                .clipShape(.rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 6) {
                if !entry.songAuthorName.isEmpty {
                    Text(entry.songAuthorName)
                        .font(.headline)
                }
                Link(destination: entry.pageURL) {
                    Label("マッパー: \(entry.mapperName)", systemImage: "arrow.up.right.square")
                        .font(.footnote)
                }
                .buttonStyle(.borderless)
                .accessibilityHint("beatsaver の譜面ページを開きます")
                Text("BPM \(info.bpm, format: .number.precision(.fractionLength(0...1)))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                accessory
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
}

/// 試聴のボタン。押すと曲の聞きどころ（Info.dat の試聴区間）をくり返し鳴らし、もう一度押すと止める
private struct PreviewButton: View {
    let isPlaying: Bool
    /// 音源をデコードしている
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                }
                Text(isPlaying ? "試聴を止める" : "試聴する")
            }
            .font(.subheadline.weight(.semibold))
        }
        // List の行の中なので、行全体ではなくボタンの形の中だけで押せるようにする
        .buttonStyle(.bordered)
        .accessibilityHint(isPlaying ? "" : "曲の聞きどころをくり返し再生します")
    }
}

/// 1 回のプレイ。もう一度遊ぶときは、同じノーツと音源で新しいセッションを作る
struct PlayScreen: View {
    let setup: PlaySetup
    let motion: MotionMonitor
    let highScores: HighScoreStore
    let onExit: () -> Void

    @State private var session: GameSession?

    var body: some View {
        Group {
            if let session {
                PlayView(
                    session: session,
                    motion: motion,
                    cover: setup.cover,
                    coverURL: setup.entry.coverURL,
                    onRetry: { self.session = makeSession() },
                    onExit: onExit
                )
                .id(ObjectIdentifier(session))
            } else {
                Color.clear
            }
        }
        .onAppear {
            if session == nil {
                session = makeSession()
            }
        }
        .onDisappear {
            // 閉じたら音と入力を止める（終えていなければ、記録せずに止める）
            if session?.phase != .finished {
                session?.clock.stop()
                session?.input.stop()
            }
        }
    }

    private func makeSession() -> GameSession {
        GameSession(
            notes: setup.notes,
            clock: AudioSongClock(song: setup.song),
            input: motion,
            offset: CalibrationStore().offset,
            scoreKey: setup.scoreKey,
            highScores: highScores
        )
    }
}

private extension BeatmapCharacteristic {
    var displayName: String {
        switch self {
        case .standard: "Standard"
        case .oneSaber: "One Saber"
        case .noArrows: "No Arrows"
        case .degree90: "90 Degree"
        case .degree360: "360 Degree"
        }
    }
}

private extension View {
    /// プレイ画面を全面に出す。macOS には全面のモーダルが無いのでシートにする
    func playCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(macOS)
        sheet(item: item) { value in
            content(value)
                .frame(minWidth: 420, minHeight: 640)
                .interactiveDismissDisabled()
        }
        #else
        fullScreenCover(item: item, content: content)
        #endif
    }
}
