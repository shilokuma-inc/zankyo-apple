import CoreGraphics
import Foundation
import Observation

/// 遊ぶ準備のできた 1 回分（ノーツとデコードした音源）
struct PlaySetup: Identifiable {
    let id = UUID()
    let entry: LibraryEntry
    let difficulty: DifficultyInfo
    let notes: [FaceNote]
    let song: DecodedSong
    /// 譜面 ZIP のジャケット画像。無ければ nil
    let cover: CGImage?

    var scoreKey: ScoreKey {
        ScoreKey(mapHash: entry.hash, characteristic: difficulty.characteristic, difficulty: difficulty.difficulty)
    }
}

/// 曲の詳細（難易度の選択）の状態。曲情報を読み、選んだ難易度のノーツと音源を用意する。遊ぶ前に曲を試聴できる
///
/// 音源のデコードは重いので、この画面にいる間は 1 度だけ行い、難易度を変えても試聴でも使い回す
@Observable
final class SongDetailModel {
    enum State {
        case loading
        case ready(SongInfo)
        case failed(String)
    }

    let entry: LibraryEntry
    private(set) var state: State = .loading
    /// 譜面 ZIP のジャケット画像。無い・読めないときは nil
    private(set) var cover: CGImage?
    /// 準備中の難易度
    private(set) var preparing: DifficultyInfo?
    /// 準備できたら遊ぶ画面を出す
    var play: PlaySetup?
    /// 準備できなかった理由
    var playError: String?
    /// 試聴のために音源をデコードしている
    private(set) var isLoadingPreview = false
    /// 試聴している
    private(set) var isPreviewing = false

    @ObservationIgnored private let maps: LocalMapStore
    @ObservationIgnored private let previewer: any SongPreviewing
    @ObservationIgnored private var song: DecodedSong?
    /// デコード中の音源。試聴と遊ぶ準備が重なっても、デコードは 1 度にする（長い曲は数百 MB になるため）
    @ObservationIgnored private var decoding: Task<Void, Never>?
    /// 直近のデコードに失敗した理由
    @ObservationIgnored private var decodeError: MapLoadError?
    /// 試聴を求めた回数。止めたときにも増やし、デコードを待っている間に止められた（遊ぶ準備を始めたなど）試聴を鳴らさない
    @ObservationIgnored private var previewRequest = 0

    init(entry: LibraryEntry, maps: LocalMapStore = LocalMapStore(), previewer: any SongPreviewing = SongPreviewPlayer()) {
        self.entry = entry
        self.maps = maps
        self.previewer = previewer
    }

    var info: SongInfo? {
        if case .ready(let info) = state { return info }
        return nil
    }

    /// 難易度を characteristic ごとにまとめる（Standard を先に）
    var difficultyGroups: [(characteristic: BeatmapCharacteristic, difficulties: [DifficultyInfo])] {
        guard let info else { return [] }
        return BeatmapCharacteristic.allCases.compactMap { characteristic in
            let difficulties = info.difficulties.filter { $0.characteristic == characteristic }
            return difficulties.isEmpty ? nil : (characteristic, difficulties)
        }
    }

    func load() async {
        guard case .loading = state else { return }
        do {
            let info = try await maps.loadInfo(hash: entry.hash)
            // 難易度を選べるようにする前に読む（読み終える前に遊び始めると、そのプレイに画像が渡らないため）。縮小した画像なのですぐ終わる
            cover = await maps.loadCover(hash: entry.hash, info: info)
            state = .ready(info)
        } catch {
            state = .failed(error.message)
        }
    }

    /// 選んだ難易度のノーツと音源を用意し、できたら `play` に入れる。取り消されたら（画面を離れたら）何も出さない
    func prepare(_ difficulty: DifficultyInfo) async {
        guard let info, preparing == nil else { return }
        stopPreview()
        preparing = difficulty
        defer { preparing = nil }
        do {
            let notes = try await maps.loadNotes(hash: entry.hash, info: info, difficulty: difficulty)
            let song = try await loadedSong(info: info)
            guard !Task.isCancelled else { return }
            play = PlaySetup(entry: entry, difficulty: difficulty, notes: notes, song: song, cover: cover)
        } catch {
            guard !Task.isCancelled else { return }
            playError = error.message
        }
    }

    /// 試聴を始める。試聴中なら止める。音源をまだデコードしていなければ、先にデコードする
    func togglePreview() async {
        if isPreviewing {
            stopPreview()
            return
        }
        guard let info, !isLoadingPreview, preparing == nil else { return }
        previewRequest += 1
        let request = previewRequest
        isLoadingPreview = true
        defer { isLoadingPreview = false }
        let song: DecodedSong
        do {
            song = try await loadedSong(info: info)
        } catch {
            // 止められた試聴の失敗は出さない（遊ぶ準備の失敗の知らせを上書きしないため）
            if !Task.isCancelled, request == previewRequest {
                playError = error.message
            }
            return
        }
        // デコードの間に画面を離れた・遊ぶ準備を始めた（失敗して戻った場合も含む）なら鳴らさない
        guard !Task.isCancelled, request == previewRequest, preparing == nil, play == nil else { return }
        let range = SongPreview.range(startTime: info.previewStartTime, duration: info.previewDuration, songDuration: song.duration)
        // 鳴らせなかったとき（出力の機器が無いなど）は、試聴は遊ぶのに要らないので、ボタンを元に戻すだけにする
        isPreviewing = (try? previewer.play(song, range: range)) != nil
    }

    func stopPreview() {
        previewRequest += 1
        previewer.stop()
        isPreviewing = false
    }

    private func loadedSong(info: SongInfo) async throws(MapLoadError) -> DecodedSong {
        if song == nil, decoding == nil {
            decoding = Task {
                do throws(MapLoadError) {
                    song = try await maps.loadSong(hash: entry.hash, info: info)
                    decodeError = nil
                } catch {
                    decodeError = error
                }
                decoding = nil
            }
        }
        await decoding?.value
        if let song { return song }
        throw decodeError ?? .audio(.unreadable)
    }
}
