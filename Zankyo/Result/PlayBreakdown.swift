import Foundation

/// 1 回のプレイの判定の内訳。結果画面で見せる（ハイスコアには残さない）
nonisolated struct PlayBreakdown: Sendable, Hashable {
    /// ずれが `ScoringRules.perfectWindow` 以内で切った
    var perfect = 0
    /// 早めに切った
    var early = 0
    /// 遅めに切った
    var late = 0
    /// 向き違い
    var badCut = 0
    var miss = 0
    /// コンボを切った空振り（ヘドバン）。ノーツの数には入らない
    var emptySwing = 0
    /// 切ったノーツのずれの平均（秒。負なら早め）。切ったノーツが無ければ nil
    var meanTimingError: TimeInterval?

    var hit: Int { perfect + early + late }
    var noteCount: Int { hit + badCut + miss }

    /// 切ったタイミングの傾向。切ったノーツが無ければ nil
    var tendency: TimingTendency? {
        meanTimingError.map(TimingTendency.init(meanTimingError:))
    }
}

/// 切ったタイミングの、平均での傾向
nonisolated enum TimingTendency: Sendable, Hashable {
    case early
    case onTime
    case late

    /// 平均のずれがこの秒以内なら、ちょうどとみなす
    static let tolerance: TimeInterval = 0.02
    /// 平均のずれがこの秒を超えたら、キャリブレーションを勧める
    static let calibrationHintThreshold: TimeInterval = 0.04

    init(meanTimingError: TimeInterval) {
        if abs(meanTimingError) <= Self.tolerance {
            self = .onTime
        } else {
            self = meanTimingError < 0 ? .early : .late
        }
    }
}

nonisolated extension Judge {
    /// 今までの判定の内訳（終えた後に呼ぶ）
    func playBreakdown() -> PlayBreakdown {
        var breakdown = PlayBreakdown(emptySwing: emptySwingCount)
        var totalTimingError: TimeInterval = 0
        for judgement in judgements {
            switch judgement {
            case .hit(_, _, let timingError):
                totalTimingError += timingError
                switch HitTiming(timingError: timingError, rules: rules) {
                case .perfect: breakdown.perfect += 1
                case .early: breakdown.early += 1
                case .late: breakdown.late += 1
                }
            case .badCut:
                breakdown.badCut += 1
            case .miss:
                breakdown.miss += 1
            }
        }
        if breakdown.hit > 0 {
            breakdown.meanTimingError = totalTimingError / Double(breakdown.hit)
        }
        return breakdown
    }
}
