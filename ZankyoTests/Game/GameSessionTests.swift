import Foundation
import Testing
@testable import Zankyo

struct GameSessionTests {
    private static let notes = [
        FaceNote(beat: 2, time: 1, direction: .right),
        FaceNote(beat: 4, time: 2, direction: .up),
        FaceNote(beat: 6, time: 3, direction: nil)
    ]

    @Test
    func judgesRecordedSwingsAndFinishesAtSongEnd() async {
        // モーションの時刻 = 曲の時刻（時計の起点 0）。各ノーツの時刻に向きを合わせて振る
        let input = RecordedMotionInput(samples: MotionRecording.make(swings: [
            .init(direction: .right, peakTime: 1, peakRate: 4),
            .init(direction: .up, peakTime: 2, peakRate: 4),
            .init(direction: .left, peakTime: 3, peakRate: 4)
        ]))
        let clock = ManualSongClock(duration: 4)
        let session = GameSession(notes: Self.notes, clock: clock, input: input)

        await session.play()
        #expect(session.phase == .playing)
        #expect(session.judge.keeper.hitCount == 3)
        #expect(session.score == session.judge.maxScore)

        clock.time = 3.5
        session.tick()
        #expect(session.phase == .playing)

        clock.time = 4
        session.tick()
        #expect(session.phase == .finished)
        #expect(!clock.isPlaying)
    }

    @Test
    func judgesNodsWithGivenThreshold() async {
        // 上下のノーツへの軽いうなずき（1.7 rad/s）。上下の閾値が 2.0 なら振りにならず、既定の 1.5 なら切れる
        let notes = [FaceNote(beat: 2, time: 1, direction: .up)]
        let samples = MotionRecording.make(swings: [.init(direction: .up, peakTime: 1, peakRate: 1.7)])
        let strict = GameSession(
            notes: notes,
            clock: ManualSongClock(duration: 2),
            input: RecordedMotionInput(samples: samples),
            detection: SwingDetection(style: .directional, directional: .init(pitchThreshold: 2.0))
        )
        let gentle = GameSession(
            notes: notes,
            clock: ManualSongClock(duration: 2),
            input: RecordedMotionInput(samples: samples),
            detection: SwingDetection(style: .directional)
        )

        await strict.play()
        await gentle.play()

        #expect(strict.judge.keeper.hitCount == 0)
        #expect(gentle.judge.keeper.hitCount == 1)
    }

    @Test
    func unplayedNotesBecomeMissesAtSongEnd() async {
        let clock = ManualSongClock(duration: 4)
        let session = GameSession(notes: Self.notes, clock: clock, input: RecordedMotionInput(samples: []))

        await session.play()
        clock.time = 2.5
        session.tick()
        #expect(session.judge.keeper.missCount == 2)
        // 既定のヘドバンでは、向きを外したノーツで判定する
        #expect(session.lastJudgement == .miss(FaceNote(beat: 4, time: 2, direction: nil)))

        clock.time = 4
        session.tick()
        #expect(session.phase == .finished)
        #expect(session.judge.keeper.missCount == 3)
    }

    @Test
    func ignoresSwingsWhilePaused() async {
        let clock = ManualSongClock(duration: 4)
        let session = GameSession(notes: Self.notes, clock: clock, input: RecordedMotionInput(samples: []))
        await session.play()

        session.pause()
        #expect(session.phase == .paused)
        #expect(!clock.isPlaying)
        session.handle(CutEvent(timestamp: 1, direction: .right, peakRate: 4))
        #expect(session.judge.keeper.hitCount == 0)

        session.resume()
        #expect(session.phase == .playing)
        session.handle(CutEvent(timestamp: 1, direction: .right, peakRate: 4))
        #expect(session.judge.keeper.hitCount == 1)
    }

    @Test
    func pausesWhenEarphonesDisconnect() async {
        let input = ControllableMotionInput(status: .ready)
        let clock = ManualSongClock(duration: 4)
        let session = GameSession(notes: Self.notes, clock: clock, input: input)
        session.start()
        await waitUntil { session.phase == .playing }

        session.tick()
        input.status = .disconnected
        session.tick()

        #expect(session.phase == .paused)
        #expect(session.pausedByDisconnection)
        session.resume()
        #expect(session.phase == .paused)

        input.status = .ready
        session.resume()
        #expect(session.phase == .playing)
        #expect(!session.pausedByDisconnection)
        session.finish()
    }

    @Test
    func doesNotPauseBeforeInputBecomesReady() async {
        // 許可を尋ねた直後など、接続の通知が届く前の状態では止めない
        let input = ControllableMotionInput(status: .notDetermined)
        let session = GameSession(notes: Self.notes, clock: ManualSongClock(duration: 4), input: input)
        session.start()
        await waitUntil { session.phase == .playing }

        input.status = .disconnected
        session.tick()

        #expect(session.phase == .playing)
        session.finish()
    }

