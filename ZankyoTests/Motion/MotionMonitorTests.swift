import Foundation
import Testing
@testable import Zankyo

@MainActor
struct MotionMonitorTests {
    @Test
    func forwardsSamplesAndUpdatesState() async {
        let base = ManualMotionInput()
        let monitor = MotionMonitor(base: base, now: { 100 })
        let stream = monitor.start()
        let sample = MotionSample(timestamp: 1, yawRate: 3, pitchRate: 0, orientation: HeadOrientation(yaw: 0.2, pitch: 0))
        base.send(sample)
        base.finish()

        var received: [MotionSample] = []
        for await value in stream {
            received.append(value)
        }

        // 判定に使うサンプルは手を加えずに渡す
        #expect(received == [sample])
        #expect(monitor.state.strength == 1.5)
        #expect(monitor.lastReceivedAt == 100)
    }

    @Test
    func stopFinishesStreamAndStopsBase() async {
        let base = ManualMotionInput()
        let monitor = MotionMonitor(base: base)
        let stream = monitor.start()

        monitor.stop()

        for await _ in stream {}
        #expect(base.stopCount >= 1)
        #expect(!monitor.isActive)
    }

    @Test
    func previewStartsOnlyWhenIdleAndReady() {
        let base = ManualMotionInput(status: .notDetermined)
        let monitor = MotionMonitor(base: base)

        // 許可を尋ねる前は、見せるためだけに取得しない
        monitor.startPreview()
        #expect(!monitor.isActive)

        base.status = .ready
        monitor.startPreview()
        #expect(monitor.isActive)
        #expect(base.startCount == 1)
    }

    @Test
    func stopPreviewKeepsConsumerRunning() {
        let base = ManualMotionInput()
        let monitor = MotionMonitor(base: base)
        monitor.startPreview()

        // ゲームなどが始めたら、プレビューは終わる。プレビューの画面が消えても、ゲームの取得は止めない
        _ = monitor.start()
        monitor.stopPreview()

        #expect(monitor.isActive)
        #expect(base.startCount == 2)
    }
}

/// テストから状態を変え、サンプルを流せる入力
@MainActor
private final class ManualMotionInput: MotionInput {
    var status: MotionInputStatus
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var continuation: AsyncStream<MotionSample>.Continuation?

    init(status: MotionInputStatus = .ready) {
        self.status = status
    }

    func start() -> AsyncStream<MotionSample> {
        startCount += 1
        let (stream, continuation) = AsyncStream.makeStream(of: MotionSample.self)
        self.continuation = continuation
        return stream
    }

    func stop() {
        stopCount += 1
        continuation?.finish()
        continuation = nil
    }

    func send(_ sample: MotionSample) {
        continuation?.yield(sample)
    }

    func finish() {
        continuation?.finish()
    }
}
