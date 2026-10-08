import Foundation
import Testing
@testable import Zankyo

struct HeadbangDetectorTests {
    @Test
    func detectsNodAtPeak() throws {
        var detector = HeadbangDetector()
        let cuts = detector.process(MotionRecording.make(swings: [.init(direction: .down, peakTime: 1, peakRate: 3)]))

        #expect(cuts.count == 1)
        let cut = try #require(cuts.first)
        #expect(abs(cut.timestamp - 1) < 0.011)
        #expect(abs(cut.peakRate - 3) < 0.05)
        #expect(cut.direction == .down)
    }

    @Test(arguments: [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0), (0.7, 0.7), (-0.6, -0.8)])
    func detectsSwingInAnyDirection(yaw: Double, pitch: Double) {
        // 左右・上下・斜めのどの向きでも、同じ速さなら 1 回の振りになる
        let samples = Self.stroke(peakTime: 0.5, peakRate: 2.5) { rate in (rate * yaw, rate * pitch) }
        var detector = HeadbangDetector()

        #expect(detector.process(samples).count == 1)
    }

    @Test
    func countsArcSwingOnce() {
        // 振りながら向きが 60 度回る（弧を描く）振りを、2 回に数えない
        let samples = Self.stroke(peakTime: 0.5, peakRate: 4, width: 0.3) { rate, progress in
            let angle = Double.pi / 3 * progress
            return (rate * cos(angle), -rate * sin(angle))
        }
        var detector = HeadbangDetector()

        #expect(detector.process(samples).count == 1)
    }

    @Test
    func ignoresSlowSway() {
        // 電車の揺れのようなゆっくりした回転は、2 つの軸を合わせても閾値に届かない
        let samples = (0..<500).map { index in
            let time = Double(index) / 50
            return MotionSample(timestamp: time, yawRate: sin(time * 2) * 0.9, pitchRate: cos(time * 3) * 0.9)
        }
        var detector = HeadbangDetector()

        #expect(detector.process(samples).isEmpty)
    }

    @Test(arguments: [true, false])
    func detectsEveryStrokeWhicheverStrokeComesFirst(startsWithUpStroke: Bool) {
        // 120 BPM で 1 拍に 1 回うなずき続ける（振り下ろしと戻しで 1 往復）。首を戻す動きから振り始めても、
        // 拍に合わせた振り下ろしを毎回数える（戻す動きを間引くと、戻す側に位相がそろったまま振り下ろしを数えなくなる）
        let period = 0.5
        let samples = Self.oscillation(period: period, cycles: 8, peakRate: 4, sampleRate: 50, startsWithUpStroke: startsWithUpStroke)
        var detector = HeadbangDetector()
        let cuts = detector.process(samples)

        let downStrokes = Self.strokePeaks(period: period, cycles: 8, startsWithUpStroke: startsWithUpStroke, down: true)
        for peak in downStrokes {
            #expect(cuts.contains { $0.direction == .down && abs($0.timestamp - peak) <= 0.021 }, "\(peak) 秒の振り下ろし")
        }
        // 戻す動きも 1 回ずつ数え、1 往復を 3 回以上に数えない
        #expect(cuts.count == 16)
    }

    @Test
    func detectsFastHeadbangWithSparseSamples() {
        // AirPods 程度の粗いサンプル（25Hz）で、ノーツの最小間隔（0.35 秒）ごとに頭を振る
        let period = FaceNoteConverter.Configuration().minimumInterval
        let samples = Self.oscillation(period: period, cycles: 10, peakRate: 5, sampleRate: 25, startsWithUpStroke: false)
        var detector = HeadbangDetector()
        let cuts = detector.process(samples)

        for peak in Self.strokePeaks(period: period, cycles: 10, startsWithUpStroke: false, down: true) {
            #expect(cuts.contains { $0.direction == .down && abs($0.timestamp - peak) <= 0.041 }, "\(peak) 秒の振り下ろし")
        }
    }

    @Test
    func endsStrokeWhenItTurnsBackWithoutStopping() {
        // サンプルの間に折り返し、止まったところが取れなくても、逆向きの振りを別の振りとして数える
        let rates: [Double] = [0, 2, 4, 2, -2, -4, -2, 0]
        let samples = rates.enumerated().map { index, rate in
            MotionSample(timestamp: Double(index) * 0.05, yawRate: 0, pitchRate: rate)
        }
        var detector = HeadbangDetector()

        #expect(detector.process(samples).map(\.direction) == [.up, .down])
    }

    @Test
    func countsStrongSwingOnce() {
        // 速さが一度ゆるんでから、もう一度強まる 1 回の振り（ピークの 7 割まで下がる）を、2 回に数えない
        let rates: [Double] = [0, 2, 4, 3.2, 2.8, 3.6, 2, 0.5, 0]
        let samples = rates.enumerated().map { index, rate in
            MotionSample(timestamp: Double(index) * 0.02, yawRate: rate, pitchRate: 0)
        }
        var detector = HeadbangDetector()

        #expect(detector.process(samples).count == 1)
    }

    @Test
    func ignoresSecondPeakWithinRefractory() {
        // いったん止まっても、0.12 秒以内の同じ向きの振りは 1 回の振りの揺れとみなす
        let samples = MotionRecording.make(swings: [
            .init(direction: .down, peakTime: 1, peakRate: 3, width: 0.06),
            .init(direction: .down, peakTime: 1.1, peakRate: 3, width: 0.06)
        ])
        var detector = HeadbangDetector()

        #expect(detector.process(samples).count == 1)
    }

    @Test
    func usesConfiguredThreshold() {
        let samples = MotionRecording.make(swings: [.init(direction: .down, peakTime: 1, peakRate: 1.3)])
        var standard = HeadbangDetector()
        var gentle = HeadbangDetector(configuration: .init(threshold: 1.0))

        #expect(standard.process(samples).isEmpty)
        #expect(gentle.process(samples).count == 1)
    }

    @Test
    func skipsNonFiniteSamples() {
        var detector = HeadbangDetector()
        let samples = [
            MotionSample(timestamp: 0, yawRate: .nan, pitchRate: 0),
            MotionSample(timestamp: .infinity, yawRate: 3, pitchRate: 0),
            MotionSample(timestamp: 0.1, yawRate: 0, pitchRate: .infinity)
        ]

        #expect(detector.process(samples).isEmpty)
    }

    /// 1 回の振り（半周期の正弦波の山）を、向きを決める関数で 2 つの軸に分ける。関数には速さと、振りの進み具合（0〜1）を渡す
    private static func stroke(
        peakTime: TimeInterval,
        peakRate: Double,
        width: TimeInterval = 0.2,
        sampleRate: Double = 50,
        components: (Double, Double) -> (yaw: Double, pitch: Double)
    ) -> [MotionSample] {
        let start = peakTime - width / 2
        return (0...Int((peakTime + width) * sampleRate)).map { index in
            let time = Double(index) / sampleRate
            let progress = (time - start) / width
            let rate = (0...1).contains(progress) ? peakRate * sin(.pi * progress) : 0
            let (yaw, pitch) = components(rate, min(max(progress, 0), 1))
            return MotionSample(timestamp: time, yawRate: yaw, pitchRate: pitch)
        }
    }

    private static func stroke(
        peakTime: TimeInterval,
        peakRate: Double,
        components: (Double) -> (yaw: Double, pitch: Double)
    ) -> [MotionSample] {
        stroke(peakTime: peakTime, peakRate: peakRate) { rate, _ in components(rate) }
    }

    /// うなずきを繰り返す動き。上下の角速度は正弦波で、1 周期に振り下ろしと戻しの山が 1 つずつある
    private static func oscillation(
        period: TimeInterval,
        cycles: Int,
        peakRate: Double,
        sampleRate: Double,
        startsWithUpStroke: Bool
    ) -> [MotionSample] {
        let sign = startsWithUpStroke ? 1.0 : -1.0
        let end = period * Double(cycles)
        return (0...Int((end + 0.3) * sampleRate)).map { index in
            let time = Double(index) / sampleRate
            let rate = time <= end ? sign * peakRate * sin(2 * .pi * time / period) : 0
            return MotionSample(timestamp: time, yawRate: 0, pitchRate: rate)
        }
    }

    /// `oscillation` の振り下ろし（`down`）または戻し（上向き）の速さのピークの時刻
    private static func strokePeaks(period: TimeInterval, cycles: Int, startsWithUpStroke: Bool, down: Bool) -> [TimeInterval] {
        // 正弦波の山は周期の 1/4、谷は 3/4。振り下ろしが山か谷かは、始めの向きで決まる
        let firstHalfIsDown = !startsWithUpStroke
        let phase = (down == firstHalfIsDown) ? 0.25 : 0.75
        return (0..<cycles).map { (Double($0) + phase) * period }
    }
}