    @Test
    func cannotStartWithoutMotionInput() {
        let session = GameSession(notes: Self.notes, clock: ManualSongClock(duration: 4), input: UnavailableMotionInputStub())

        #expect(!session.canStart)
    }

    @Test
    func silentClockAdvancesAndPauses() {
        var now = 100.0
        let clock = SilentSongClock(duration: 10) { now }

        clock.play()
        now = 102
        #expect(clock.currentTime == 2)
        #expect(clock.songTime(atUptime: 101.5) == 1.5)

        clock.pause()
        now = 110
        #expect(clock.currentTime == 2)
        #expect(clock.songTime(atUptime: 110) == nil)

        clock.play()
        now = 111
        #expect(clock.currentTime == 3)
        now = 200
        #expect(clock.currentTime == 10)
    }

    @Test
    func headbangIgnoresNoteDirections() async {
        // ヘドバンでは、ノーツの向きと違う向きに振っても切れる。ノーツの向きは外して判定する
        let samples = MotionRecording.make(swings: [
            .init(direction: .down, peakTime: 1, peakRate: 4),
            .init(direction: .left, peakTime: 2, peakRate: 4),
            .init(direction: .up, peakTime: 3, peakRate: 4)
        ])
        let headbang = GameSession(
            notes: Self.notes,
            clock: ManualSongClock(duration: 4),
            input: RecordedMotionInput(samples: samples),
            detection: SwingDetection(style: .headbang)
        )
        let directional = GameSession(
            notes: Self.notes,
            clock: ManualSongClock(duration: 4),
            input: RecordedMotionInput(samples: samples),
            detection: SwingDetection(style: .directional)
        )

        await headbang.play()
        await directional.play()

        #expect(headbang.judge.keeper.hitCount == 3)
        #expect(headbang.judge.remainingNotes.isEmpty)
        #expect(headbang.judge.judgements.allSatisfy { $0.note.direction == nil })
        // 向きを合わせて切る遊び方では、右と上のノーツは向き違い
        #expect(directional.judge.keeper.hitCount == 1)
        #expect(directional.judge.judgements.filter { if case .badCut = $0 { true } else { false } }.count == 2)
    }

    @Test(arguments: [true, false])
    func headbangHitsEveryBeatOfContinuousNodding(startsWithUpStroke: Bool) async {
        // 120 BPM で 1 拍に 1 回うなずき続ける。振り下ろしを拍に合わせていれば、首を戻す動きから振り始めても全部のノーツを切れる
        let period = 0.5
        let sign = startsWithUpStroke ? 1.0 : -1.0
        let samples = (0...Int(5 * 50)).map { index in
            let time = Double(index) / 50
            return MotionSample(timestamp: time, yawRate: 0, pitchRate: time <= 4 ? sign * 4 * sin(2 * .pi * time / period) : 0)
        }
        // 振り下ろしの速さのピーク（上下の角速度が負の山）の時刻にノーツを置く
        let firstDownPeak = startsWithUpStroke ? 0.375 : 0.125
        let notes = (0..<8).map { FaceNote(beat: Double($0), time: firstDownPeak + Double($0) * period, direction: .left) }
        let session = GameSession(
            notes: notes,
            clock: ManualSongClock(duration: 5),
            input: RecordedMotionInput(samples: samples),
            detection: SwingDetection(style: .headbang)
        )

        await session.play()

        #expect(session.judge.keeper.hitCount == 8)
        #expect(session.judge.keeper.missCount == 0)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
        }
    }
}

/// 時刻を手で進める時計。モーションの時刻と曲の時刻を同じにする
private final class ManualSongClock: SongClock {
    let duration: TimeInterval
    var time: TimeInterval = 0
    private(set) var isPlaying = false

    init(duration: TimeInterval) {
        self.duration = duration
    }

    var currentTime: TimeInterval { time }

    func play() throws {
        isPlaying = true
    }

    func pause() {
        isPlaying = false
    }

    func stop() {
        isPlaying = false
    }

    func songTime(atUptime uptime: TimeInterval) -> TimeInterval? {
        isPlaying ? uptime : nil
    }
}

/// 状態を外から変えられる入力。`stop()` を呼ぶまで列を終えない
private final class ControllableMotionInput: MotionInput {
    var status: MotionInputStatus
    private var continuation: AsyncStream<MotionSample>.Continuation?

    init(status: MotionInputStatus) {
        self.status = status
    }

    func start() -> AsyncStream<MotionSample> {
        let (stream, continuation) = AsyncStream.makeStream(of: MotionSample.self)
        self.continuation = continuation
        return stream
    }

    func stop() {
        continuation?.finish()
        continuation = nil
    }
}

private final class UnavailableMotionInputStub: MotionInput {
    let status: MotionInputStatus = .unsupported

    func start() -> AsyncStream<MotionSample> {
        AsyncStream { $0.finish() }
    }

    func stop() {}
}
