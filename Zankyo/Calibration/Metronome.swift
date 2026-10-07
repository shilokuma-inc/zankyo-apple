import AVFoundation
import Foundation

/// 一定の間隔でクリック音を鳴らす。キャリブレーションで使い、テストでは差し替える
protocol Metronome: AnyObject {
    /// 鳴らし始め、各クリックが聞こえる予定の時刻を返す。時刻はモーションのサンプルと同じ「起動からの秒」
    func start(bpm: Double, beats: Int) throws -> [TimeInterval]
    func stop()
}

/// `AVAudioEngine` でクリック音を鳴らす。出力の遅延（Bluetooth のイヤホンを含む）を、聞こえる時刻に足す
final class ClickMetronome: Metronome {
    /// 鳴らし始めるまでの余裕（エンジンの起動を待つ）
    private static let leadTime: TimeInterval = 0.5
    /// 前打ち（最初の数回）は高い音にして、数えないことを伝える
    private let countIn: Int

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

    init(countIn: Int = CalibrationAnalyzer.Configuration().countIn) {
        self.countIn = countIn
        engine.attach(player)
    }

    func start(bpm: Double, beats: Int) throws -> [TimeInterval] {
        stop()
        guard bpm.isFinite, bpm > 0, beats > 0 else { return [] }
        #if !os(macOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        #endif

        let outputRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let sampleRate = outputRate > 0 ? outputRate : 44_100
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return [] }
        let interval = 60 / bpm
        guard let buffer = Self.clickTrack(format: format, interval: interval, beats: beats, countIn: countIn) else { return [] }
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try engine.start()

        let startHostTime = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: Self.leadTime)
        player.scheduleBuffer(buffer, at: nil)
        player.play(at: AVAudioTime(hostTime: startHostTime))

        let start = AVAudioTime.seconds(forHostTime: startHostTime) + outputLatency
        return (0..<beats).map { start + Double($0) * interval }
    }

    func stop() {
        player.stop()
        engine.stop()
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// 鳴らしてから耳に届くまでの秒
    private var outputLatency: TimeInterval {
        #if os(macOS)
        engine.outputNode.presentationLatency
        #else
        AVAudioSession.sharedInstance().outputLatency + AVAudioSession.sharedInstance().ioBufferDuration
        #endif
    }

    /// すべてのクリックを並べた 1 本の音。クリックは 30ms の減衰する正弦波
    private static func clickTrack(format: AVAudioFormat, interval: TimeInterval, beats: Int, countIn: Int) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let clickLength = Int(sampleRate * 0.03)
        let frames = AVAudioFrameCount(sampleRate * (interval * Double(beats) + 0.1))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for index in 0..<Int(frames) {
            samples[index] = 0
        }
        for beat in 0..<beats {
            let frequency: Double = beat < countIn ? 1_760 : 880
            let start = Int((Double(beat) * interval * sampleRate).rounded())
            for offset in 0..<clickLength where start + offset < Int(frames) {
                let time = Double(offset) / sampleRate
                let envelope = 1 - Double(offset) / Double(clickLength)
                samples[start + offset] = Float(sin(2 * Double.pi * frequency * time) * envelope * 0.6)
            }
        }
        return buffer
    }
}
