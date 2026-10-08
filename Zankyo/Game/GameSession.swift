import Foundation
import Observation

/// 1 曲分のプレイ。曲の時計・モーション入力・「切る」検出・判定をつなぐ
///
/// 振りは届いたときに判定し、窓を過ぎたノーツは画面のフレームごとの `tick()` でミスにする。
/// 遊び方がヘドバンなら、ノーツの向きを問わない（矢印を出さず、向き違いにもしない）。ハイスコアは遊び方ごとに分ける
@Observable
final class GameSession {
    enum Phase: Equatable {
        case ready
        case playing
        case paused
        case finished
    }

    private(set) var phase: Phase = .ready
    private(set) var judge: Judge
    /// 直近の判定（画面に一瞬出す）
    private(set) var lastJudgement: Judgement?
    /// 直近のフレームの曲の時刻
    private(set) var currentTime: TimeInterval = 0
    /// イヤホンが外れて一時停止した
    private(set) var pausedByDisconnection = false
    /// 終えたときの結果。始められずに終えたときは nil
    private(set) var result: PlayResult?
    /// この回より前のハイスコア
    private(set) var previousBest: PlayResult?
    /// この回でハイスコアを更新した
    private(set) var isNewRecord = false

    let input: any MotionInput
    @ObservationIgnored let clock: any SongClock
    @ObservationIgnored private let detection: SwingDetection
    @ObservationIgnored private var detector: any SwingDetector
    @ObservationIgnored private var task: Task<Void, Never>?
    /// 一度でも入力が使える状態になった（始めた直後の、接続の通知が届く前の状態で止めないため）
    @ObservationIgnored private var wasInputReady = false
    @ObservationIgnored private let scoreKey: ScoreKey?
    @ObservationIgnored private let highScores: HighScoreStore?

    init(
        notes: [FaceNote],
        clock: any SongClock,
        input: any MotionInput,
        detection: SwingDetection = SwingDetection(),
        offset: TimeInterval = 0,
        rules: ScoringRules = ScoringRules(),
        scoreKey: ScoreKey? = nil,
        highScores: HighScoreStore? = nil
    ) {
        let notes = detection.style.usesDirection ? notes : notes.map { FaceNote(beat: $0.beat, time: $0.time, direction: nil) }
        judge = Judge(notes: notes, rules: rules, offset: offset)
        self.detection = detection
        detector = detection.makeDetector()
        self.clock = clock
        self.input = input
        self.scoreKey = scoreKey?.playing(detection.style)
        self.highScores = highScores
    }

    /// 入力が使えるか、使い始めれば許可を尋ねられる状態なら始められる
    var canStart: Bool {
        input.status == .ready || input.status == .notDetermined
    }

    var score: Int { judge.keeper.score }
    var combo: Int { judge.keeper.combo }
    var multiplier: Int { judge.keeper.multiplier }

    func start() {
        guard phase == .ready else { return }
        task = Task { await play() }
    }

    /// 再生と入力を始め、入力が終わる（`finish()` で止める・入力が切れる）まで振りを判定し続ける
    func play() async {
        guard phase == .ready else { return }
        let stream = input.start()
        do {
            try clock.play()
        } catch {
            input.stop()
            phase = .finished
            return
        }
        phase = .playing
        for await sample in stream {
            guard let cut = detector.process(sample) else { continue }
            handle(cut)
        }
    }

    /// 検出した振りを判定する。一時停止中・再生していない時刻の振りは数えない
    func handle(_ cut: CutEvent) {
        guard phase == .playing, let time = clock.songTime(atUptime: cut.timestamp) else { return }
        if let judgement = judge.cut(cut, at: time) {
            lastJudgement = judgement
        }
    }

    /// 画面のフレームごとに呼ぶ。窓を過ぎたノーツをミスにし、曲の終わりで終える
    func tick() {
        guard phase == .playing else { return }
        currentTime = clock.currentTime
        if let judgement = judge.advance(to: currentTime).last {
            lastJudgement = judgement
        }
        if input.status == .ready {
            wasInputReady = true
        } else if wasInputReady {
            // プレイ中にイヤホンが外れた・許可が取り消された
            pausedByDisconnection = true
            pause()
            return
        }
        if currentTime >= clock.duration {
            finish()
        }
    }

    func pause() {
        guard phase == .playing else { return }
        clock.pause()
        phase = .paused
    }

    func resume() {
        guard phase == .paused, input.status == .ready || input.status == .notDetermined else { return }
        do {
            try clock.play()
        } catch {
            return
        }
        // 止めている間の動きの途中から振りを数えない
        detector = detection.makeDetector()
        pausedByDisconnection = false
        phase = .playing
    }

    /// 終える。残ったノーツはすべてミスにし、結果をまとめてハイスコアに記録する
    func finish() {
        guard phase != .finished else { return }
        judge.advance(to: .greatestFiniteMagnitude)
        clock.stop()
        input.stop()
        task?.cancel()
        task = nil
        let result = judge.result()
        self.result = result
        if let scoreKey, let highScores {
            previousBest = highScores.best(for: scoreKey)
            isNewRecord = highScores.record(result, for: scoreKey)
        }
        phase = .finished
    }
}
