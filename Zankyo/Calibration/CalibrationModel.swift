import Foundation
import Observation

/// キャリブレーションの進み具合を持つ。クリックを鳴らしながら振りを検出し、終わったらずれを求める
@Observable
final class CalibrationModel {
    enum Phase: Equatable {
        case idle
        /// 何拍目かは、サンプルの届き方に左右されないよう時刻から求める（`CalibrationCue`）
        case measuring
        case finished(CalibrationResult)
        case failed(String)
    }

    static let bpm = 100.0
    static let beats = 20
    /// 最後のクリックの後、振りを待つ秒
    private static let tail: TimeInterval = 0.6

    private(set) var phase: Phase = .idle
    private(set) var savedOffset: TimeInterval?
    /// 測っている回のクリックが聞こえる時刻と、検出した振りの時刻。画面の手がかり（`CalibrationCue`）に使う
    private(set) var clickTimes: [TimeInterval] = []
    private(set) var cutTimes: [TimeInterval] = []

    let input: any MotionInput
    @ObservationIgnored private let metronome: any Metronome
    @ObservationIgnored private let store: CalibrationStore
    @ObservationIgnored private let now: () -> TimeInterval
    @ObservationIgnored private var task: Task<Void, Never>?
    /// 測る回ごとの番号。前の回の締め切りが、新しい回の入力を止めないようにする
    @ObservationIgnored private var generation = 0

    init(
        input: any MotionInput,
        metronome: any Metronome,
        store: CalibrationStore = CalibrationStore(),
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.input = input
        self.metronome = metronome
        self.store = store
        self.now = now
        savedOffset = store.hasOffset ? store.offset : nil
    }

    var isMeasuring: Bool {
        phase == .measuring
    }

    /// 入力が使えるか、使い始めれば許可を尋ねられる状態なら測れる
    var canMeasure: Bool {
        input.status == .ready || input.status == .notDetermined
    }

    var cue: CalibrationCue {
        CalibrationCue(clickTimes: clickTimes)
    }

    /// クリックと同じ物差し（起動からの秒）の今の時刻
    var currentTime: TimeInterval {
        now()
    }

    func start() {
        guard !isMeasuring else { return }
        task?.cancel()
        task = Task { await measure() }
    }

    func cancel() {
        task?.cancel()
        task = nil
        input.stop()
        metronome.stop()
        phase = .idle
    }

    func save() {
        guard case .finished(let result) = phase else { return }
        store.save(result.offset)
        savedOffset = store.offset
        phase = .idle
    }

    func resetSavedOffset() {
        store.reset()
        savedOffset = nil
    }

    /// 測る。終わる（最後のクリックを過ぎる・入力が終わる・中止する）まで返らない
    func measure() async {
        // 開始を続けて押したときなど、始まる前に中止された回は何もしない（新しい回の入力と音を奪わない）
        guard !Task.isCancelled else { return }
        generation += 1
        let currentGeneration = generation
        let stream = input.start()
        let clicks: [TimeInterval]
        do {
            clicks = try metronome.start(bpm: Self.bpm, beats: Self.beats)
        } catch {
            input.stop()
            metronome.stop()
            phase = .failed("音を鳴らせませんでした。ほかのアプリで音を再生していないか確かめてください。")
            return
        }
        guard let lastClick = clicks.last else {
            input.stop()
            metronome.stop()
            phase = .failed("音を鳴らせませんでした。")
            return
        }
        clickTimes = clicks
        cutTimes = []
        phase = .measuring

        let deadline = lastClick + Self.tail
        // 振りが届かなくても、最後のクリックを過ぎたら入力を止めて終える
        let waitSeconds = max(deadline - now(), 0)
        let stopper = Task { [weak self] in
            try? await Task.sleep(for: .seconds(waitSeconds))
            guard !Task.isCancelled, let self, self.generation == currentGeneration else { return }
            self.input.stop()
        }
        defer { stopper.cancel() }

        var detector = CutDetector()
        var cuts: [TimeInterval] = []
        for await sample in stream {
            if let cut = detector.process(sample) {
                cuts.append(cut.timestamp)
                // 中止の後に残ったサンプルで、新しい回の表示を書き換えない
                if generation == currentGeneration {
                    cutTimes = cuts
                }
            }
            if sample.timestamp > deadline { break }
        }
        // 中止の後に新しい回が始まっていたら、その回の入力と音を止めない
        guard generation == currentGeneration else { return }
        input.stop()
        metronome.stop()
        guard !Task.isCancelled else { return }

        if let result = CalibrationAnalyzer.analyze(clickTimes: clicks, cutTimes: cuts) {
            phase = .finished(result)
        } else {
            phase = .failed("振りを十分に検出できませんでした。低い音に合わせて、首を左右か上下にはっきり振ってください。")
        }
    }
}
