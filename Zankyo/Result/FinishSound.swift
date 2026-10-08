import AVFoundation
import Foundation

/// 曲を最後まで遊んだときの音。ゲームやテストからはこのプロトコル越しに使う
protocol FinishSounding: AnyObject {
    /// 終わりの効果音を鳴らし、続けて結果画面の間、曲の聞きどころを小さめの音量でくり返す
    func play()
    func stop()
}

/// 終わりの効果音（`FinishJingle`）を鳴らし、和音の余韻に重ねて、曲の聞きどころを小さめの音量でくり返す
///
/// 鳴らせなかったとき（出力の機器が無いなど）は何もしない。音が無くても結果は見られるので、エラーにはしない
final class FinishSoundPlayer: FinishSounding {
    /// 結果画面で流す曲の音量（効果音は 1）。結果を読む邪魔にならないよう小さめにする
    static let loopVolume: Float = 0.45
    /// 効果音を鳴らし始めてから、曲を流し始めるまでの秒（和音の余韻に重ねる）
    static let loopDelay: TimeInterval = 1.2
    /// 曲を流し始めるときに、音を大きくしていく秒
    static let loopFadeIn: TimeInterval = 2.5

    private let song: DecodedSong
    private let loopRange: Range<TimeInterval>
    private let engine = AVAudioEngine()
    private let jingle = AVAudioPlayerNode()
    private let loop = AVAudioPlayerNode()
    private var isPlaying = false

    /// - Parameter loopRange: 結果画面で流す区間（試聴と同じ聞きどころ）
    init(song: DecodedSong, loopRange: Range<TimeInterval>) {
        self.song = song
        self.loopRange = loopRange
        engine.attach(jingle)
        engine.attach(loop)
    }

    func play() {
        stop()
        let format = song.format
        guard let jingleBuffer = FinishJingle.buffer(format: format) else { return }
        #if !os(macOS)
        let session = AVAudioSession.sharedInstance()
        guard (try? session.setCategory(.playback, mode: .default)) != nil, (try? session.setActive(true)) != nil else { return }
        #endif
        engine.connect(jingle, to: engine.mainMixerNode, format: format)
        engine.connect(loop, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
        } catch {
            Self.releaseSession()
            return
        }
        jingle.scheduleBuffer(jingleBuffer)
        jingle.play()
        if let loopBuffer = SongPreviewPlayer.loopBuffer(of: song, range: loopRange, fade: SongPreview.fadeDuration) {
            // 1 周目だけ静かに入り、2 周目からは試聴と同じつなぎ目でくり返す
            if let intro = Self.fadedIn(loopBuffer, over: Self.loopFadeIn) {
                loop.scheduleBuffer(intro)
            }
            loop.scheduleBuffer(loopBuffer, at: nil, options: .loops)
            loop.volume = Self.loopVolume
            loop.play(at: AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: Self.loopDelay)))
        }
        isPlaying = true
    }

    func stop() {
        guard isPlaying else { return }
        jingle.stop()
        loop.stop()
        engine.stop()
        isPlaying = false
        Self.releaseSession()
    }

    /// オーディオセッションを手放し、止めていたほかのアプリの音に再開してよいと伝える
    private static func releaseSession() {
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// `buffer` を写し、頭から `duration` 秒かけて音を大きくしていく
    private static func fadedIn(_ buffer: AVAudioPCMBuffer, over duration: TimeInterval) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength),
              let source = buffer.floatChannelData, let destination = copy.floatChannelData else { return nil }
        let length = Int(buffer.frameLength)
        copy.frameLength = buffer.frameLength
        let fadeFrames = min(Int(duration * buffer.format.sampleRate), length)
        for channel in 0..<Int(buffer.format.channelCount) {
            destination[channel].update(from: source[channel], count: length)
            for index in 0..<fadeFrames {
                destination[channel][index] *= Float(index) / Float(fadeFrames)
            }
        }
        return copy
    }
}

