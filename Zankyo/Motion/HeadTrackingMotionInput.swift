#if os(visionOS)
import ARKit
import Observation
import QuartzCore
import RealityKit
import SwiftUI

/// visionOS の頭の向き（ARKit の `WorldTrackingProvider`）からの入力（Discussion #3 Q7）
///
/// ARKit はイマーシブ空間の中でしか動かないので、`HeadTrackingSpace` を開いたときに `activate()` する
@Observable
final class HeadTrackingMotionInput: MotionInput {
    /// 姿勢を問い合わせる間隔（秒）。画面の更新（90Hz）に近い頻度で角速度を求める
    private static let pollInterval: Duration = .milliseconds(11)

    private(set) var status: MotionInputStatus

    @ObservationIgnored private let session = ARKitSession()
    @ObservationIgnored private let provider = WorldTrackingProvider()
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var continuation: AsyncStream<MotionSample>.Continuation?

    init() {
        status = WorldTrackingProvider.isSupported ? .disconnected : .unsupported
    }

    /// イマーシブ空間を開いたら呼ぶ。頭の向きの追跡を始める
    func activate() async {
        guard WorldTrackingProvider.isSupported, !isRunning else { return }
        do {
            try await session.run([provider])
            isRunning = true
            status = .ready
        } catch {
            status = .notAuthorized
        }
    }

    /// イマーシブ空間を閉じたら呼ぶ
    func deactivate() {
        stop()
        session.stop()
        isRunning = false
        status = WorldTrackingProvider.isSupported ? .disconnected : .unsupported
    }

    func start() -> AsyncStream<MotionSample> {
        stop()
        let (stream, continuation) = AsyncStream.makeStream(of: MotionSample.self, bufferingPolicy: .bufferingNewest(256))
        guard isRunning else {
            continuation.finish()
            return stream
        }
        self.continuation = continuation
        task = Task { [provider] in
            var tracker = HeadRateTracker()
            while !Task.isCancelled {
                // CACurrentMediaTime はモーションのサンプルと同じ「起動からの秒」
                let now = CACurrentMediaTime()
                if let anchor = provider.queryDeviceAnchor(atTimestamp: now), anchor.isTracked {
                    if let sample = tracker.update(timestamp: now, transform: anchor.originFromAnchorTransform) {
                        continuation.yield(sample)
                    }
                } else {
                    // 追跡が途切れたら、途切れる前の姿勢とつなげない
                    tracker.reset()
                }
                try? await Task.sleep(for: Self.pollInterval)
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
}

/// 頭の向きを取るためだけに開くイマーシブ空間。何も表示しない
enum HeadTrackingSpace {
    static let id = "head-tracking"
}

struct HeadTrackingSpaceView: View {
    let input: HeadTrackingMotionInput?

    var body: some View {
        RealityView { _ in }
            .task { await input?.activate() }
            .onDisappear { input?.deactivate() }
    }
}

/// ウィンドウを出したら、頭の向きを取るためのイマーシブ空間を開く
struct OpensHeadTrackingSpace: ViewModifier {
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    func body(content: Content) -> some View {
        content.task {
            _ = await openImmersiveSpace(id: HeadTrackingSpace.id)
        }
    }
}
#endif
