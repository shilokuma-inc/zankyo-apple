import Foundation
import Testing
@testable import Zankyo

struct HeadMotionStateTests {
    @Test
    func measuresOrientationFromFirstSample() {
        var state = HeadMotionState()
        state.update(with: MotionSample(timestamp: 1, yawRate: 0, pitchRate: 0, orientation: HeadOrientation(yaw: 1, pitch: -0.2)))
        state.update(with: MotionSample(timestamp: 1.1, yawRate: 0, pitchRate: 0, orientation: HeadOrientation(yaw: 1.3, pitch: 0)))

        // 最初の向きを正面にする
        #expect(abs(state.orientation.yaw - 0.3) < 1e-9)
        #expect(abs(state.orientation.pitch - 0.2) < 1e-9)
    }

    @Test
    func wrapsAroundBehind() {
        var state = HeadMotionState()
        state.update(with: MotionSample(timestamp: 1, yawRate: 0, pitchRate: 0, orientation: HeadOrientation(yaw: 3.1, pitch: 0)))
        state.update(with: MotionSample(timestamp: 1.1, yawRate: 0, pitchRate: 0, orientation: HeadOrientation(yaw: -3.1, pitch: 0)))

        // 真後ろをまたいでも、少し右を向いただけにする
        #expect(abs(state.orientation.yaw - (2 * .pi - 6.2)) < 1e-9)
    }

    @Test
    func integratesRatesWithoutOrientation() {
        var state = HeadMotionState()
        state.update(with: MotionSample(timestamp: 1, yawRate: 1, pitchRate: 0))
        state.update(with: MotionSample(timestamp: 1.1, yawRate: 1, pitchRate: -0.5))

        #expect(abs(state.orientation.yaw - 0.1) < 1e-9)
        #expect(abs(state.orientation.pitch + 0.05) < 1e-9)
    }

    @Test
    func recenterMakesNextSampleFront() {
        var state = HeadMotionState()
        state.update(with: MotionSample(timestamp: 1, yawRate: 0, pitchRate: 0, orientation: HeadOrientation(yaw: 0, pitch: 0)))
        state.update(with: MotionSample(timestamp: 1.1, yawRate: 0, pitchRate: 0, orientation: HeadOrientation(yaw: 0.5, pitch: 0)))
        state.recenter()
        state.update(with: MotionSample(timestamp: 1.2, yawRate: 0, pitchRate: 0, orientation: HeadOrientation(yaw: 0.5, pitch: 0)))

        #expect(state.orientation == HeadOrientation(yaw: 0, pitch: 0))
    }

    @Test
    func strengthFollowsRateAndDecays() {
        var state = HeadMotionState(detection: SwingDetection(style: .directional))
        state.update(with: MotionSample(timestamp: 1, yawRate: 3, pitchRate: -1))
        #expect(state.strength == 1.5)

        // 弱くなっても、すぐには下げない
        state.update(with: MotionSample(timestamp: 1.1, yawRate: 0, pitchRate: 0))
        #expect(abs(state.strength - (1.5 - HeadMotionState.strengthDecayPerSecond * 0.1)) < 1e-9)
    }

    @Test
    func strengthUsesThresholdOfEachAxis() {
        let detection = SwingDetection(style: .directional, directional: .init(yawThreshold: 2.0, pitchThreshold: 1.0))
        var state = HeadMotionState(detection: detection)
        state.update(with: MotionSample(timestamp: 1, yawRate: 1, pitchRate: 1.5))

        // 上下は 1.5 / 1.0、左右は 1 / 2.0。大きい方を強さにする
        #expect(state.strength == 1.5)
    }

    @Test
    func strengthUsesHeadbangSpeed() {
        var state = HeadMotionState(detection: SwingDetection(style: .headbang, headbang: .init(threshold: 2.5)))
        state.update(with: MotionSample(timestamp: 1, yawRate: 3, pitchRate: -4))

        // ヘドバンは向きを問わないので、2 つの軸を合わせた速さ（5）を閾値（2.5）で割る
        #expect(state.strength == 2)
    }

    @Test
    func reconfigureKeepsOrientation() {
        var state = HeadMotionState()
        state.update(with: MotionSample(timestamp: 1, yawRate: 0, pitchRate: 0, orientation: HeadOrientation(yaw: 0.1, pitch: 0)))
        state.update(with: MotionSample(timestamp: 1.1, yawRate: 0, pitchRate: 0, orientation: HeadOrientation(yaw: 0.4, pitch: 0)))

        state.reconfigure(SwingDetection(style: .directional, directional: .init(pitchThreshold: 2.4)))

        #expect(state.detection.style == .directional)
        #expect(state.detection.directional.pitchThreshold == 2.4)
        #expect(abs(state.orientation.yaw - 0.3) < 1e-9)
    }

    @Test
    func highlightsDetectedSwingForAWhile() {
        var state = HeadMotionState()
        // 右へ強く振って止める
        for (time, rate) in [(1.0, 0.0), (1.02, 3.0), (1.04, 4.0), (1.06, 1.0)] {
            state.update(with: MotionSample(timestamp: time, yawRate: rate, pitchRate: 0))
        }

        #expect(state.lastCut?.direction == .right)
        #expect(state.highlightedDirection(at: 1.1) == .right)
        #expect(state.highlightedDirection(at: 1.04 + HeadMotionState.cutHighlightDuration + 0.01) == nil)
    }

    @Test
    func demoInputSwingsInAllDirections() {
        var state = HeadMotionState()
        var detected: [SwingDirection] = []
        var lastSeen: CutEvent?
        var previous: HeadOrientation?
        // 4 振り分（1 振り 1.2 秒）を 20ms おきに流す
        for step in 0...240 {
            let time = Double(step) * 0.02
            let orientation = DemoMotionInput.orientation(at: time)
            if let previous {
                state.update(with: MotionSample(
                    timestamp: time,
                    yawRate: (orientation.yaw - previous.yaw) / 0.02,
                    pitchRate: (orientation.pitch - previous.pitch) / 0.02,
                    orientation: orientation
                ))
            }
            if let cut = state.lastCut, cut != lastSeen {
                detected.append(cut.direction)
                lastSeen = cut
            }
            previous = orientation
        }

        // 戻す動きは数えず、1 振りごとに SwingDirection の並び（上・下・左・右）で 1 回ずつ検出する
        #expect(detected == SwingDirection.allCases)
    }
}
