#if DEBUG
import Foundation

/// 決まった首振り（右・左・上・下）を繰り返す入力。モーションの取れない Simulator で、画面の見え方を確かめるためのデバッグ用
///
/// 起動引数に `-ZankyoDemoMotion` を付けると、実際の入力の代わりに使う（Debug ビルドのみ）
final class DemoMotionInput: MotionInput {
    static let launchArgument = "-ZankyoDemoMotion"
    /// 1 回の振り（素早く向いて、ゆっくり戻る）にかける秒
    static let cycle: TimeInterval = 1.2
    private static let swingDuration: TimeInterval = 0.3
    private static let amplitude = 0.6

    let status: MotionInputStatus = .ready
    private var task: Task<Void, Never>?
    private var continuation: AsyncStream<MotionSample>.Continuation?

    func start() -> AsyncStream<MotionSample> {
        stop()
        let (stream, continuation) = AsyncStream.makeStream(of: MotionSample.self, bufferingPolicy: .bufferingNewest(256))
        self.continuation = continuation
        let origin = ProcessInfo.processInfo.systemUptime
        task = Task {
            var previous: (time: TimeInterval, orientation: HeadOrientation)?
            while !Task.isCancelled {
                let now = ProcessInfo.processInfo.systemUptime
                let orientation = Self.orientation(at: now - origin)
                if let previous, now > previous.time {
                    let elapsed = now - previous.time
                    continuation.yield(MotionSample(
                        timestamp: now,
                        yawRate: (orientation.yaw - previous.orientation.yaw) / elapsed,
                        pitchRate: (orientation.pitch - previous.orientation.pitch) / elapsed,
                        orientation: orientation
                    ))
                }
                previous = (now, orientation)
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        return stream
    }

    func stop() {
        task?.cancel()
        task = nil
        continuation?.finish()
        continuation = nil
    }

    /// 経過秒での向き。振りごとに向きを変え、素早く振ってからゆっくり戻る
    static func orientation(at elapsed: TimeInterval) -> HeadOrientation {
        let index = Int(elapsed / cycle)
        let phase = elapsed - Double(index) * cycle
        let amount: Double
        if phase < swingDuration {
            amount = amplitude * sin(phase / swingDuration * .pi / 2)
        } else {
            amount = amplitude * cos((phase - swingDuration) / (cycle - swingDuration) * .pi / 2)
        }
        switch SwingDirection.allCases[index % SwingDirection.allCases.count] {
        case .up: return HeadOrientation(yaw: 0, pitch: amount)
        case .down: return HeadOrientation(yaw: 0, pitch: -amount)
        case .left: return HeadOrientation(yaw: -amount, pitch: 0)
        case .right: return HeadOrientation(yaw: amount, pitch: 0)
        }
    }
}
#endif
