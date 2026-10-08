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
    /// 振りの向きを上下左右に丸めたもの
    let direction: SwingDirection
    /// ピークの角速度（ラジアン毎秒。スコアの振りの大きさに使う）
    let peakRate: Double
    /// ピークの角速度の左右・上下の成分（ラジアン毎秒）。丸める前の振りの向きで、首を戻す動きの見分けに使う
    let yawRate: Double
    let pitchRate: Double

    /// - Parameters:
    ///   - yawRate: ピークの左右の成分。省くと、`direction` の向きに `peakRate` の速さで振ったとみなす
    ///   - pitchRate: ピークの上下の成分。省き方は `yawRate` と同じ
    init(timestamp: TimeInterval, direction: SwingDirection, peakRate: Double, yawRate: Double? = nil, pitchRate: Double? = nil) {
        self.timestamp = timestamp
        self.direction = direction
        self.peakRate = peakRate
        let axis: (yaw: Double, pitch: Double) = switch direction {
        case .right: (1, 0)
        case .left: (-1, 0)
        case .up: (0, 1)
        case .down: (0, -1)
        }
        self.yawRate = yawRate ?? axis.yaw * peakRate
        self.pitchRate = pitchRate ?? axis.pitch * peakRate
    }

    /// `other` とおおむね逆向き（向きの差が 90 度より大きい）の振り。上下左右に丸める前の向きで比べるので、斜めの振りも見分けられる
    func isOpposite(to other: CutEvent) -> Bool {
        yawRate * other.yawRate + pitchRate * other.pitchRate < 0
    }
}

/// 角速度のピークから「切る」動きを検出する。遊び方が向きを合わせて切る（`PlayStyle.directional`）ときに使う。
/// 加速度は使わない（電車の揺れは直線加速度に乗るため）
///
/// 閾値に対する割合の大きい方の軸（yaw / pitch）が、その軸の閾値を超えてから `releaseRatio` を下回るまでを 1 回の振りとみなし、
/// その間のピークの時刻・向きで 1 つの `CutEvent` を出す。振った後に首を戻す動きは逆向きのピークになるので、
/// `returnWindow` の間は直前と逆向きの振りを出さない
nonisolated struct CutDetector: SwingDetector {
    nonisolated struct Configuration: Sendable, Hashable {
        /// 左右（yaw）の振りとみなす角速度（ラジアン毎秒）
        var yawThreshold: Double = 2.0
        /// 上下（pitch・うなずき）の振りとみなす角速度（ラジアン毎秒）。うなずきは首を左右に振るより速く動かしにくいので低くし、
        /// 利用者が変えられるようにしている（`SwingSensitivityStore`）
        var pitchThreshold: Double = 1.5
        /// ピークに対してこの割合まで下がったら、振りが終わったとみなす
        var releaseRatio: Double = 0.5
        /// 振りを出した後、向きを問わず次の振りを出さない時間（秒）
        var refractory: TimeInterval = 0.12
        /// 振りを出した後、逆向きの振り（首を戻す動き）を出さない時間（秒）
        var returnWindow: TimeInterval = 0.35

        /// 向きの軸の閾値
        func threshold(for direction: SwingDirection) -> Double {
            switch direction {
            case .left, .right: yawThreshold
            case .up, .down: pitchThreshold
            }
        }
    }

    private struct Peak {
        var timestamp: TimeInterval
        var direction: SwingDirection
        var rate: Double
    }

    let configuration: Configuration
    private var peak: Peak?
    private var lastCut: CutEvent?
    /// 直前の振りを終えたときに、閾値を超えていた向き。それぞれ閾値をいったん下回るまで、その向きの振りを始めない
    private var settling: Set<SwingDirection> = []

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// サンプルを 1 つ受け取り、振りが終わったときだけ `CutEvent` を返す
    mutating func process(_ sample: MotionSample) -> CutEvent? {
        guard sample.yawRate.isFinite, sample.pitchRate.isFinite, sample.timestamp.isFinite else { return nil }
        let (direction, rate) = dominant(sample)
        let threshold = configuration.threshold(for: direction)

        var cut: CutEvent?
        if var current = peak {
            // 振りの軸の角速度で追う。別の軸が強くなっただけでは終えない（弧を描く 1 回の振りを、上下と左右の 2 回に数えない）
            let currentRate = Self.rate(toward: current.direction, in: sample)
            if currentRate > current.rate {
                current = Peak(timestamp: sample.timestamp, direction: current.direction, rate: currentRate)
            }
            let isReleased = currentRate < current.rate * configuration.releaseRatio
            guard isReleased else {
                peak = current
                return nil
            }
            peak = nil
            // このとき閾値を超えている向きは、いったん閾値を下回るまで振りにしない（すぐ下で絞る）。
            // 強い振りの減っていく途中で同じ向きをもう一度数えず、弧を描く振りの後半（別の軸がまだ強い）も別の振りにしない
            settling = Set(SwingDirection.allCases)
            cut = emit(current)
        }
        settling = settling.filter { Self.rate(toward: $0, in: sample) >= configuration.threshold(for: $0) }
        if peak == nil, !settling.contains(direction), rate >= threshold {
            peak = Peak(timestamp: sample.timestamp, direction: direction, rate: rate)
        }
        return cut
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

    /// その向きへの角速度。逆向きに動いているときは負
    private static func rate(toward direction: SwingDirection, in sample: MotionSample) -> Double {
        switch direction {
        case .right: sample.yawRate
        case .left: -sample.yawRate
        case .up: sample.pitchRate
        case .down: -sample.pitchRate
        }
    }

    /// 閾値に対する割合の大きい方の軸と、その向き・角速度。斜めの振りは近い方の軸に丸める
    ///
    /// 角速度そのもので比べると、閾値の低い上下の振りが、左右の小さな揺れに負けて振りにならないことがある
    private func dominant(_ sample: MotionSample) -> (SwingDirection, Double) {
        let yaw = abs(sample.yawRate)
        let pitch = abs(sample.pitchRate)
        // yaw / yawThreshold >= pitch / pitchThreshold を、割り算を使わずに比べる（閾値が 0 でも NaN にしない）
        if yaw * configuration.pitchThreshold >= pitch * configuration.yawThreshold {
            return (sample.yawRate >= 0 ? .right : .left, yaw)
        }
        return (sample.pitchRate >= 0 ? .up : .down, pitch)
    }
}
