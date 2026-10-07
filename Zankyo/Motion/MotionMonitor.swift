import Foundation
import Observation

/// モーション入力を包み、流れるサンプルから画面に出す状態（`HeadMotionState`）を作る
///
/// - ゲームやキャリブレーションは、これを `MotionInput` として使う。サンプルはそのまま渡すので、判定は変わらない
/// - プレイやキャリブレーションを始める前も向きを見られるよう、受け取る側がいない間だけ自分で取得する（プレビュー）。
///   受け取る側が `start()` すると、プレビューは自然に終わる
@Observable
final class MotionMonitor: MotionInput {
    let base: any MotionInput
    private(set) var state = HeadMotionState()
    /// 最後にサンプルを受け取った、起動からの秒（届いているかの表示に使う）
    private(set) var lastReceivedAt: TimeInterval?
    /// 取得中（ゲーム・キャリブレーション・プレビューのいずれか）
    private(set) var isActive = false

    @ObservationIgnored private var continuation: AsyncStream<MotionSample>.Continuation?
    @ObservationIgnored private var forwarding: Task<Void, Never>?
    /// 取得の回ごとの番号。前の回の終わりが、今の回を止めないようにする
    @ObservationIgnored private var generation = 0
    /// プレビューの回の番号。プレビューでなければ nil
    @ObservationIgnored private var previewGeneration: Int?
    @ObservationIgnored private let now: () -> TimeInterval

    init(base: any MotionInput, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.base = base
        self.now = now
    }

    var status: MotionInputStatus { base.status }

    /// 取得中で、直近（1 秒以内）にサンプルが届いている
    func isReceiving(at time: TimeInterval) -> Bool {
        guard isActive, let lastReceivedAt else { return false }
        return time - lastReceivedAt < 1
    }

    func start() -> AsyncStream<MotionSample> {
        stop()
        generation += 1
        let current = generation
        state.reset()
        lastReceivedAt = nil
        let source = base.start()
        let (stream, continuation) = AsyncStream.makeStream(of: MotionSample.self, bufferingPolicy: .bufferingNewest(256))
        // 受け取る側が列を捨てた・タスクを中止したときも、取得を止める
        continuation.onTermination = Self.terminationHandler(for: self, generation: current)
        self.continuation = continuation
        isActive = true
        forwarding = Task { [weak self] in
            for await sample in source {
                continuation.yield(sample)
                self?.receive(sample)
            }
            continuation.finish()
        }
        return stream
    }

    func stop() {
        forwarding?.cancel()
        forwarding = nil
        let continuation = continuation
        self.continuation = nil
        previewGeneration = nil
        isActive = false
        continuation?.finish()
        base.stop()
    }

    /// 受け取る側がいなければ、向きを見せるためだけに取得を始める。権限を尋ねる前（`notDetermined`）は始めない
    func startPreview() {
        guard continuation == nil, status == .ready || status == .disconnected else { return }
        let stream = start()
        previewGeneration = generation
        Task {
            for await _ in stream {}
        }
    }

    /// プレビュー中なら止める。ゲームなどが取得しているときは止めない
    func stopPreview() {
        guard let previewGeneration, previewGeneration == generation else { return }
        stop()
    }

    /// 次のサンプルの向きを正面にする
    func recenter() {
        state.recenter()
    }

    private func receive(_ sample: MotionSample) {
        state.update(with: sample)
        lastReceivedAt = now()
    }

    private func terminated(generation: Int) {
        guard generation == self.generation, continuation != nil else { return }
        stop()
    }

    nonisolated private static func terminationHandler(
        for monitor: MotionMonitor,
        generation: Int
    ) -> @Sendable (AsyncStream<MotionSample>.Continuation.Termination) -> Void {
        { [weak monitor] _ in
            Task { @MainActor [monitor] in monitor?.terminated(generation: generation) }
        }
    }
}
