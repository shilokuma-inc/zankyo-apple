import Foundation
import Testing
@testable import Zankyo

struct CutDetectorTests {
    @Test
    func detectsTurnAtPeak() throws {
        var detector = CutDetector()
        let cuts = detector.process(MotionRecording.make(swings: [.init(direction: .right, peakTime: 1, peakRate: 4)]))

        #expect(cuts.count == 1)
        let cut = try #require(cuts.first)
        #expect(cut.direction == .right)
        #expect(abs(cut.timestamp - 1) < 0.011)
        #expect(abs(cut.peakRate - 4) < 0.05)
    }

    @Test(arguments: SwingDirection.allCases)
    func detectsEachDirection(direction: SwingDirection) {
        var detector = CutDetector()
        let cuts = detector.process(MotionRecording.make(swings: [.init(direction: direction, peakTime: 0.5, peakRate: 3)]))

        #expect(cuts.map(\.direction) == [direction])
    }

    @Test
    func ignoresSlowSway() {
        // 電車の揺れのようなゆっくりした回転は閾値に届かない
        let samples = (0..<500).map { index in
            let time = Double(index) / 50
            return MotionSample(timestamp: time, yawRate: sin(time * 2) * 1.2, pitchRate: cos(time * 3) * 0.8)
        }
        var detector = CutDetector()

        #expect(detector.process(samples).isEmpty)
    }

    @Test
    func suppressesReturnSwing() {
        // 右を向いてすぐ首を戻す動き（左向きのピーク）は数えない
        let samples = MotionRecording.make(swings: [
            .init(direction: .right, peakTime: 1, peakRate: 4),
            .init(direction: .left, peakTime: 1.25, peakRate: 3)
        ])
        var detector = CutDetector()

        #expect(detector.process(samples).map(\.direction) == [.right])
    }

    @Test
    func detectsOppositeSwingAfterReturnWindow() {
        let samples = MotionRecording.make(swings: [
            .init(direction: .right, peakTime: 1, peakRate: 4),
            .init(direction: .left, peakTime: 1.6, peakRate: 4)
        ])
        var detector = CutDetector()

        #expect(detector.process(samples).map(\.direction) == [.right, .left])
    }

    @Test
    func countsStrongSwingOnce() {
        // ピークの半分まで下がっても閾値より上にいる強い振りを、2 回に数えない
        var detector = CutDetector()
        let cuts = detector.process(MotionRecording.make(swings: [.init(direction: .up, peakTime: 1, peakRate: 10, width: 0.4)]))

        #expect(cuts.map(\.direction) == [.up])
    }

    @Test
    func detectsRepeatedSwingsInSameDirection() {
        let samples = MotionRecording.make(swings: [
            .init(direction: .down, peakTime: 1, peakRate: 3),
            .init(direction: .down, peakTime: 1.4, peakRate: 3)
        ])
        var detector = CutDetector()

        #expect(detector.process(samples).map(\.direction) == [.down, .down])
    }

    @Test
    func roundsDiagonalSwingToStrongerAxis() {
        let samples = (0...20).map { index in
            let time = Double(index) / 50
            let shape = sin(Double.pi * time / 0.4)
            return MotionSample(timestamp: time, yawRate: shape * -2.5, pitchRate: shape * -3.5)
        }
        var detector = CutDetector()

        #expect(detector.process(samples).map(\.direction) == [.down])
    }

    @Test
    func detectsGentleNodBelowYawThreshold() {
        // 上下の閾値（既定 1.5）は左右（2.0）より低い。同じ 1.7 rad/s でも、うなずきだけが振りになる
        var detector = CutDetector()
        let samples = MotionRecording.make(swings: [
            .init(direction: .up, peakTime: 0.5, peakRate: 1.7),
            .init(direction: .right, peakTime: 1.5, peakRate: 1.7)
        ])

        #expect(detector.process(samples).map(\.direction) == [.up])
    }

    @Test
    func usesConfiguredPitchThreshold() {
        let nod = MotionRecording.make(swings: [.init(direction: .down, peakTime: 0.5, peakRate: 1.2)])
        var strict = CutDetector(configuration: .init(pitchThreshold: 2.0))
        var gentle = CutDetector(configuration: .init(pitchThreshold: 1.0))

        #expect(strict.process(nod).isEmpty)
        #expect(gentle.process(nod).map(\.direction) == [.down])
    }

