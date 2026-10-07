import Foundation
import simd
import Testing
@testable import Zankyo

struct HeadRateTrackerTests {
    @Test
    func turningRightIsPositiveYaw() throws {
        var tracker = HeadRateTracker()

        // 右を向くのは +Y 軸まわりの負の回転（前方向 -Z が +X へ向く）
        let first = tracker.update(timestamp: 0, transform: Self.pose(yaw: 0))
        #expect(first == nil)
        let updated = tracker.update(timestamp: 0.1, transform: Self.pose(yaw: 0.2))
        let sample = try #require(updated)

        #expect(abs(sample.yawRate - 2) < 1e-4)
        #expect(abs(sample.pitchRate) < 1e-4)
        #expect(sample.timestamp == 0.1)
    }

    @Test
    func lookingUpIsPositivePitch() throws {
        var tracker = HeadRateTracker()
        tracker.update(timestamp: 1, transform: Self.pose(pitch: 0))
        let updated = tracker.update(timestamp: 1.05, transform: Self.pose(pitch: 0.1))
        let sample = try #require(updated)

        #expect(abs(sample.pitchRate - 2) < 1e-4)
        #expect(abs(sample.yawRate) < 1e-4)
    }

    @Test
    func wrapsAroundBehind() throws {
        // 真後ろ（±π）をまたいでも、2π 跳ばずに小さな回転として扱う
        var tracker = HeadRateTracker()
        tracker.update(timestamp: 0, transform: Self.pose(yaw: .pi - 0.05))
        let updated = tracker.update(timestamp: 0.1, transform: Self.pose(yaw: -.pi + 0.05))
        let sample = try #require(updated)

        #expect(abs(sample.yawRate - 1) < 1e-3)
    }

    @Test
    func restartsAfterGapOrReset() {
        var tracker = HeadRateTracker()
        tracker.update(timestamp: 0, transform: Self.pose(yaw: 0))

        let afterGap = tracker.update(timestamp: 1, transform: Self.pose(yaw: 0.5))
        let next = tracker.update(timestamp: 1.01, transform: Self.pose(yaw: 0.5))
        tracker.reset()
        let afterReset = tracker.update(timestamp: 1.02, transform: Self.pose(yaw: 0.5))

        #expect(afterGap == nil)
        #expect(next != nil)
        #expect(afterReset == nil)
    }

    @Test
    func ignoresPositionAndNonIncreasingTime() {
        var tracker = HeadRateTracker()
        var moved = Self.pose(yaw: 0)
        moved.columns.3 = SIMD4(3, 1.5, -2, 1)
        tracker.update(timestamp: 0, transform: Self.pose(yaw: 0))

        let sameTime = tracker.update(timestamp: 0, transform: moved)
        let sample = tracker.update(timestamp: 0.01, transform: moved)

        #expect(sameTime == nil)
        #expect(sample.map { abs($0.yawRate) < 1e-4 } == true)
    }

    @Test
    func detectsSwingFromHeadPoses() {
        // 頭の姿勢の列から求めた角速度で、「切る」動きを検出できる
        var tracker = HeadRateTracker()
        var detector = CutDetector()
        var cuts: [CutEvent] = []
        for index in 0...90 {
            let time = Double(index) / 90
            // 0.4〜0.6 秒に、右へ 0.5 ラジアンほど首を振る
            let progress = min(max((time - 0.4) / 0.2, 0), 1)
            let yaw = 0.5 * (1 - cos(Double.pi * progress)) / 2
            if let sample = tracker.update(timestamp: time, transform: Self.pose(yaw: yaw)),
               let cut = detector.process(sample) {
                cuts.append(cut)
            }
        }

        #expect(cuts.map(\.direction) == [.right])
    }

    /// 右を向く角度 `yaw`・上を向く角度 `pitch` の姿勢
    private static func pose(yaw: Double = 0, pitch: Double = 0) -> simd_float4x4 {
        let turn = simd_quatf(angle: Float(-yaw), axis: SIMD3(0, 1, 0))
        let nod = simd_quatf(angle: Float(pitch), axis: SIMD3(1, 0, 0))
        return simd_float4x4(turn * nod)
    }
}
