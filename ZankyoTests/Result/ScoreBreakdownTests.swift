import Foundation
import Testing
@testable import Zankyo

struct ScoreBreakdownTests {
    private static let rules = ScoringRules()
    private static let note = FaceNote(beat: 0, time: 1, direction: .left)

    /// `swing` は振りの強さの割合（0〜1）、`timingError` はずれの秒
    private static func hit(swing: Double, timingError: TimeInterval) -> Judgement {
        let score = CutScore(peakRate: rules.fullSwingRate * swing, timingError: timingError, rules: rules)
        return .hit(note, score, timingError: timingError)
    }

    @Test
    func averagesSwingAndTimingOfHits() {
        let breakdown = ScoreBreakdown(
            judgements: [
                Self.hit(swing: 1, timingError: 0),
                Self.hit(swing: 0.5, timingError: -0.1),
                Self.hit(swing: 0.5, timingError: 0.1),
                .miss(Self.note)
            ],
            rules: Self.rules
        )

        #expect(breakdown.hitCount == 3)
        #expect(breakdown.missCount == 1)
        #expect(breakdown.averageSwing == (100 + 50 + 50) / 3.0)
        #expect(breakdown.averageAccuracy == (15 + 5 + 5) / 3.0)
        #expect(breakdown.perfectCount == 1)
        #expect(breakdown.earlyCount == 1)
        #expect(breakdown.lateCount == 1)
    }

    @Test
    func advisesAvoidingMissesFirst() {
        let judgements = Array(repeating: Self.hit(swing: 1, timingError: 0), count: 8) + [.miss(Self.note), .badCut(Self.note, .up)]

        #expect(ScoreBreakdown(judgements: judgements, rules: Self.rules).advice == .avoidMisses)
    }

    @Test
    func advisesFasterSwingWhenSwingLosesMorePoints() {
        // 振りで 40 点、タイミングで 0 点を落としている
        let judgements = Array(repeating: Self.hit(swing: 0.6, timingError: 0), count: 10)

        #expect(ScoreBreakdown(judgements: judgements, rules: Self.rules).advice == .swingFaster)
    }

    @Test
    func advisesTimingDirection() {
        let early = Array(repeating: Self.hit(swing: 1, timingError: -0.12), count: 10)
        let late = Array(repeating: Self.hit(swing: 1, timingError: 0.12), count: 10)
        let both = Array(repeating: Self.hit(swing: 1, timingError: -0.12), count: 5)
            + Array(repeating: Self.hit(swing: 1, timingError: 0.12), count: 5)

        #expect(ScoreBreakdown(judgements: early, rules: Self.rules).advice == .waitLonger)
        #expect(ScoreBreakdown(judgements: late, rules: Self.rules).advice == .swingSooner)
        #expect(ScoreBreakdown(judgements: both, rules: Self.rules).advice == .aimForLine)
    }

    @Test
    func advisesKeepingComboWhenNearlyPerfect() {
        let judgements = Array(repeating: Self.hit(swing: 1, timingError: 0.01), count: 10)

        #expect(ScoreBreakdown(judgements: judgements, rules: Self.rules).advice == .keepCombo)
    }

    @Test
    func hasNoAdviceWithoutJudgements() {
        #expect(ScoreBreakdown(judgements: [], rules: Self.rules).advice == nil)
    }
}

struct ScoringGuideTests {
    @Test
    func rankThresholdsMatchRankBoundaries() {
        // ランクの下限ちょうどでそのランクになり、少し下回ると下のランクになる
        for (index, rank) in Rank.allCases.enumerated() where rank != .rankE {
            #expect(Rank(accuracy: rank.minimumAccuracy) == rank)
            #expect(Rank(accuracy: rank.minimumAccuracy - 0.001) == Rank.allCases[index + 1])
        }
    }

    @Test
    func multiplierStepsDoubleUpToMax() {
        let steps = ScoringGuideView.multiplierSteps
        #expect(steps.map(\.from) == [1, 2, 4])
        #expect(steps.map(\.count) == [2, 4, 8])
        #expect(steps.last?.to == ScoreKeeper.maxMultiplier)
        #expect(ScoreKeeper.maxMultiplier == 8)
    }

    @Test
    func examplesUseRealScoring() {
        let examples = ScoringGuideView.examples
        #expect(examples.first?.score.total == CutScore.maxTotal)
        // 振りが遅いほど、タイミングより大きく点が下がる
        #expect(examples.map(\.score.total) == examples.map(\.score.total).sorted(by: >))
    }
}
