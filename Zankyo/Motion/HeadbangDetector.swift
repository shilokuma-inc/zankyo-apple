import Foundation

/// 向きを問わず、頭を振る（ヘドバン）動きを検出する。遊び方がヘドバン（`PlayStyle.headbang`）のときに使う
///
/// 左右と上下の角速度を合わせた大きさ（頭の回る速さ）が `threshold` を超えてから、振りの向きへの速さがピークの `releaseRatio` を
/// 下回るまでを 1 回の振りとみなし、ピークの時刻で 1 つの `CutEvent` を出す。軸に分けないので、斜めや弧を描く振りも 1 回に数える
///
/// `CutDetector` と違い、首を戻す逆向きの振りを間引かない。間引くと、戻す動きから振り始めたときに戻す側の振りだけを数え続け、
/// 拍の裏で振ったことになってしまう（どちらが戻す動きかは、向きを決めない遊び方では分からない）。
/// 1 拍に表と裏の 2 回の振りが出ても、ノーツの時間窓（前後 `ScoringRules.hitWindow`）に入るのは拍に合わせた方の振りだけ
nonisolated struct HeadbangDetector: SwingDetector {
    nonisolated struct Configuration: Sendable, Hashable {
        /// 振りとみなす頭の回る速さ（ラジアン毎秒）。利用者が変えられる（`SwingSensitivityStore`）
        var threshold: Double = 1.5
        /// 振りの向きへの速さが、ピークのこの割合まで下がったら振りが終わったとみなす
        var releaseRatio: Double = 0.5
        /// 振りを出した後、次の振りを出さない時間（秒）。1 回の振りの速さの揺れを 2 回に数えない
        var refractory: TimeInterval = 0.12
    }

    /// 振りの途中のピーク
    private struct Peak {
        var timestamp: TimeInterval
        var yawRate: Double
        var pitchRate: Double

        var speed: Double { hypot(yawRate, pitchRate) }

        /// サンプルの角速度の、このピークの向きの成分。逆向きに動いているときは負
        func rate(along sample: MotionSample) -> Double {
            let speed = speed
            guard speed > 0 else { return 0 }
            return (sample.yawRate * yawRate + sample.pitchRate * pitchRate) / speed
        }
    }

    let configuration: Configuration
    private var peak: Peak?
    /// 直前に終えた振り。速さが閾値を下回るか、逆向きに動き出すまで次の振りを始めない
    /// （減っていく途中の強い振りを、もう一度数えない）
    private var settling: Peak?
    private var lastCutTime: TimeInterval?

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// サンプルを 1 つ受け取り、振りが終わったときだけ `CutEvent` を返す
    mutating func process(_ sample: MotionSample) -> CutEvent? {
        guard sample.yawRate.isFinite, sample.pitchRate.isFinite, sample.timestamp.isFinite else { return nil }
        let speed = hypot(sample.yawRate, sample.pitchRate)

        var cut: CutEvent?
        if var current = peak {
            if speed > current.speed {
                current = Peak(timestamp: sample.timestamp, yawRate: sample.yawRate, pitchRate: sample.pitchRate)
            }
            // ピークの向きへの速さで終わりを決める。止まったときだけでなく、止まりきらずに折り返したとき
            // （サンプルの間隔が粗く、折り返しの遅いところが取れないとき）も振りを終える
            guard current.rate(along: sample) < current.speed * configuration.releaseRatio else {
                peak = current
                return nil
            }
            peak = nil
            settling = current
            cut = emit(current)
        }
        if let previous = settling, speed < configuration.threshold || previous.rate(along: sample) <= 0 {
            settling = nil
        }
        if peak == nil, settling == nil, speed >= configuration.threshold {
            peak = Peak(timestamp: sample.timestamp, yawRate: sample.yawRate, pitchRate: sample.pitchRate)
        }
        return cut
    }

    /// 不応期の中の振りを除いて、振りを確定する
    private mutating func emit(_ peak: Peak) -> CutEvent? {
        if let lastCutTime, peak.timestamp - lastCutTime < configuration.refractory {
            return nil
        }
        lastCutTime = peak.timestamp
        return CutEvent(timestamp: peak.timestamp, direction: Self.direction(of: peak), peakRate: peak.speed)
    }

    /// 振りの向きを、近い方の軸に丸める。判定には使わず、頭の動きの表示で光らせる矢印に使う
    private static func direction(of peak: Peak) -> SwingDirection {
        if abs(peak.yawRate) >= abs(peak.pitchRate) {
            return peak.yawRate >= 0 ? .right : .left
        }
        return peak.pitchRate >= 0 ? .up : .down
    }
}
