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

/// 曲の詳細（難易度の選択）の状態。曲情報を読み、選んだ難易度のノーツと音源を用意する
///
/// 音源のデコードは重いので、この画面にいる間は 1 度だけ行い、難易度を変えても使い回す
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

    @ObservationIgnored private let maps: LocalMapStore
    @ObservationIgnored private var song: DecodedSong?
    /// デコード中の音源。デコードを待つ間にもう一度求められても、デコードは 1 度にする（長い曲は数百 MB になるため）
    @ObservationIgnored private var decoding: Task<Void, Never>?
    /// 直近のデコードに失敗した理由
    @ObservationIgnored private var decodeError: MapLoadError?

    init(entry: LibraryEntry, maps: LocalMapStore = LocalMapStore()) {
        self.entry = entry
        self.maps = maps
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
