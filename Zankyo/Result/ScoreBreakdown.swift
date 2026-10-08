import Foundation

/// 1 回のプレイの点の内訳。切ったノーツの「振りの強さ」と「タイミング」の平均と、どちらにずれたかを数え、
/// 次にどこを直すと点が伸びるかを決める
nonisolated struct ScoreBreakdown: Sendable, Hashable {
    /// 点を伸ばすために、次に気をつけるとよいこと
    nonisolated enum Advice: Sendable, Hashable {
        /// ミス・向き違いが多い。倍率が下がるので、まず切り逃さない
        case avoidMisses
        /// 振りが遅い。もっと速く振る
        case swingFaster
        /// 早く振りがち。少し待つ
        case waitLonger
        /// 遅く振りがち。少し早めに振る
        case swingSooner
        /// ずれが早い・遅いの両方にある。線に重なる瞬間を狙う
        case aimForLine
        /// どちらもほぼ満点。コンボを切らずに倍率を保つ
        case keepCombo
    }

    /// ミス・向き違いの割合がこれ以上なら、まず切り逃さないよう勧める
    static let missRatioForAdvice = 0.1
    /// 平均がこの割合以上なら、ほぼ満点とみなす
    static let nearlyFullRatio = 0.9

    let hitCount: Int
    let missCount: Int
    let badCutCount: Int
    /// 切ったノーツの振りの強さの点の平均（0〜`CutScore.maxSwing`）
    let averageSwing: Double
    /// 切ったノーツのタイミングの点の平均（0〜`CutScore.maxAccuracy`）
    let averageAccuracy: Double
    let perfectCount: Int
    let earlyCount: Int
    let lateCount: Int

    init(judgements: [Judgement], rules: ScoringRules) {
        var swingTotal = 0
        var accuracyTotal = 0
        var hits = 0, misses = 0, badCuts = 0, perfect = 0, early = 0, late = 0
        for judgement in judgements {
            switch judgement {
            case .hit(_, let score, let timingError):
                hits += 1
                swingTotal += score.swing
                accuracyTotal += score.accuracy
                switch HitTiming(timingError: timingError, rules: rules) {
                case .perfect: perfect += 1
                case .early: early += 1
                case .late: late += 1
                }
            case .badCut:
                badCuts += 1
            case .miss:
                misses += 1
            }
        }
        hitCount = hits
        missCount = misses
        badCutCount = badCuts
        averageSwing = hits > 0 ? Double(swingTotal) / Double(hits) : 0
        averageAccuracy = hits > 0 ? Double(accuracyTotal) / Double(hits) : 0
        perfectCount = perfect
        earlyCount = early
        lateCount = late
    }

    /// 次に気をつけるとよいこと。1 つも判定が無ければ nil
    var advice: Advice? {
        let total = hitCount + missCount + badCutCount
        guard total > 0 else { return nil }
        if hitCount == 0 || Double(missCount + badCutCount) / Double(total) >= Self.missRatioForAdvice {
            return .avoidMisses
        }
        // 取り逃した点の多いほうを先に直す
        let swingLoss = Double(CutScore.maxSwing) - averageSwing
        let accuracyLoss = Double(CutScore.maxAccuracy) - averageAccuracy
        let swingIsNearlyFull = averageSwing >= Double(CutScore.maxSwing) * Self.nearlyFullRatio
        let accuracyIsNearlyFull = averageAccuracy >= Double(CutScore.maxAccuracy) * Self.nearlyFullRatio
        if swingIsNearlyFull, accuracyIsNearlyFull {
            return .keepCombo
        }
        if swingLoss >= accuracyLoss, !swingIsNearlyFull {
            return .swingFaster
        }
        // 早い・遅いの片方に 2 倍以上偏っていれば、その向きを直す
        if earlyCount >= max(lateCount * 2, 1) {
            return .waitLonger
        }
        if lateCount >= max(earlyCount * 2, 1) {
            return .swingSooner
        }
        return .aimForLine
    }
}

nonisolated extension Judge {
    /// 今までの判定の点の内訳
    var breakdown: ScoreBreakdown {
        ScoreBreakdown(judgements: judgements, rules: rules)
    }
}

extension ScoreBreakdown.Advice {
    /// 画面に出す説明
    var message: String {
        switch self {
        case .avoidMisses:
            "ミスすると倍率が 1 段下がります。まずは切り逃さないことを優先すると点が伸びます。"
        case .swingFaster:
            "振りの強さで点を落としています。大きくゆっくりより、短く素早く首を振ると満点に近づきます。"
        case .waitLonger:
            "早めに振りがちです。ノーツが線に重なるまで、もう少し待ってから振りましょう。"
        case .swingSooner:
            "遅めに振りがちです。ノーツが線に重なる少し前から振り始めましょう。ずれが続くときはキャリブレーションで測り直してください。"
        case .aimForLine:
            "タイミングが早い・遅いの両方にずれています。ノーツが線に重なる瞬間を狙いましょう。"
        case .keepCombo:
            "振りの強さもタイミングもほぼ満点です。コンボを切らずに ×\(ScoreKeeper.maxMultiplier) を保てば、さらに伸びます。"
        }
    }
}
