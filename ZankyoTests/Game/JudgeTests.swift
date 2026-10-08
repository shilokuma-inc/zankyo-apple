import Foundation
import Testing
@testable import Zankyo

struct CutScoreTests {
    private let rules = ScoringRules()

    @Test
    func perfectCutScores115() {
        let score = CutScore(peakRate: 4, timingError: 0, rules: rules)

        #expect(score == CutScore(peakRate: 10, timingError: 0, rules: rules))
        #expect(score.swing == 100)
        #expect(score.accuracy == 15)
        #expect(score.total == CutScore.maxTotal)
    }

    @Test
    func weakSwingAndLateTimingLosePoints() {
        // 満点の半分の角速度で 100 点の半分、時間窓の 2/3 のずれで 15 点の 1/3
        let score = CutScore(peakRate: 2, timingError: -0.1, rules: rules)

        #expect(score.swing == 50)
        #expect(score.accuracy == 5)
    }

    @Test
    func invalidValuesScoreZero() {
        let score = CutScore(peakRate: .nan, timingError: .infinity, rules: rules)

        #expect(score.total == 0)
    }
}

struct HitTimingTests {
    @Test(arguments: zip(
        [-0.1, -0.05, 0, 0.05, 0.08] as [TimeInterval],
        [HitTiming.early, .perfect, .perfect, .perfect, .late]
    ))
    func classifiesTimingErrorAroundPerfectWindow(timingError: TimeInterval, expected: HitTiming) {
        // ぴったりは前後 0.05 秒。負のずれは早い
        #expect(HitTiming(timingError: timingError, rules: ScoringRules()) == expected)
    }
}

struct ScoreKeeperTests {
    private static let perfect = CutScore(peakRate: 4, timingError: 0, rules: ScoringRules())

    @Test
    func multiplierClimbsLikeBeatSaber() {
        var keeper = ScoreKeeper()
        var multipliers: [Int] = []
        for _ in 0..<15 {
            keeper.recordHit(Self.perfect)
            multipliers.append(keeper.multiplier)
        }

        // 2 回で 2 倍、さらに 4 回で 4 倍、さらに 8 回で 8 倍
        #expect(multipliers == [1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 4, 4, 4, 8, 8])
        #expect(keeper.combo == 15)
        #expect(keeper.maxCombo == 15)
    }

    @Test
    func missDropsOneStepAndResetsCombo() {
        var keeper = ScoreKeeper()
        for _ in 0..<14 {
            keeper.recordHit(Self.perfect)
        }
        #expect(keeper.multiplier == 8)

        keeper.recordMiss()
        #expect(keeper.multiplier == 4)
        #expect(keeper.multiplierProgress == 0)
        #expect(keeper.combo == 0)
        #expect(keeper.maxCombo == 14)
        #expect(keeper.missCount == 1)

        keeper.recordMiss()
        keeper.recordMiss()
        keeper.recordMiss()
        #expect(keeper.multiplier == 1)
    }

    @Test
    func scoreUsesMultiplierAtHitTime() {
        var keeper = ScoreKeeper()
        keeper.recordHit(Self.perfect)
        keeper.recordHit(Self.perfect)
        keeper.recordHit(Self.perfect)

        // 115 × 1 + 115 × 1 + 115 × 2
        #expect(keeper.score == 460)
    }

    @Test
    func progressToNextMultiplierFillsRing() {
        var keeper = ScoreKeeper()
        var progress = [keeper.progressToNextMultiplier]
        for _ in 0..<15 {
            keeper.recordHit(Self.perfect)
            progress.append(keeper.progressToNextMultiplier)
        }

        // 1 倍は 2 回、2 倍は 4 回、4 倍は 8 回で埋まり、8 倍では埋まったまま
        #expect(progress[0...2] == [0, 0.5, 0])
        #expect(progress[2...6] == [0, 0.25, 0.5, 0.75, 0])
        #expect(progress[14...15] == [1, 1])

        keeper.recordMiss()
        #expect(keeper.progressToNextMultiplier == 0)
    }

    @Test(arguments: [(0, 0), (1, 115), (2, 230), (3, 460)])
    func maxScore(noteCount: Int, expected: Int) {
        #expect(ScoreKeeper.maxScore(noteCount: noteCount) == expected)
    }
}

struct JudgeTests {
    private static let notes = [
        FaceNote(beat: 2, time: 1, direction: .left),
        FaceNote(beat: 4, time: 2, direction: nil),
        FaceNote(beat: 6, time: 3, direction: .up)
    ]

