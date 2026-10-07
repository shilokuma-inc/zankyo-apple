#if !os(visionOS)
import CoreMotion
import Foundation
import Observation
import os

/// AirPods など、頭の動きに対応したイヤホンのモーションセンサー（`CMHeadphoneMotionManager`）からの入力。
/// iOS / macOS で使う。visionOS は ARKit の頭の向きを使う（Discussion #3 Q7）
@Observable
final class HeadphoneMotionInput: MotionInput {
    private(set) var status: MotionInputStatus

    @ObservationIgnored private let manager: CMHeadphoneMotionManager
    @ObservationIgnored private let queue: OperationQueue
    @ObservationIgnored private var delegate: ConnectionDelegate?
    @ObservationIgnored private var continuation: AsyncStream<MotionSample>.Continuation?
    /// 取得の回ごとの番号。前の回の列の終わりが、今の回を止めないようにする
    @ObservationIgnored private var session = 0
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
        // 接続・接続解除の通知は、接続状態の監視を始めないと届かない。プレイ前の案内にも使うので、作った時点から監視する
        let delegate = ConnectionDelegate(onChange: Self.connectionHandler(for: self))
        self.delegate = delegate
        manager.delegate = delegate
        if manager.isDeviceMotionAvailable {
            manager.startConnectionStatusUpdates()
        }
    }

    func start() -> AsyncStream<MotionSample> {
        stop()
        session += 1
        // 判定に使うのは新しいサンプルなので、処理が詰まったら古いものから捨てる
        let (stream, continuation) = AsyncStream.makeStream(of: MotionSample.self, bufferingPolicy: .bufferingNewest(256))
        guard manager.isDeviceMotionAvailable else {
            status = .unsupported
            continuation.finish()
            return stream
        }
        // 受け取る側が列を捨てた・タスクを中止したときも、取得を止める
        continuation.onTermination = Self.terminationHandler(for: self, session: session)
        self.continuation = continuation
        // 権限を尋ねるのは取得を始めたとき
        manager.startDeviceMotionUpdates(
            to: queue,
            withHandler: Self.motionHandler(for: self, session: session, continuation: continuation)
        )
        return stream
    }

    /// 動きの取得を止める。接続状態の監視は続けるので、接続の状態は保つ
    func stop() {
        manager.stopDeviceMotionUpdates()
        let continuation = continuation
        self.continuation = nil
        continuation?.finish()
        refreshStatus()
    }

    private func connectionChanged(_ isConnected: Bool) {
        self.isConnected = isConnected
        refreshStatus()
    }

    /// 動きが届いたなら、許可されていてイヤホンもつながっている（接続の通知が届かない場合に備える）
    private func firstSampleReceived(session: Int) {
        guard session == self.session, continuation != nil else { return }
        isConnected = true
        refreshStatus()
    }

    /// 列が終わった（受け取る側が捨てた・エラーで終えた）。今の回の列なら取得を止める
    private func streamTerminated(session: Int) {
        guard session == self.session, continuation != nil else {
            refreshStatus()
            return
        }
        stop()
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
        session: Int,
        continuation: AsyncStream<MotionSample>.Continuation
    ) -> CMHeadphoneMotionManager.DeviceMotionHandler {
        let hasReceived = OSAllocatedUnfairLock(initialState: false)
        return { [weak input] motion, error in
            // 権限が無い・取り消されたときなどはエラーで届く。列を終えると、終わりの処理で取得も止まる
            if error != nil {
                continuation.finish()
                return
            }
            guard let motion else { return }
            continuation.yield(MotionSample(
                headphoneTimestamp: motion.timestamp,
                rotationRate: motion.rotationRate,
                attitude: motion.attitude
            ))
            let isFirst = hasReceived.withLock { received in
                defer { received = true }
                return !received
            }
            if isFirst {
                Task { @MainActor [input] in input?.firstSampleReceived(session: session) }
            }
        }
    }

    nonisolated private static func terminationHandler(
        for input: HeadphoneMotionInput,
        session: Int
    ) -> @Sendable (AsyncStream<MotionSample>.Continuation.Termination) -> Void {
        { [weak input] _ in
            Task { @MainActor [input] in input?.streamTerminated(session: session) }
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
    /// z 軸まわり = 首振り（左を向くと正）なので、右を向く向きを正にするため z の符号を反転する。姿勢（`CMAttitude`）も同じ向きにそろえる
    nonisolated init(headphoneTimestamp: TimeInterval, rotationRate: CMRotationRate, attitude: CMAttitude? = nil) {
        self.init(
            timestamp: headphoneTimestamp,
            yawRate: -rotationRate.z,
            pitchRate: rotationRate.x,
            orientation: attitude.map { HeadOrientation(yaw: -$0.yaw, pitch: $0.pitch) }
        )
    }
}
#endif
