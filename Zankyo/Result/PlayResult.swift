import Foundation

/// 1 回のプレイの結果
nonisolated struct PlayResult: Sendable, Hashable, Codable {
    let score: Int
    /// すべて満点で切ったときの点数
    let maxScore: Int
    let maxCombo: Int
    let hitCount: Int
    let missCount: Int
    let noteCount: Int
    let playedAt: Date
    /// スコアの計算方法のバージョン（`ScoringRules.version`）。違うバージョンの点数は比べない
    let scoringVersion: Int

    /// 達成率（0〜1）
    var accuracy: Double {
        maxScore > 0 ? min(max(Double(score) / Double(maxScore), 0), 1) : 0
    }

    var rank: Rank { Rank(accuracy: accuracy) }

    /// 1 つもミスせずに終えた
    var isFullCombo: Bool { noteCount > 0 && missCount == 0 }
}

/// ランク。Beat Saber と同じ達成率の区切り
nonisolated enum Rank: String, Sendable, Hashable, CaseIterable {
    case rankSS = "SS"
    case rankS = "S"
    case rankA = "A"
    case rankB = "B"
    case rankC = "C"
    case rankD = "D"
    case rankE = "E"

    init(accuracy: Double) {
        switch accuracy {
        case 0.9...: self = .rankSS
        case 0.8...: self = .rankS
        case 0.65...: self = .rankA
        case 0.5...: self = .rankB
        case 0.35...: self = .rankC
        case 0.2...: self = .rankD
        default: self = .rankE
        }
    }
}

extension ScoringRules {
    /// スコアの計算方法のバージョン。点数の内訳・倍率・時間窓など、同じ動きで点数が変わる変更をしたら上げる
    nonisolated static let version = 1
}

nonisolated extension Judge {
    /// 今までの判定から結果を作る（終えた後に呼ぶ）
    func result(playedAt: Date = Date()) -> PlayResult {
        PlayResult(
            score: keeper.score,
            maxScore: maxScore,
            maxCombo: keeper.maxCombo,
            hitCount: keeper.hitCount,
            missCount: keeper.missCount,
            noteCount: judgements.count + remainingNotes.count,
            playedAt: playedAt,
            scoringVersion: ScoringRules.version
        )
    }
}