    @Test
    func hitsNoteInWindowWithMatchingDirection() throws {
        var judge = Judge(notes: Self.notes)

        let result = judge.cut(Self.cut(.left), at: 1.05)

        let judgement = try #require(result)

        guard case let .hit(note, score, timingError) = judgement else {
            Issue.record("ヒットになるはず: \(judgement)")
            return
        }
        #expect(note == Self.notes[0])
        #expect(abs(timingError - 0.05) < 1e-9)
        #expect(score.swing == 100)
        #expect(score.accuracy == 10)
        #expect(judge.keeper.combo == 1)
    }

    @Test
    func wrongDirectionIsBadCut() {
        var judge = Judge(notes: Self.notes)

        let judgement = judge.cut(Self.cut(.right), at: 1)

        #expect(judgement == .badCut(Self.notes[0], .right))
        #expect(judge.keeper.missCount == 1)
        #expect(judge.keeper.combo == 0)
    }

    @Test
    func anyDirectionAcceptsEverySwing() throws {
        var judge = Judge(notes: Self.notes)
        judge.cut(Self.cut(.left), at: 1)

        let result = judge.cut(Self.cut(.down), at: 2)

        let judgement = try #require(result)
        guard case .hit = judgement else {
            Issue.record("方向不問のノーツはどの向きでもヒットになるはず: \(judgement)")
            return
        }
    }

    @Test
    func swingWithoutNoteIsIgnored() {
        var judge = Judge(notes: Self.notes)

        let judgement = judge.cut(Self.cut(.left), at: 0.5)

        #expect(judgement == nil)
        #expect(judge.keeper.missCount == 0)
        #expect(judge.remainingNotes.count == 3)
    }

    @Test
    func passedNotesBecomeMisses() {
        var judge = Judge(notes: Self.notes)

        let early = judge.advance(to: 1.1)
        let late = judge.advance(to: 2.2)

        #expect(early.isEmpty)
        #expect(late == [.miss(Self.notes[0]), .miss(Self.notes[1])])
        #expect(judge.keeper.missCount == 2)
        #expect(!judge.isFinished)

        judge.advance(to: 10)
        #expect(judge.isFinished)
    }

    @Test
    func lateSwingMissesEarlierNoteBeforeJudgingNext() throws {
        var judge = Judge(notes: Self.notes)

        // 1 秒のノーツを切らずに 2 秒のノーツを切ると、1 秒のノーツはミスになる
        let result = judge.cut(Self.cut(.right), at: 2)
        let judgement = try #require(result)
        #expect(judgement.note == Self.notes[1])
        #expect(judge.judgements.first == .miss(Self.notes[0]))
    }

    @Test
    func appliesCalibrationOffset() throws {
        // 動きが音より 0.12 秒遅れる人は、1.12 秒の振りが 1 秒のノーツにぴったり合う
        var judge = Judge(notes: Self.notes, offset: 0.12)

        let result = judge.cut(Self.cut(.left), at: 1.12)

        let judgement = try #require(result)
        guard case let .hit(_, score, _) = judgement else {
            Issue.record("ヒットになるはず: \(judgement)")
            return
        }
        #expect(score.accuracy == 15)
    }

    @Test
    func advanceAppliesCalibrationOffset() throws {
        // 動きが 0.12 秒遅れる人の、曲の時刻 1.2 の振りは補正後 1.08 で窓の中。その手前のフレームでミスにしない
        var judge = Judge(notes: Self.notes, offset: 0.12)

        let missed = judge.advance(to: 1.16)
        let result = judge.cut(Self.cut(.left), at: 1.2)
        let judgement = try #require(result)

        #expect(missed.isEmpty)
        guard case .hit = judgement else {
            Issue.record("ヒットになるはず: \(judgement)")
            return
        }
        let late = judge.advance(to: 2.26)
        #expect(late.isEmpty)
        let passed = judge.advance(to: 2.3)
        #expect(passed == [.miss(Self.notes[1])])
    }

    @Test
    func perfectRunReachesMaxScore() {
        var judge = Judge(notes: Self.notes)
        judge.cut(Self.cut(.left), at: 1)
        judge.cut(Self.cut(.down), at: 2)
        judge.cut(Self.cut(.up), at: 3)

        #expect(judge.isFinished)
        #expect(judge.keeper.score == judge.maxScore)
    }

    private static func cut(_ direction: SwingDirection, peakRate: Double = 4) -> CutEvent {
        CutEvent(timestamp: 0, direction: direction, peakRate: peakRate)
    }
}
