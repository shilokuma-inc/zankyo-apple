import Foundation
import simd

/// 頭の姿勢（ワールドに対する変換行列）の列から、yaw / pitch の角速度を求める。visionOS の頭の向きの入力で使う
///
/// 姿勢の前方向は -Z（ARKit の device anchor と同じ）。右を向く向き・上を向く向きを正にする
nonisolated struct HeadRateTracker: Sendable {
    /// これより間が空いたサンプルは、前とつなげずに数え直す（追跡が途切れたときなど）
    static let maxGap: TimeInterval = 0.25

    private struct Pose {
        let timestamp: TimeInterval
        let yaw: Double
        let pitch: Double
    }

    private var previous: Pose?

    /// 姿勢を 1 つ受け取り、前の姿勢との差から角速度のサンプルを返す。最初の 1 つと、間が空いたときは nil
    @discardableResult
    mutating func update(timestamp: TimeInterval, transform: simd_float4x4) -> MotionSample? {
        guard timestamp.isFinite else { return nil }
        let (yaw, pitch) = Self.angles(of: transform)
        guard yaw.isFinite, pitch.isFinite else { return nil }
        defer { previous = Pose(timestamp: timestamp, yaw: yaw, pitch: pitch) }
        guard let previous else { return nil }
        let elapsed = timestamp - previous.timestamp
        guard elapsed > 0, elapsed <= Self.maxGap else { return nil }
        return MotionSample(
            timestamp: timestamp,
            yawRate: Self.wrap(yaw - previous.yaw) / elapsed,
            pitchRate: (pitch - previous.pitch) / elapsed,
            orientation: HeadOrientation(yaw: yaw, pitch: pitch)
        )
    }

    mutating func reset() {
        previous = nil
    }

    /// 前方向の yaw（右が正・-π〜π）と pitch（上が正・-π/2〜π/2）
    static func angles(of transform: simd_float4x4) -> (yaw: Double, pitch: Double) {
        let forward = -simd_normalize(simd_make_float3(transform.columns.2))
        let yaw = atan2(Double(forward.x), Double(-forward.z))
        let pitch = asin(Double(min(max(forward.y, -1), 1)))
        return (yaw, pitch)
    }

    /// 角度の差を -π〜π に収める（真後ろをまたいだときに 2π 跳ばないように）
    private static func wrap(_ angle: Double) -> Double {
        var value = angle
        while value > .pi { value -= 2 * .pi }
        while value < -.pi { value += 2 * .pi }
        return value
    }
}
