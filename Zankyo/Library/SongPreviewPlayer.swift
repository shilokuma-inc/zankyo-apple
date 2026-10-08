import AVFoundation
import Foundation

/// 曲の試聴。画面やテストからはこのプロトコル越しに使う
protocol SongPreviewing: AnyObject {
    var isPlaying: Bool { get }
    /// `song` の `range` をくり返し鳴らす。鳴らしていたものは止める
    func play(_ song: DecodedSong, range: Range<TimeInterval>) throws
    func stop()
}

nonisolated enum SongPreviewError: Error, Equatable {
    /// 試聴する区間が空
    case emptyRange
}

/// デコードした曲の試聴区間を、始めと終わりをフェードして `AVAudioEngine` でくり返し鳴らす
final class SongPreviewPlayer: SongPreviewing {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private(set) var isPlaying = false

    init() {
        engine.attach(player)
    }

    func play(_ song: DecodedSong, range: Range<TimeInterval>) throws {
        stop()
        guard let loop = Self.loopBuffer(of: song, range: range, fade: SongPreview.fadeDuration) else {
            throw SongPreviewError.emptyRange
        }
        #if !os(macOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        #endif
        engine.connect(player, to: engine.mainMixerNode, format: song.format)
        do {
            try engine.start()
        } catch {
            // まだ鳴らしていない（`isPlaying` が false の）ので `stop()` では返らない。取ったオーディオセッションをここで返す
            Self.releaseSession()
            throw error
        }
        player.scheduleBuffer(loop, at: nil, options: .loops)
        player.play()
        isPlaying = true
    }

    func stop() {
        guard isPlaying else { return }
        player.stop()
        engine.stop()
        isPlaying = false
        // 遊ぶ画面の音（別のエンジン）を鳴らしている間に呼ばれても切らないよう、鳴らしていたときだけ手放す
        Self.releaseSession()
    }

    /// オーディオセッションを手放し、止めていたほかのアプリの音に再開してよいと伝える
    private static func releaseSession() {
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// 曲の `range` を 1 つの塊に写し、始めと終わりを `fade` 秒かけてフェードする（くり返したときのつなぎ目で音が跳ねないように）
    static func loopBuffer(of song: DecodedSong, range: Range<TimeInterval>, fade: TimeInterval) -> AVAudioPCMBuffer? {
        let sampleRate = song.format.sampleRate
        let start = AVAudioFramePosition(max(range.lowerBound, 0) * sampleRate)
        let end = min(AVAudioFramePosition(max(range.upperBound, 0) * sampleRate), song.frameCount)
        guard end > start, let loop = AVAudioPCMBuffer(pcmFormat: song.format, frameCapacity: AVAudioFrameCount(end - start)),
              let destination = loop.floatChannelData else { return nil }
        let channels = Int(song.format.channelCount)

        // 区間に重なる塊から、重なる部分だけを写す
        var chunkStart: AVAudioFramePosition = 0
        for chunk in song.chunks {
            let chunkEnd = chunkStart + AVAudioFramePosition(chunk.frameLength)
            defer { chunkStart = chunkEnd }
            let from = max(start, chunkStart)
            let until = min(end, chunkEnd)
            guard from < until, let source = chunk.floatChannelData else { continue }
            for channel in 0..<channels {
                (destination[channel] + Int(from - start)).update(from: source[channel] + Int(from - chunkStart), count: Int(until - from))
            }
        }
        let length = Int(end - start)
        loop.frameLength = AVAudioFrameCount(length)

        let fadeFrames = min(Int(fade * sampleRate), length / 2)
        guard fadeFrames > 0 else { return loop }
        for index in 0..<fadeFrames {
            let gain = Float(index) / Float(fadeFrames)
            for channel in 0..<channels {
                destination[channel][index] *= gain
                destination[channel][length - 1 - index] *= gain
            }
        }
        return loop
    }
}
