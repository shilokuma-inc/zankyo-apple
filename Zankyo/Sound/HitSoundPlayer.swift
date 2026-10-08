import AVFoundation
import Foundation

/// ノーツを切ったときの効果音を鳴らすもの。プレイ（`GameSession`）から呼び、テストでは差し替える
protocol HitSoundPlaying: AnyObject {
    /// 鳴らす準備をする（エンジンを起こす）。曲を鳴らし始めるときに呼び、最初の音が遅れないようにする
    func prepare()
    func play()
    func stop()
}

/// `AVAudioEngine` で効果音を鳴らす。曲の再生とは別のエンジンにして、曲の時計（`AudioSongClock`）や曲の音量に影響させない
///
/// 続けて切ったときに前の音を途中で止めないよう、いくつかの再生ノードを順に使う
final class EngineHitSoundPlayer: HitSoundPlaying {
    /// 同時に重ねられる音の数
    private static let voices = 3

    let settings: HitSoundSettings
    /// プレイ中は曲の時計がオーディオセッションを持つので触らない。設定画面の試し聞きでは自分で使い始め、止めるときに返す
    private let managesAudioSession: Bool
    private let engine = AVAudioEngine()
    private let players: [AVAudioPlayerNode]
    private let buffer: AVAudioPCMBuffer?
    private var nextVoice = 0

    init(settings: HitSoundSettings, managesAudioSession: Bool = false) {
        self.settings = settings
        self.managesAudioSession = managesAudioSession
        players = (0..<Self.voices).map { _ in AVAudioPlayerNode() }
        let outputRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let sampleRate = outputRate > 0 ? outputRate : 44_100
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        buffer = format.flatMap { Self.makeBuffer(sound: settings.sound, format: $0) }
        guard let format else { return }
        for player in players {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            player.volume = Float(min(max(settings.volume, 0), 1))
        }
    }

    func prepare() {
        guard settings.isAudible, buffer != nil, !engine.isRunning else { return }
        #if !os(macOS)
        if managesAudioSession {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default)
            try? session.setActive(true)
        }
        #endif
        try? engine.start()
    }

    func play() {
        guard settings.isAudible, let buffer else { return }
        prepare()
        guard engine.isRunning else { return }
        // いちばん前に鳴らしたノードを使い回す（鳴り終わっていなければ、その音だけ止まる）
        let player = players[nextVoice]
        nextVoice = (nextVoice + 1) % players.count
        player.stop()
        player.scheduleBuffer(buffer, at: nil)
        player.play()
    }

    func stop() {
        players.forEach { $0.stop() }
        engine.stop()
        #if !os(macOS)
        if managesAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        #endif
    }

    private static func makeBuffer(sound: HitSound, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let samples = HitSoundSynthesizer.samples(for: sound, sampleRate: format.sampleRate)
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (index, value) in samples.enumerated() {
            channel[index] = value
        }
        return buffer
    }
}
