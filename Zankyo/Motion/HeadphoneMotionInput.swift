#if !os(visionOS)
import CoreMotion
import Foundation
import Observation

/// AirPods など、頭の動きに対応したイヤホンのモーションセンサー（`CMHeadphoneMotionManager`）からの入力。
/// iOS / macOS で使う。visionOS は ARKit の頭の向きを使う（Discussion #3 Q7）
@Observable
final class HeadphoneMotionInput: MotionInput {
    private(set) var status: MotionInputStatus

    @ObservationIgnored private let manager: CMHeadphoneMotionManager
    @ObservationIgnored private let queue: OperationQueue
    @ObservationIgnored private var delegate: ConnectionDelegate?
    @ObservationIgnored private var continuation: AsyncStream<MotionSample>.Continuation?
    @ObservationIgnored private var isConnected = false

    init(manager: CMHeadphoneMotionManager = CMHeadphoneMotionManager()) {
        self.manager = manager
        let queue = OperationQueue()
        queue.name = "jp.shilokuma.Zankyo.HeadphoneMotion"
        queue.maxConcurrentOperationCount = 1
        self.queue = queue
        status = Self.status(
            isAvailable: manager.isDeviceMotionAvailable,
            authorization: CMHeadphoneMotionManager.authorizationStatus(),
            isConnected: false
        )
    }

    func start() -> AsyncStream<MotionSample> {
        stop()
        // 判定に使うのは新しいサンプルなので、処理が詰まったら古いものから捨てる
        let (stream, continuation) = AsyncStream.makeStream(of: MotionSample.self, bufferingPolicy: .bufferingNewest(256))
        guard manager.isDeviceMotionAvailable else {
            status = .unsupported
            continuation.finish()
            return stream
        }
        self.continuation = continuation
        // 接続・接続解除の通知は取得を始めてから届く。権限を尋ねるのも取得を始めたとき
        let delegate = ConnectionDelegate(onChange: Self.connectionHandler(for: self))
        self.delegate = delegate
        manager.delegate = delegate
        manager.startDeviceMotionUpdates(to: queue, withHandler: Self.motionHandler(for: self, continuation: continuation))
        return stream
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        manager.delegate = nil
        delegate = nil
        continuation?.finish()
        continuation = nil
        isConnected = false
        refreshStatus()
    }

    private func connectionChanged(_ isConnected: Bool) {
        self.isConnected = isConnected
        refreshStatus()
    }

    private func refreshStatus() {
        status = Self.status(
            isAvailable: manager.isDeviceMotionAvailable,
            authorization: CMHeadphoneMotionManager.authorizationStatus(),
            isConnected: isConnected
        )
    }

    /// 端末の対応・権限・接続から、入力を使えるかを決める
    nonisolated static func status(
        isAvailable: Bool,
        authorization: CMAuthorizationStatus,
        isConnected: Bool
    ) -> MotionInputStatus {
        guard isAvailable else { return .unsupported }
        switch authorization {
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted:
            return .notAuthorized
        case .authorized:
            return isConnected ? .ready : .disconnected
        @unknown default:
            return .notAuthorized
        }
    }

    // MotionInput の外（CoreMotion のキュー）で呼ばれるので、MainActor に隔離されないクロージャを nonisolated な関数で作る

    nonisolated private static func motionHandler(
        for input: HeadphoneMotionInput,
        continuation: AsyncStream<MotionSample>.Continuation
    ) -> CMHeadphoneMotionManager.DeviceMotionHandler {
        { [weak input] motion, error in
            if let motion {
                continuation.yield(MotionSample(headphoneTimestamp: motion.timestamp, rotationRate: motion.rotationRate))
            } else if error != nil {
                // 権限が無い・取り消されたときなどはエラーで届く
                Task { @MainActor [input] in input?.refreshStatus() }
            }
        }
    }

    nonisolated private static func connectionHandler(for input: HeadphoneMotionInput) -> @Sendable (Bool) -> Void {
        { [weak input] isConnected in
            Task { @MainActor [input] in input?.connectionChanged(isConnected) }
        }
    }
}

/// イヤホンの接続・接続解除を受け取る
nonisolated private final class ConnectionDelegate: NSObject, CMHeadphoneMotionManagerDelegate, Sendable {
    private let onChange: @Sendable (Bool) -> Void

    init(onChange: @escaping @Sendable (Bool) -> Void) {
        self.onChange = onChange
    }

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        onChange(true)
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        onChange(false)
    }
}

extension MotionSample {
    /// AirPods の角速度から作る。`CMRotationRate` は右手系で x 軸まわり = うなずき（上を向くと正）、
    /// z 軸まわり = 首振り（左を向くと正）なので、右を向く向きを正にするため z の符号を反転する
    nonisolated init(headphoneTimestamp: TimeInterval, rotationRate: CMRotationRate) {
        self.init(timestamp: headphoneTimestamp, yawRate: -rotationRate.z, pitchRate: rotationRate.x)
    }
}
#endif
