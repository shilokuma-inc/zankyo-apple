import Foundation

/// 1 ノーツの点数（最大 115 点）。Beat Saber の内訳（振り始め 70・振り抜き 30・中心からの近さ 15）を、
/// 頭の振りの大きさ（角速度のピーク）とタイミングのずれに置き換える（Discussion #3 Q6）
nonisolated struct CutScore: Sendable, Hashable {
    static let maxSwing = 100
    static let maxAccuracy = 15
    static let maxTotal = maxSwing + maxAccuracy

    /// 振りの大きさの点（0〜100。Beat Saber の振り始め 70 + 振り抜き 30 に当たる）
    let swing: Int
    /// タイミングの点（0〜15。Beat Saber の中心からの近さに当たる）
    let accuracy: Int

    var total: Int { swing + accuracy }

    /// - Parameters:
    ///   - peakRate: 振りの角速度のピーク（ラジアン毎秒）
    ///   - timingError: ノーツの時刻からのずれ（秒。符号は問わない）
    init(peakRate: Double, timingError: TimeInterval, rules: ScoringRules) {
        let swingRatio = peakRate.isFinite ? min(max(peakRate / rules.fullSwingRate, 0), 1) : 0
        swing = Int((Double(Self.maxSwing) * swingRatio).rounded())
        let timingRatio = timingError.isFinite ? 1 - min(abs(timingError) / rules.hitWindow, 1) : 0
        accuracy = Int((Double(Self.maxAccuracy) * timingRatio).rounded())
    }
}

/// 判定とスコアの係数。実機で調整する前提の既定値（判断ログ #8）
nonisolated struct ScoringRules: Sendable, Hashable {
    /// ノーツの時刻の前後この秒の中の振りを、そのノーツへの振りとみなす
    var hitWindow: TimeInterval = 0.15
    /// ずれがこの秒以内の振りを「ぴったり」と表示する（時間窓の内側 1/3。イヤホンのセンサーの更新間隔より広くとる）
    var perfectWindow: TimeInterval = 0.05
    /// 振りの点が満点になる角速度（ラジアン毎秒）
    var fullSwingRate: Double = 4.0
    /// 空振りでコンボを切る遊び方（ヘドバン）で、振った後この秒の中の逆向きの振り（首を戻す動き）は 1 回だけ空振りにしない。
    /// ヘドバンは振り下ろしと戻しで 1 拍に 2 回振りが出るので、戻すたびにコンボが切れないようにする
    var returnSwingWindow: TimeInterval = 0.8
}

/// 切ったタイミングの早い・遅い。判定の表示で、ぴったりのタイミングからどちらにずれたかを伝える
nonisolated enum HitTiming: Sendable, Hashable {
    case early
    case perfect
    case late

    /// - Parameter timingError: ノーツの時刻からのずれ（秒。負なら早い）
    init(timingError: TimeInterval, rules: ScoringRules) {
        if abs(timingError) <= rules.perfectWindow {
            self = .perfect
        } else if timingError < 0 {
            self = .early
        } else {
            self = .late
        }
    }
}

/// コンボと倍率を数え、点数を積む。倍率は Beat Saber と同じく 1・2・4・8 倍で、
/// 2・4・8 回続けて切ると次の段に上がり、ミスで 1 段下がって数え直す
nonisolated struct ScoreKeeper: Sendable, Hashable {
    /// 各段から次の段に上がるのに要る、続けて切った数
    static let multiplierSteps = [1: 2, 2: 4, 4: 8]
    /// 最大の倍率
    static var maxMultiplier: Int {
        (multiplierSteps.keys.max() ?? 1) * 2
    }

    private(set) var score = 0
    private(set) var combo = 0
    private(set) var maxCombo = 0
    private(set) var multiplier = 1
    /// 今の段で続けて切った数
    private(set) var multiplierProgress = 0
    private(set) var hitCount = 0
    private(set) var missCount = 0

    /// 次の倍率までの進み具合（0〜1）。最大の倍率では 1
    var progressToNextMultiplier: Double {
        guard let step = Self.multiplierSteps[multiplier], step > 0 else { return 1 }
        return Double(multiplierProgress) / Double(step)
    }

    mutating func recordHit(_ cut: CutScore) {
        score += cut.total * multiplier
        hitCount += 1
        combo += 1
        maxCombo = max(maxCombo, combo)
        guard let step = Self.multiplierSteps[multiplier] else { return }
        multiplierProgress += 1
        if multiplierProgress >= step {
            multiplier *= 2
            multiplierProgress = 0
        }
    }

    mutating func recordMiss() {
        missCount += 1
        breakCombo()
    }

    /// コンボを切り、倍率を 1 段下げる。ミスのほか、ヘドバンの空振り（ノーツの無いところで振った）でも切る。空振りはミスに数えない
    mutating func breakCombo() {
        combo = 0
        multiplier = max(multiplier / 2, 1)
        multiplierProgress = 0
    }

    /// すべてのノーツを満点で切ったときの点数（達成率の分母）
    static func maxScore(noteCount: Int) -> Int {
        var keeper = ScoreKeeper()
        let perfect = CutScore(peakRate: .greatestFiniteMagnitude, timingError: 0, rules: ScoringRules())
        for _ in 0..<max(noteCount, 0) {
            keeper.recordHit(perfect)
        }
        return keeper.score
    }
}
