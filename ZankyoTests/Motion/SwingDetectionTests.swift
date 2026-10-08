import Foundation
import Testing
@testable import Zankyo

struct SwingDetectionTests {
    @Test
    func defaultsToHeadbang() {
        #expect(SwingDetection().style == .headbang)
        #expect(SwingDetection().makeDetector() is HeadbangDetector)
        #expect(SwingDetection(style: .directional).makeDetector() is CutDetector)
    }

    @Test
    func makesDetectorWithConfiguredThreshold() {
        // 軽い振り（1.3 rad/s）は、閾値を 1.0 に下げた遊び方の検出でだけ数える
        let samples = MotionRecording.make(swings: [.init(direction: .down, peakTime: 1, peakRate: 1.3)])
        for style in PlayStyle.allCases {
            var standard = SwingDetection(style: style).makeDetector()
            var gentle = SwingDetection(style: style)
            gentle.setAdjustableThreshold(1.0, for: style)
            var gentleDetector = gentle.makeDetector()

            #expect(standard.process(samples).isEmpty, "\(style)")
            #expect(gentleDetector.process(samples).count == 1, "\(style)")
        }
    }

    @Test
    func adjustsThresholdOfEachStyle() {
        var detection = SwingDetection()
        detection.setAdjustableThreshold(2.2, for: .headbang)
        detection.setAdjustableThreshold(1.1, for: .directional)

        #expect(detection.headbang.threshold == 2.2)
        #expect(detection.directional.pitchThreshold == 1.1)
        // 左右の閾値は変えない
        #expect(detection.directional.yawThreshold == CutDetector.Configuration().yawThreshold)
        #expect(detection.adjustableThreshold(for: .headbang) == 2.2)
        #expect(detection.adjustableThreshold(for: .directional) == 1.1)
    }

    @Test
    func strengthFollowsStyle() {
        let sample = MotionSample(timestamp: 0, yawRate: 3, pitchRate: 4)

        // ヘドバンは 2 つの軸を合わせた速さ（5）を閾値（1.5）で割る。向きを合わせて切る遊び方は軸ごとの割合の大きい方
        #expect(abs(SwingDetection(style: .headbang).strength(of: sample) - 5 / 1.5) < 1e-9)
        #expect(abs(SwingDetection(style: .directional).strength(of: sample) - 4 / 1.5) < 1e-9)
    }
}
