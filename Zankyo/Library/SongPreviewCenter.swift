import Foundation
import Observation

/// アプリ全体で 1 つの試聴。画面を移っても鳴らし続け、一覧と曲の詳細のどちらからでも始め・止められる
///
/// 同時に鳴らすのは 1 曲で、別の曲を試聴すると前の曲は止める。遊び始めるとき・キャリブレーションを測り始めるときは止める
@Observable
final class SongPreviewCenter {
    /// 鳴らしている曲の譜面ハッシュ
    private(set) var playingHash: String?
    /// 一覧から試聴するために、曲情報と音源を読んでいる曲の譜面ハッシュ
    private(set) var loadingHash: String?
    /// 一覧から始めた試聴を鳴らせなかった理由（画面に出したら nil に戻す）
    var error: String?

    @ObservationIgnored private let previewer: any SongPreviewing
    @ObservationIgnored private let maps: LocalMapStore
    /// 鳴らすつもりで読んでいる試聴。止めたら取り消して nil にする
    @ObservationIgnored private var loading: Task<Void, Never>?
    /// 最後に始めた読み込み。止めてもデコードは途中で止まらないので、終わるまで次の読み込みを待たせるために持ち続ける
    @ObservationIgnored private var lastLoading: Task<Void, Never>?
    /// 試聴を求めた回数。止めた・別の曲にしたときも増やし、読み終えるのを待っている間に変わった試聴を鳴らさない
    @ObservationIgnored private var request = 0

    init(previewer: any SongPreviewing = SongPreviewPlayer(), maps: LocalMapStore = LocalMapStore()) {
        self.previewer = previewer
        self.maps = maps
    }

    func isPlaying(_ hash: String) -> Bool {
        playingHash == hash
    }

    func isLoading(_ hash: String) -> Bool {
        loadingHash == hash
    }

    /// 一覧から: その曲を鳴らしている（読んでいる）なら止め、そうでなければ曲情報と音源を読んで鳴らす
    func toggle(_ entry: LibraryEntry) {
        if isPlaying(entry.hash) || isLoading(entry.hash) {
            stop()
            return
        }
        // 止めても、始まったデコードは途中で止まらない。続けて押したときにデコードを重ねない（長い曲は数百 MB になる）よう、前の読み込みが終わるのを待つ
        let previous = lastLoading
        stop()
        let current = request
        loadingHash = entry.hash
        let task = Task {
            await previous?.value
            guard !Task.isCancelled, request == current else { return }
            do throws(MapLoadError) {
                let info = try await maps.loadInfo(hash: entry.hash)
                guard !Task.isCancelled, request == current else { return }
                let song = try await maps.loadSong(hash: entry.hash, info: info)
                guard request == current else { return }
                // 一覧では、押しても何も起きないように見えないよう、鳴らせなかったことを知らせる
                if !play(song, info: info, hash: entry.hash) {
                    self.error = "試聴を再生できませんでした。ほかのアプリで音を再生していないか確かめてください。"
                }
            } catch {
                guard request == current else { return }
                loadingHash = nil
                self.error = error.message
            }
        }
        loading = task
        lastLoading = task
    }

    /// 読み終えた音源で鳴らす（曲の詳細から。デコードした音源を使い回す）。鳴らしていた曲は止める。鳴らせたら true
    @discardableResult
    func play(_ song: DecodedSong, info: SongInfo, hash: String) -> Bool {
        stop()
        let range = SongPreview.range(startTime: info.previewStartTime, duration: info.previewDuration, songDuration: song.duration)
        // 鳴らせなかったとき（出力の機器が無いなど）は、試聴は遊ぶのに要らないので、鳴らしていない状態に戻すだけにする
        guard (try? previewer.play(song, range: range)) != nil else { return false }
        playingHash = hash
        return true
    }

    /// 試聴を止める。読んでいる途中の試聴も鳴らさない
    func stop() {
        request += 1
        loading?.cancel()
        loading = nil
        loadingHash = nil
        previewer.stop()
        playingHash = nil
    }
}
