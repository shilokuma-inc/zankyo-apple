import Foundation
import Testing
@testable import Zankyo

struct CalibrationAnalyzerTests {
    /// 0.6 秒おきのクリック 20 回（最初の 4 回は前打ち）
    private static let clicks = (0..<20).map { 1 + Double($0) * 0.6 }

    @Test
    func averagesDelayAfterCountIn() throws {
        // 前打ちの 4 回への振りは数えない（ずれが大きくても結果に入らない）
        let cuts = Self.clicks.enumerated().map { index, click in
            index < 4 ? click + 0.25 : click + (index.isMultiple(of: 2) ? 0.08 : 0.12)
        }
        let result = try #require(CalibrationAnalyzer.analyze(clickTimes: Self.clicks, cutTimes: cuts))

        #expect(abs(result.offset - 0.1) < 1e-9)
        #expect(result.matchedCount == 16)
        #expect(abs(result.spread - 0.02) < 1e-9)
    }

    @Test
    func handlesEarlySwings() throws {
        let cuts = Self.clicks.map { $0 - 0.05 }
        let result = try #require(CalibrationAnalyzer.analyze(clickTimes: Self.clicks, cutTimes: cuts))

        #expect(abs(result.offset + 0.05) < 1e-9)
    }

    @Test
    func dropsOutliersAndUnmatchedSwings() throws {
        var cuts = Self.clicks.map { $0 + 0.1 }
        // 1 回だけ大きく遅れた振りと、クリックから遠い余計な振り
        cuts[10] = Self.clicks[10] + 0.28
        cuts.append(Self.clicks[12] + 0.45)
        let result = try #require(CalibrationAnalyzer.analyze(clickTimes: Self.clicks, cutTimes: cuts))

        #expect(abs(result.offset - 0.1) < 1e-9)
        #expect(result.matchedCount == 15)
    }

    @Test
    func usesEachSwingOnce() {
        // 1 回の振りを、近い 2 つのクリックに数えない
        let clicks = [1.0, 1.2, 1.4, 1.6, 1.8, 2.0, 2.2]
        let result = CalibrationAnalyzer.analyze(
            clickTimes: clicks,
            cutTimes: [1.1],
            configuration: .init(countIn: 0, minimumMatches: 2)
        )

        #expect(result == nil)
    }

    @Test
    func needsEnoughSwings() {
        let cuts = Self.clicks.prefix(9).map { $0 + 0.1 }

        // 前打ちの後の 5 回だけでは足りない
        #expect(CalibrationAnalyzer.analyze(clickTimes: Self.clicks, cutTimes: cuts) == nil)
        #expect(CalibrationAnalyzer.analyze(clickTimes: Self.clicks, cutTimes: []) == nil)
    }
}

struct CalibrationStoreTests {
    @Test
    func savesAndClampsOffset() {
        let suite = "ZankyoTests.Calibration.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let store = CalibrationStore(suiteName: suite)

        #expect(store.offset == 0)
        #expect(!store.hasOffset)

        store.save(0.085)
        #expect(store.offset == 0.085)
        #expect(store.hasOffset)

        store.save(2)
        #expect(store.offset == CalibrationStore.range.upperBound)

        store.save(.nan)
        #expect(store.offset == CalibrationStore.range.upperBound)

        store.reset()
        #expect(!store.hasOffset)
        #expect(store.offset == 0)
    }

    @Test
    func ignoresBrokenStoredValue() {
        let suite = "ZankyoTests.Calibration.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        UserDefaults(suiteName: suite)?.set("fast", forKey: CalibrationStore.offsetKey)

        #expect(CalibrationStore(suiteName: suite).offset == 0)
    }
}

struct CalibrationModelTests {
    @Test
    func measuresOffsetFromRecordedSwings() async throws {
        let suite = "ZankyoTests.Calibration.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let clicks = (0..<CalibrationModel.beats).map { 1 + Double($0) * 0.6 }
        // 前打ちの後、各クリックの 0.1 秒後に左右交互に振る
        let swings = clicks.enumerated().dropFirst(4).map { index, click in
            MotionRecording.Swing(direction: index.isMultiple(of: 2) ? .right : .left, peakTime: click + 0.1, peakRate: 4)
        }
        let metronome = FakeMetronome(clicks: clicks)
        let model = CalibrationModel(
            input: RecordedMotionInput(samples: MotionRecording.make(swings: swings)),
            metronome: metronome,
            store: CalibrationStore(suiteName: suite),
            now: { 1_000 }
        )

        await model.measure()

        guard case .finished(let result) = model.phase else {
            Issue.record("測り終えるはず: \(model.phase)")
            return
        }
        #expect(abs(result.offset - 0.1) < 0.001)
        #expect(result.matchedCount == 16)
        #expect(metronome.isStopped)

        model.save()
        #expect(model.phase == .idle)
        let saved = try #require(model.savedOffset)
        #expect(abs(saved - 0.1) < 0.001)
    }

    @Test
    func failsWithoutSwings() async {
        let model = CalibrationModel(
            input: RecordedMotionInput(samples: MotionRecording.make(swings: [], duration: 2)),
            metronome: FakeMetronome(clicks: (0..<CalibrationModel.beats).map { Double($0) * 0.6 }),
            store: CalibrationStore(suiteName: "ZankyoTests.Calibration.\(UUID().uuidString)"),
            now: { 1_000 }
        )

        await model.measure()

        guard case .failed = model.phase else {
            Issue.record("振りが無ければ失敗するはず: \(model.phase)")
            return
        }
    }

    @Test
    func cannotMeasureWithoutMotionInput() {
        let model = CalibrationModel(input: UnavailableMotionInput(), metronome: FakeMetronome(clicks: []))

        #expect(!model.canMeasure)
    }
}

/// 音を鳴らさず、決まったクリックの時刻を返す
private final class FakeMetronome: Metronome {
    let clicks: [TimeInterval]
    private(set) var isStopped = false

    init(clicks: [TimeInterval]) {
        self.clicks = clicks
    }

    func start(bpm: Double, beats: Int) throws -> [TimeInterval] {
        isStopped = false
        return clicks
    }

    func stop() {
        isStopped = true
    }
}
