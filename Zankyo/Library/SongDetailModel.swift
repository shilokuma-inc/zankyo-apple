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
            state = .ready(info)
            cover = await maps.loadCover(hash: entry.hash, info: info)
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
            play = PlaySetup(entry: entry, difficulty: difficulty, notes: notes, song: song)
        } catch {
            guard !Task.isCancelled else { return }
            playError = error.message
        }
    }

    private func loadedSong(info: SongInfo) async throws(MapLoadError) -> DecodedSong {
        if let song { return song }
        let loaded = try await maps.loadSong(hash: entry.hash, info: info)
        song = loaded
        return loaded
    }
}