    @Test
    func comparesAxesRelativeToTheirThresholds() {
        // 角速度は左右（2.2）の方が大きいが、閾値に対する割合は上下（1.8 / 1.5 = 1.2）の方が大きい
        let samples = (0...20).map { index in
            let time = Double(index) / 50
            let shape = sin(Double.pi * time / 0.4)
            return MotionSample(timestamp: time, yawRate: shape * 2.2, pitchRate: shape * 1.8)
        }
        var detector = CutDetector()

        #expect(detector.process(samples).map(\.direction) == [.up])
    }

    @Test
    func countsCurvedSwingOnce() {
        // 先に上下、少し遅れて左右が強くなる 1 回の振り（弧を描く動き）。強い軸が入れ替わっても 1 回に数える
        var detector = CutDetector()
        let samples = MotionRecording.make(swings: [
            .init(direction: .up, peakTime: 1.0, peakRate: 3, width: 0.4),
            .init(direction: .right, peakTime: 1.15, peakRate: 4, width: 0.4)
        ])

        #expect(detector.process(samples).count == 1)
    }

    @Test
    func detectsSwingOnAnotherAxisAfterFirstEnds() {
        // 右に振り終えてからのうなずきは、別の振りとして数える
        var detector = CutDetector()
        let samples = MotionRecording.make(swings: [
            .init(direction: .right, peakTime: 1.0, peakRate: 4),
            .init(direction: .down, peakTime: 1.3, peakRate: 3)
        ])

        #expect(detector.process(samples).map(\.direction) == [.right, .down])
    }

    @Test
    func worksAtLowSampleRate() {
        // AirPods のサンプルは毎秒 25 回ほどのことがある
        let samples = MotionRecording.make(
            swings: [.init(direction: .left, peakTime: 1, peakRate: 4), .init(direction: .right, peakTime: 2, peakRate: 4)],
            sampleRate: 25
        )
        var detector = CutDetector()

        #expect(detector.process(samples).map(\.direction) == [.left, .right])
    }

    @Test
    func ignoresNonFiniteSamples() {
        var detector = CutDetector()
        let samples = [
            MotionSample(timestamp: 0, yawRate: .infinity, pitchRate: 0),
            MotionSample(timestamp: 0.02, yawRate: .nan, pitchRate: 0),
            MotionSample(timestamp: 0.04, yawRate: 0, pitchRate: 0)
        ]

        #expect(detector.process(samples).isEmpty)
    }

    @Test
    func detectsCutsFromRecordedInput() async {
        let input = RecordedMotionInput(samples: MotionRecording.make(swings: [
            .init(direction: .up, peakTime: 0.5, peakRate: 3),
            .init(direction: .right, peakTime: 1.2, peakRate: 3)
        ]))
        var detector = CutDetector()
        var cuts: [CutEvent] = []

        #expect(input.status == .ready)
        for await sample in input.start() {
            if let cut = detector.process(sample) {
                cuts.append(cut)
            }
        }

        #expect(cuts.map(\.direction) == [.up, .right])
    }
}

/// 自作のモーション列。振りは半周期の正弦波の山で表す
enum MotionRecording {
    struct Swing {
        let direction: SwingDirection
        let peakTime: TimeInterval
        let peakRate: Double
        var width: TimeInterval = 0.2
    }

    static func make(swings: [Swing], sampleRate: Double = 50, duration: TimeInterval? = nil) -> [MotionSample] {
        let end = duration ?? ((swings.map { $0.peakTime + $0.width }.max() ?? 0) + 0.5)
        return (0...Int(end * sampleRate)).map { index in
            let time = Double(index) / sampleRate
            var yaw = 0.0
            var pitch = 0.0
            for swing in swings {
                let start = swing.peakTime - swing.width / 2
                guard (start...(start + swing.width)).contains(time) else { continue }
                let rate = swing.peakRate * sin(Double.pi * (time - start) / swing.width)
                switch swing.direction {
                case .right: yaw += rate
                case .left: yaw -= rate
                case .up: pitch += rate
                case .down: pitch -= rate
                }
            }
            return MotionSample(timestamp: time, yawRate: yaw, pitchRate: pitch)
        }
    }
}
