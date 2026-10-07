import Foundation

/// 端末に合ったモーション入力を作る
enum MotionInputFactory {
    static func makeDefault() -> any MotionInput {
        #if os(visionOS)
        HeadTrackingMotionInput()
        #else
        HeadphoneMotionInput()
        #endif
    }
}

/// 使えるモーション入力が無い端末向け。常に `unsupported` で、何も流さない
final class UnavailableMotionInput: MotionInput {
    let status: MotionInputStatus = .unsupported

    func start() -> AsyncStream<MotionSample> {
        AsyncStream { $0.finish() }
    }

    func stop() {}
}
