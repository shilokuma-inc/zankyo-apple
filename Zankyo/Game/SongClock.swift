import Foundation

/// 曲の時計。音源の再生の後ろに隠し、ゲームはこの時計の時刻（曲の先頭からの秒）で判定する
protocol SongClock: AnyObject {
    /// 今、耳に届いている音の曲の時刻（出力の遅延を差し引いたもの）
    var currentTime: TimeInterval { get }
    /// 曲の長さ
    var duration: TimeInterval { get }
    var isPlaying: Bool { get }
    /// 再生する。一時停止していたら、止めた位置から続ける
    func play() throws
    func pause()
    func stop()
    /// モーションのサンプルの時刻（起動からの秒）を、曲の時刻に直す。再生していなければ nil
    func songTime(atUptime uptime: TimeInterval) -> TimeInterval?
}

/// 音を鳴らさず、時間だけ進める時計。音源の再生（Ogg Vorbis）が入るまでのデバッグ・プレビュー・テスト用
final class SilentSongClock: SongClock {
    let duration: TimeInterval
    private let now: () -> TimeInterval
    /// 再生中、曲の時刻 0 に当たる起動からの秒
    private var origin: TimeInterval?
    /// 止めている間の曲の時刻
    private var pausedTime: TimeInterval = 0

    init(duration: TimeInterval, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.duration = max(duration, 0)
        self.now = now
    }

    var isPlaying: Bool { origin != nil }

    var currentTime: TimeInterval {
        guard let origin else { return pausedTime }
        return min(now() - origin, duration)
    }

    func play() {
        guard origin == nil else { return }
        origin = now() - pausedTime
    }

    func pause() {
        pausedTime = currentTime
        origin = nil
    }

    func stop() {
        pausedTime = 0
        origin = nil
    }

    func songTime(atUptime uptime: TimeInterval) -> TimeInterval? {
        origin.map { uptime - $0 }
    }
}
