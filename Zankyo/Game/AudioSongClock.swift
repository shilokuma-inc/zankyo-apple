import AVFoundation
import Foundation

/// デコードした曲を `AVAudioEngine` で鳴らす時計。曲の時刻は「耳に届いている音」の時刻で、出力の遅延（Bluetooth のイヤホンを含む）を差し引く
///
/// 再生を始める時刻を少し先に予約し、その時刻と出力の遅延から「曲の時刻 0 が聞こえる起動からの秒」を決める。
/// 以降の時刻はこの起点からの経過で求めるので、モーションのサンプル（起動からの秒）と同じ物差しで比べられる
final class AudioSongClock: SongClock {
    /// 鳴らし始めるまでの余裕（エンジンの起動と最初の塊の準備を待つ）
    static let leadTime: TimeInterval = 0.3

    let duration: TimeInterval
    private let song: DecodedSong
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let now: () -> TimeInterval
    /// 再生中、曲の時刻 0 が聞こえる（聞こえた）起動からの秒
    private var origin: TimeInterval?
    /// 止めている間の曲の時刻。再生中は、鳴らし始めた位置
    private var resumeTime: TimeInterval = 0

    init(song: DecodedSong, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.song = song
        self.now = now
        duration = song.duration
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: song.format)
    }

    var isPlaying: Bool { origin != nil }

    var currentTime: TimeInterval {
        guard let origin else { return resumeTime }
        // 鳴らし始める前（予約した時刻まで）は、鳴らし始める位置に留める
        return min(max(now() - origin, resumeTime), duration)
    }

    func play() throws {
        guard origin == nil, resumeTime < duration else { return }
        #if !os(macOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        #endif
        if !engine.isRunning {
            try engine.start()
        }
        schedule(from: resumeTime)
        let startHostTime = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: Self.leadTime)
        player.play(at: AVAudioTime(hostTime: startHostTime))
        origin = AVAudioTime.seconds(forHostTime: startHostTime) + outputLatency - resumeTime
    }

    func pause() {
        guard origin != nil else { return }
        resumeTime = currentTime
        origin = nil
        player.stop()
    }

    func stop() {
        resumeTime = 0
        origin = nil
        player.stop()
        engine.stop()
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    func songTime(atUptime uptime: TimeInterval) -> TimeInterval? {
        origin.map { uptime - $0 }
    }

    /// `time` の位置から最後までの塊を予約する。位置を含む塊は、その位置から後ろだけを写して鳴らす
    private func schedule(from time: TimeInterval) {
        let startFrame = AVAudioFramePosition(time * song.format.sampleRate)
        var chunkStart: AVAudioFramePosition = 0
        for chunk in song.chunks {
            let length = AVAudioFramePosition(chunk.frameLength)
            defer { chunkStart += length }
            if chunkStart + length <= startFrame { continue }
            let skip = max(startFrame - chunkStart, 0)
            if skip == 0 {
                player.scheduleBuffer(chunk)
            } else if let tail = Self.tail(of: chunk, from: AVAudioFrameCount(skip)) {
                player.scheduleBuffer(tail)
            }
        }
    }

    private static func tail(of buffer: AVAudioPCMBuffer, from offset: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        let length = buffer.frameLength - offset
        guard let tail = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: length),
              let source = buffer.floatChannelData, let destination = tail.floatChannelData else { return nil }
        for channel in 0..<Int(buffer.format.channelCount) {
            destination[channel].update(from: source[channel] + Int(offset), count: Int(length))
        }
        tail.frameLength = length
        return tail
    }

    /// 鳴らしてから耳に届くまでの秒
    private var outputLatency: TimeInterval {
        #if os(macOS)
        engine.outputNode.presentationLatency
        #else
        AVAudioSession.sharedInstance().outputLatency + AVAudioSession.sharedInstance().ioBufferDuration
        #endif
    }
}
