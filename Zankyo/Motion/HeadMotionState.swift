import Foundation

/// 画面に出す頭の動きの状態。サンプルを受け取るたびに、正面からの向き・振りの強さ・検出した振りを更新する
///
/// 振りの検出は判定と同じ `CutDetector` で行うので、ここで光った向きはプレイでもそのまま「切った」向きになる
nonisolated struct HeadMotionState: Sendable {
    /// 検出した振りを光らせておく秒
    static let cutHighlightDuration: TimeInterval = 0.35
    /// 振りの強さが閾値を超えたあと、表示を下げていく速さ（毎秒、閾値に対する割合）
    static let strengthDecayPerSecond = 3.0

    /// 正面からの向き（ラジアン。右・上が正）
    private(set) var orientation = HeadOrientation(yaw: 0, pitch: 0)
    /// 振りの強さ。角速度の大きい方の軸を、振りとみなす閾値で割ったもの（1 以上で振りになる）。すぐ消えないよう、ゆっくり下げる
    private(set) var strength: Double = 0
    /// 最後に検出した振り
    private(set) var lastCut: CutEvent?
    /// 最後に受け取ったサンプルの時刻
    private(set) var lastSampleTime: TimeInterval?

    private var detector: CutDetector
    /// 正面とみなす向き（入力の基準での値）
    private var neutral: HeadOrientation?
    /// 向きの取れない入力のときに、角速度を積み上げた向き
    private var integrated = HeadOrientation(yaw: 0, pitch: 0)

    init(configuration: CutDetector.Configuration = CutDetector.Configuration()) {
        detector = CutDetector(configuration: configuration)
    }

    var threshold: Double { detector.configuration.threshold }

    /// `time`（サンプルと同じ物差しの秒）の時点で、光らせている振りの向き
    func highlightedDirection(at time: TimeInterval) -> SwingDirection? {
        guard let lastCut, time - lastCut.timestamp < Self.cutHighlightDuration else { return nil }
        return lastCut.direction
    }

    mutating func update(with sample: MotionSample) {
        guard sample.timestamp.isFinite, sample.yawRate.isFinite, sample.pitchRate.isFinite else { return }
        let elapsed = lastSampleTime.map { min(max(sample.timestamp - $0, 0), 0.25) } ?? 0
        lastSampleTime = sample.timestamp

        let raw: HeadOrientation
        if let measured = sample.orientation, measured.yaw.isFinite, measured.pitch.isFinite {
            raw = measured
        } else {
            integrated = HeadOrientation(
                yaw: integrated.yaw + sample.yawRate * elapsed,
                pitch: integrated.pitch + sample.pitchRate * elapsed
            )
            raw = integrated
        }
        // 最初の向きを正面にする
        let neutral = neutral ?? raw
        self.neutral = neutral
        orientation = HeadOrientation(yaw: Self.wrap(raw.yaw - neutral.yaw), pitch: Self.wrap(raw.pitch - neutral.pitch))

        let current = max(abs(sample.yawRate), abs(sample.pitchRate)) / threshold
        strength = max(current, strength - Self.strengthDecayPerSecond * elapsed, 0)

        if let cut = detector.process(sample) {
            lastCut = cut
        }
    }

    /// 次のサンプルの向きを正面にする
    mutating func recenter() {
        neutral = nil
        integrated = HeadOrientation(yaw: 0, pitch: 0)
        orientation = HeadOrientation(yaw: 0, pitch: 0)
    }

    /// 取得し直すときに、前の回の状態を消す（正面も決め直す）
    mutating func reset() {
        self = HeadMotionState(configuration: detector.configuration)
    }

    /// 角度を -π〜π に収める
    private static func wrap(_ angle: Double) -> Double {
        var value = angle
        while value > .pi { value -= 2 * .pi }
        while value < -.pi { value += 2 * .pi }
        return value
    }
}