/// 曲を終えたときの効果音。素材を使わず、アプリの中で合成する
///
/// ド・ミ・ソ・ドと駆け上がったあと、低いドを足した和音を伸ばす。和音の頭に低い打撃音を重ね、ディレイで余韻を残す
nonisolated enum FinishJingle {
    /// 長さ（秒）。ディレイの余韻を含む
    static let duration: TimeInterval = 2.2
    /// 最も大きいところの振幅
    static let peak: Float = 0.5

    struct Tone: Sendable {
        /// 鳴らし始める秒
        let start: TimeInterval
        let frequency: Double
        /// 鳴らす秒（減衰して 0 になるまで）
        let length: TimeInterval
        let gain: Double
    }

    /// 和音を鳴らし始める秒
    static let chordStart: TimeInterval = 0.3

    static let tones: [Tone] = {
        let arpeggio = [523.25, 659.26, 783.99, 1_046.50].enumerated().map { index, frequency in
            Tone(start: Double(index) * 0.07, frequency: frequency, length: 0.25, gain: 0.8)
        }
        let chord = [261.63, 523.25, 659.26, 783.99, 1_046.50, 1_318.51].map { frequency in
            Tone(start: chordStart, frequency: frequency, length: 1.4, gain: 0.5)
        }
        return arpeggio + chord
    }()

    /// 1 チャンネル分の波形
    static func samples(sampleRate: Double) -> [Float] {
        guard sampleRate > 0 else { return [] }
        var output = [Float](repeating: 0, count: Int(duration * sampleRate))
        let table = waveTable()
        for tone in tones {
            add(tone, table: table, to: &output, sampleRate: sampleRate)
        }
        addImpact(at: chordStart, to: &output, sampleRate: sampleRate)
        addEcho(to: &output, delay: 0.16, feedback: 0.35, sampleRate: sampleRate)
        normalize(&output, peak: peak)
        // 余韻の終わりで音が途切れないよう、最後の 0.2 秒で 0 にする
        let fadeFrames = min(Int(0.2 * sampleRate), output.count)
        for index in 0..<fadeFrames {
            output[output.count - 1 - index] *= Float(index) / Float(fadeFrames)
        }
        return output
    }

    /// `format`（曲と同じ形式）の塊にする。どのチャンネルにも同じ波形を入れる
    static func buffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let samples = samples(sampleRate: format.sampleRate)
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for channel in 0..<Int(format.channelCount) {
            samples.withUnsafeBufferPointer { source in
                if let base = source.baseAddress {
                    channels[channel].update(from: base, count: samples.count)
                }
            }
        }
        return buffer
    }

    /// 1 周期分の波形の表。のこぎり波の倍音を 6 つまで重ね、明るいシンセの音にする（高い倍音を持たないので折り返さない）
    private static func waveTable(size: Int = 2_048) -> [Float] {
        (0..<size).map { index in
            let phase = 2 * Double.pi * Double(index) / Double(size)
            let value = (1...6).reduce(0.0) { sum, harmonic in sum + sin(phase * Double(harmonic)) / Double(harmonic) }
            return Float(value * 0.55)
        }
    }

    /// 少しだけ音程をずらした 2 つの声を重ねて足す。立ち上がりは 5ms、その後はゆるやかに減衰し、最後の 1/4 で 0 まで絞る
    private static func add(_ tone: Tone, table: [Float], to output: inout [Float], sampleRate: Double) {
        let first = Int(tone.start * sampleRate)
        let count = min(Int(tone.length * sampleRate), output.count - first)
        guard first >= 0, count > 0 else { return }
        let attack = 0.005 * sampleRate
        let decay = tone.length / 2.5
        let release = Double(count) / 4
        let detunes = [0.997, 1.003]
        let tableSize = Double(table.count)
        for index in 0..<count {
            let time = Double(index) / sampleRate
            let envelope = min(Double(index) / attack, 1) * exp(-time / decay) * min(Double(count - index) / release, 1)
            var value: Float = 0
            for detune in detunes {
                let position = (time * tone.frequency * detune).truncatingRemainder(dividingBy: 1) * tableSize
                value += table[Int(position) % table.count]
            }
            output[first + index] += value * Float(envelope * tone.gain / Double(detunes.count))
        }
    }

    /// 和音の頭の低い打撃音（120Hz から 45Hz へ下がる正弦波）
    private static func addImpact(at start: TimeInterval, to output: inout [Float], sampleRate: Double) {
        let first = Int(start * sampleRate)
        let count = min(Int(0.35 * sampleRate), output.count - first)
        guard first >= 0, count > 0 else { return }
        var phase = 0.0
        for index in 0..<count {
            let time = Double(index) / sampleRate
            let frequency = 45 + 75 * exp(-time / 0.05)
            phase += 2 * Double.pi * frequency / sampleRate
            output[first + index] += Float(sin(phase) * exp(-time / 0.1) * 0.9)
        }
    }

    /// くり返し小さくなっていくディレイ
    private static func addEcho(to output: inout [Float], delay: TimeInterval, feedback: Float, sampleRate: Double) {
        let offset = Int(delay * sampleRate)
        guard offset > 0, offset < output.count else { return }
        for index in offset..<output.count {
            output[index] += output[index - offset] * feedback
        }
    }

    private static func normalize(_ output: inout [Float], peak: Float) {
        let loudest = output.reduce(0) { max($0, abs($1)) }
        guard loudest > 0 else { return }
        let gain = peak / loudest
        for index in output.indices {
            output[index] *= gain
        }
    }
}
