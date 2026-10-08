import AVFoundation
import Foundation
import Testing
@testable import Zankyo

struct ScoreBreakdownTimingTests {
    @Test
    func countsJudgementsByTiming() {
        let notes = (0..<6).map { FaceNote(beat: Double($0), time: 1 + Double($0), direction: .left) }
        var judge = Judge(notes: notes)
        // ぴったり（+0.02）・早い（-0.08）・遅い（+0.1）・ぴったり（-0.04）・向き違い・ミス
        judge.cut(Self.cut(.left), at: 1.02)
        judge.cut(Self.cut(.left), at: 1.92)
        judge.cut(Self.cut(.left), at: 3.1)
        judge.cut(Self.cut(.left), at: 3.96)
        judge.cut(Self.cut(.right), at: 5)
        judge.advance(to: 10)

        let breakdown = judge.breakdown

        #expect(breakdown.perfectCount == 2)
        #expect(breakdown.earlyCount == 1)
        #expect(breakdown.lateCount == 1)
        #expect(breakdown.badCutCount == 1)
        #expect(breakdown.missCount == 1)
        #expect(breakdown.hitCount == 4)
        #expect(breakdown.noteCount == 6)
        // 切った 4 つのずれの平均（向き違いとミスは入れない）
        #expect(abs(breakdown.meanTimingError ?? 1) < 0.000_001)
        #expect(breakdown.tendency == .onTime)
    }

    @Test
    func countsEmptySwingsWithoutNotes() {
        // ヘドバンの空振りはノーツの数に入れず、別に数える
        let notes = [FaceNote(beat: 2, time: 1, direction: nil), FaceNote(beat: 4, time: 2, direction: nil)]
        var judge = Judge(notes: notes, breaksComboOnEmptySwing: true)
        judge.cut(Self.cut(.down), at: 1)
        judge.cut(Self.cut(.right), at: 1.5)
        judge.cut(Self.cut(.down), at: 2.1)

        let breakdown = judge.breakdown

        #expect(breakdown.emptySwingCount == 1)
        #expect(breakdown.noteCount == 2)
        #expect(breakdown.lateCount == 1)
        #expect(breakdown.tendency == .late)
    }

    @Test
    func hasNoTendencyWithoutHits() {
        var judge = Judge(notes: [FaceNote(beat: 2, time: 1, direction: .up)])
        judge.advance(to: 5)

        let breakdown = judge.breakdown

        #expect(breakdown.missCount == 1)
        #expect(breakdown.meanTimingError == nil)
        #expect(breakdown.tendency == nil)
    }

    @Test(arguments: [(-0.05, TimingTendency.early), (-0.02, .onTime), (0, .onTime), (0.02, .onTime), (0.021, .late)])
    func tendencyHasTolerance(meanTimingError: TimeInterval, expected: TimingTendency) {
        #expect(TimingTendency(meanTimingError: meanTimingError) == expected)
    }

    private static func cut(_ direction: SwingDirection) -> CutEvent {
        CutEvent(timestamp: 0, direction: direction, peakRate: 4)
    }
}

struct FinishJingleTests {
    @Test
    func rendersQuietStartAndEnd() {
        let sampleRate = 44_100.0
        let samples = FinishJingle.samples(sampleRate: sampleRate)

        #expect(samples.count == Int(FinishJingle.duration * sampleRate))
        let loudest = samples.reduce(0) { max($0, abs($1)) }
        #expect(abs(loudest - FinishJingle.peak) < 0.001)
        // 鳴らし始めと終わりで音が跳ねない
        #expect(abs(samples[0]) < 0.01)
        #expect(abs(samples[samples.count - 1]) < 0.01)
        // 余韻の途中まで音がある
        let tail = samples[Int(1.5 * sampleRate)..<Int(1.6 * sampleRate)]
        #expect(tail.contains { abs($0) > 0.01 })
    }

    @Test
    func fillsEveryChannelOfSongFormat() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))

        let buffer = try #require(FinishJingle.buffer(format: format))

        #expect(buffer.frameLength == AVAudioFrameCount(FinishJingle.duration * 48_000))
        let channels = try #require(buffer.floatChannelData)
        let middle = Int(buffer.frameLength) / 4
        #expect(channels[0][middle] == channels[1][middle])
    }
}

struct GameSessionFinishSoundTests {
    @Test
    func playsFinishSoundOnceWhenSongEnds() async {
        let sound = RecordingFinishSound()
        let session = GameSession(
            notes: [FaceNote(beat: 2, time: 1, direction: nil)],
            clock: SilentSongClock(duration: 3),
            input: RecordedMotionInput(samples: []),
            finishSound: sound
        )

        await session.play()
        #expect(sound.plays == 0)
        session.finish()
        session.finish()

        #expect(sound.plays == 1)
        #expect(session.judge.breakdown.missCount == 1)

        session.stopFinishSound()
        #expect(sound.stops == 1)
    }

    @Test
    func doesNotPlayFinishSoundWhenSongCannotStart() async {
        let sound = RecordingFinishSound()
        let session = GameSession(
            notes: [FaceNote(beat: 2, time: 1, direction: nil)],
            clock: FailingSongClock(),
            input: RecordedMotionInput(samples: []),
            finishSound: sound
        )

        await session.play()

        #expect(session.phase == .finished)
        #expect(session.result == nil)
        #expect(sound.plays == 0)
    }
}

private final class RecordingFinishSound: FinishSounding {
    private(set) var plays = 0
    private(set) var stops = 0

    func play() {
        plays += 1
    }

    func stop() {
        stops += 1
    }
}

/// 鳴らせない時計（出力の機器が無いときなど）
private final class FailingSongClock: SongClock {
    struct Failure: Error {}

    let duration: TimeInterval = 3
    let currentTime: TimeInterval = 0
    let isPlaying = false

    func play() throws {
        throw Failure()
    }

    func pause() {}

    func stop() {}

    func songTime(atUptime uptime: TimeInterval) -> TimeInterval? {
        nil
    }
}
