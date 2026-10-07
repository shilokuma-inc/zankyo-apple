import Foundation

/// 頭の動きの 1 サンプル。角速度は頭の向きの変化（ラジアン毎秒）で、機種ごとの軸の違いは各実装が吸収する
nonisolated struct MotionSample: Sendable, Hashable {
    /// 秒。単調に増える時刻（起点は実装ごとに違ってよい）
    let timestamp: TimeInterval
    /// 左右の首振り（yaw）の角速度。右を向く向きを正とする
    let yawRate: Double
    /// うなずき（pitch）の角速度。上を向く向きを正とする
    let pitchRate: Double
}

/// モーション入力を使えるかどうか。使えないときは、プレイを始めずに案内を出す（Discussion #3 Q3）
nonisolated enum MotionInputStatus: Sendable, Hashable {
    /// 使える
    case ready
    /// この端末・OS では使えない
    case unsupported
    /// 動きの取得をまだ尋ねていない。取得を始めると OS が許可を尋ねる
    case notDetermined
    /// 動きの取得が許可されていない（拒否・制限）
    case notAuthorized
    /// 対応するイヤホンがつながっていない
    case disconnected
}

/// 頭の動きの入力。AirPods（`CMHeadphoneMotionManager`）や visionOS の頭の向きをこの後ろに隠し、
/// テストや Simulator では録画したモーション列に差し替える
protocol MotionInput: AnyObject {
    var status: MotionInputStatus { get }
    /// 動きの取得を始め、サンプルを順に流す。`stop()` を呼ぶか入力が終わると、列も終わる
    func start() -> AsyncStream<MotionSample>
    func stop()
}

/// 録画したモーション列をそのまま流す入力。テスト・デバッグ用で、ユーザー向けの代替入力にはしない
final class RecordedMotionInput: MotionInput {
    let status: MotionInputStatus = .ready
    private let samples: [MotionSample]
    private var continuation: AsyncStream<MotionSample>.Continuation?

    init(samples: [MotionSample]) {
        self.samples = samples
    }

    func start() -> AsyncStream<MotionSample> {
        stop()
        let (stream, continuation) = AsyncStream.makeStream(of: MotionSample.self)
        self.continuation = continuation
        for sample in samples {
            continuation.yield(sample)
        }
        continuation.finish()
        return stream
    }

    func stop() {
        continuation?.finish()
        continuation = nil
    }
}
