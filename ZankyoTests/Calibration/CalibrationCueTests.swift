import Foundation
import Testing
@testable import Zankyo

struct CalibrationCueTests {
    /// 0.6 秒おきのクリック 20 回（最初の 4 回は前打ち）
    private static let cue = CalibrationCue(clickTimes: (0..<20).map { 1 + Double($0) * 0.6 })

    @Test
    func countsPassedClicks() {
        #expect(Self.cue.passedCount(at: 0.9) == 0)
        // 聞こえた瞬間に鳴ったものとして数える
        #expect(Self.cue.passedCount(at: 1) == 1)
        #expect(Self.cue.passedCount(at: 2.5) == 3)
        #expect(Self.cue.passedCount(at: 100) == 20)
    }

    @Test
    func measuresTimeSinceLastClick() throws {
        #expect(Self.cue.timeSinceLastClick(at: 0.5) == nil)

        let since = try #require(Self.cue.timeSinceLastClick(at: 1.7))
        #expect(abs(since - 0.1) < 1e-9)
    }

    @Test
    func listsApproachingClicks() {
        // 1.6 秒（0.05 秒前）に鳴ったものと、2.2・2.8 秒に鳴るもの。1.0 秒と 3.4 秒は範囲の外
        let clicks = Self.cue.approachingClicks(at: 1.65, lookahead: 1.2, lookbehind: 0.1)

        #expect(clicks.map(\.index) == [1, 2, 3])
        let expected = [-0.05, 0.55, 1.15]
        #expect(zip(clicks.map(\.remaining), expected).allSatisfy { abs($0 - $1) < 1e-9 })
    }

    @Test
    func separatesCountInFromSwings() {
        #expect(Self.cue.isCountIn(3))
        #expect(!Self.cue.isCountIn(4))
        #expect(Self.cue.swingCount == 16)
        #expect(CalibrationCue(clickTimes: [1, 2]).swingCount == 0)
    }

    @Test
    func marksCaughtBeatsLikeAnalyzer() {
        let clicks = Self.cue.clickTimes
        let cuts = [
            // 前打ちへの振りは数えない
            clicks[0] + 0.05,
            clicks[4] - 0.08,
            // 1 回の振りは 1 拍だけに数える（近い方が 6 拍目に使われ、もう一方は 7 拍目から遠い）
            clicks[6] + 0.02,
            clicks[6] + 0.05,
            // 最後のクリックから離れた振り
            clicks[19] + 0.4
        ]

        #expect(Self.cue.caughtBeats(cutTimes: cuts) == [4, 6])
    }
}
