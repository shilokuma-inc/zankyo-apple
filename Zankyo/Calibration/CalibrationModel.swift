import Foundation
import Observation

/// キャリブレーションの進み具合を持つ。クリックを鳴らしながら振りを検出し、終わったらずれを求める
@Observable
final class CalibrationModel {
    enum Phase: Equatable {
        case idle
        /// `beat` 回目のクリックまで鳴った
        case measuring(beat: Int, total: Int)
        case finished(CalibrationResult)
        case failed(String)
    }

    static let bpm = 100.0
    static let beats = 20
    /// 最後のクリックの後、振りを待つ秒
    private static let tail: TimeInterval = 0.6

    private(set) var phase: Phase = .idle
    private(set) var savedOffset: TimeInterval?

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
        if case .measuring = phase { return true }
        return false
    }

    /// 入力が使えるか、使い始めれば許可を尋ねられる状態なら測れる
    var canMeasure: Bool {
        input.status == .ready || input.status == .notDetermined
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
        phase = .measuring(beat: 0, total: clicks.count)

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
            }
            updateProgress(clicks: clicks, at: sample.timestamp)
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

    private func updateProgress(clicks: [TimeInterval], at time: TimeInterval) {
        guard case .measuring(let current, let total) = phase else { return }
        let beat = clicks.prefix { $0 <= time }.count
        if beat != current {
            phase = .measuring(beat: beat, total: total)
        }
    }
}
