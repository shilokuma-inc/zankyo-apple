import Foundation

/// 頭を振る向き。ノーツの 4 方向（Discussion #3 Q4）と対応する
nonisolated enum SwingDirection: Sendable, Hashable, CaseIterable {
    case up
    case down
    case left
    case right

    var opposite: Self {
        switch self {
        case .up: .down
        case .down: .up
        case .left: .right
        case .right: .left
        }
    }
}

/// 検出した「切る」動き
nonisolated struct CutEvent: Sendable, Hashable {
    /// 角速度がピークに達した時刻（判定のタイミングに使う）
    let timestamp: TimeInterval
    let direction: SwingDirection
    /// ピークの角速度（ラジアン毎秒。スコアの振りの大きさに使う）
    let peakRate: Double
}

/// 角速度のピークから「切る」動きを検出する。加速度は使わない（電車の揺れは直線加速度に乗るため）
///
/// 角速度の大きい方の軸（yaw / pitch）が `threshold` を超えてから `releaseRatio` を下回るまでを 1 回の振りとみなし、
/// その間のピークの時刻・向きで 1 つの `CutEvent` を出す。振った後に首を戻す動きは逆向きのピークになるので、
/// `returnWindow` の間は直前と逆向きの振りを出さない
nonisolated struct CutDetector: Sendable {
    nonisolated struct Configuration: Sendable, Hashable {
        /// 振りとみなす角速度（ラジアン毎秒）
        var threshold: Double = 2.0
        /// ピークに対してこの割合まで下がったら、振りが終わったとみなす
        var releaseRatio: Double = 0.5
        /// 振りを出した後、向きを問わず次の振りを出さない時間（秒）
        var refractory: TimeInterval = 0.12
        /// 振りを出した後、逆向きの振り（首を戻す動き）を出さない時間（秒）
        var returnWindow: TimeInterval = 0.35
    }

    private struct Peak {
        var timestamp: TimeInterval
        var direction: SwingDirection
        var rate: Double
    }

    let configuration: Configuration
    private var peak: Peak?
    private var lastCut: CutEvent?
    /// 直前に終えた振りの向き。角速度が閾値を下回るまで、同じ向きの振りを始めない
    private var settling: SwingDirection?

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// サンプルを 1 つ受け取り、振りが終わったときだけ `CutEvent` を返す
    mutating func process(_ sample: MotionSample) -> CutEvent? {
        guard sample.yawRate.isFinite, sample.pitchRate.isFinite, sample.timestamp.isFinite else { return nil }
        let (direction, rate) = Self.dominant(sample)

        var cut: CutEvent?
        if var current = peak {
            if direction == current.direction, rate > current.rate {
                current = Peak(timestamp: sample.timestamp, direction: direction, rate: rate)
            }
            let isReleased = direction != current.direction || rate < current.rate * configuration.releaseRatio
            guard isReleased else {
                peak = current
                return nil
            }
            peak = nil
            settling = current.direction
            cut = emit(current)
        }
        // 強い振りの減っていく途中で、同じ向きの振りをもう一度数えない。いったん閾値を下回るまで待つ
        if rate < configuration.threshold || direction != settling {
            settling = nil
        }
        if peak == nil, settling == nil, rate >= configuration.threshold {
            peak = Peak(timestamp: sample.timestamp, direction: direction, rate: rate)
        }
        return cut
    }

    /// サンプル列をまとめて処理する（録画した列の再生やテスト用）
    mutating func process(_ samples: some Sequence<MotionSample>) -> [CutEvent] {
        samples.compactMap { process($0) }
    }

    /// 不応期と首を戻す動きを除いて、振りを確定する
    private mutating func emit(_ peak: Peak) -> CutEvent? {
        if let lastCut {
            let elapsed = peak.timestamp - lastCut.timestamp
            if elapsed < configuration.refractory {
                return nil
            }
            if peak.direction == lastCut.direction.opposite, elapsed < configuration.returnWindow {
                return nil
            }
        }
        let cut = CutEvent(timestamp: peak.timestamp, direction: peak.direction, peakRate: peak.rate)
        lastCut = cut
        return cut
    }

    /// 角速度の大きい方の軸と、その向き・大きさ。斜めの振りは近い方の軸に丸める
    private static func dominant(_ sample: MotionSample) -> (SwingDirection, Double) {
        if abs(sample.yawRate) >= abs(sample.pitchRate) {
            return (sample.yawRate >= 0 ? .right : .left, abs(sample.yawRate))
        }
        return (sample.pitchRate >= 0 ? .up : .down, abs(sample.pitchRate))
    }
}
