import CoreGraphics
import Foundation
import os

/// 譜面 ZIP に画像が無いときに、beatsaver のジャケット画像を取りに行く。
/// 譜面 ZIP の画像と同じく、受け取る量を上限で打ち切り、形式・ピクセル数を確かめて縮小してから使う（`CoverImage`）
nonisolated struct CoverImageLoader: Sendable {
    private let session: URLSession
    private let userAgent: String
    /// 受け取る量の上限
    private let maxBytes: Int

    init(
        session: URLSession = .shared,
        userAgent: String = BeatsaverAPIClient.defaultUserAgent,
        maxBytes: Int = CoverImage.maxBytes
    ) {
        self.session = session
        self.userAgent = userAgent
        self.maxBytes = maxBytes
    }

    /// 取れない・上限を超える・画像として読めないときは nil（画像が無くても遊べるので、エラーにしない）
    @concurrent
    func load(_ url: URL) async -> CGImage? {
        guard BeatsaverHost.isTrusted(url) else { return nil }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let delegate = CoverTaskDelegate(maxBytes: maxBytes)
        let data = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                delegate.start(session: session, request: request, continuation: continuation)
            }
        } onCancel: {
            delegate.cancel()
        }
        guard let data else { return nil }
        return CoverImage.decode(data)
    }
}

/// 受信した塊をメモリにためる。応答が不正なとき・上限を超えたとき・beatsaver の外へ転送されそうなときは打ち切る
///
/// `URLSession.bytes(for:)` は 1 バイトずつ読むので遅い。`data(for:)` は受け取り終わるまで量を確かめられないので、データタスクの delegate で受ける
nonisolated private final class CoverTaskDelegate: NSObject, URLSessionDataDelegate, Sendable {
    private struct State {
        var task: URLSessionDataTask?
        var continuation: CheckedContinuation<Data?, Never>?
        var data = Data()
        var failed = false
        var isCancelled = false
    }

    private let maxBytes: Int
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(maxBytes: Int) {
        self.maxBytes = maxBytes
    }

    func start(session: URLSession, request: URLRequest, continuation: CheckedContinuation<Data?, Never>) {
        let task = session.dataTask(with: request)
        task.delegate = self
        let isCancelled = state.withLock { state in
            state.task = task
            state.continuation = continuation
            return state.isCancelled
        }
        // 開始前に中止されていたら、通信せずに終える
        if isCancelled {
            finish()
        } else {
            task.resume()
        }
    }

    func cancel() {
        let task = state.withLock { state in
            state.isCancelled = true
            return state.task
        }
        task?.cancel()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // 宣言されたサイズが上限を超えるなら、本文を受け取らずに打ち切る
        guard (200..<300).contains(status), response.expectedContentLength <= maxBytes else {
            state.withLock { $0.failed = true }
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        // 転送先も beatsaver のホストに限る。それ以外へは転送せず、転送の応答（3xx）のまま失敗させる
        guard let url = request.url, BeatsaverHost.isTrusted(url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let isOverLimit = state.withLock { state in
            state.data.append(data)
            guard state.data.count > maxBytes else { return false }
            state.failed = true
            state.data = Data()
            return true
        }
        if isOverLimit {
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if error != nil {
            state.withLock { $0.failed = true }
        }
        finish()
    }

    /// 1 度だけ結果を返す
    private func finish() {
        let (continuation, data) = state.withLock { state in
            defer { state.continuation = nil }
            let succeeded = !state.failed && !state.isCancelled
            return (state.continuation, succeeded ? state.data : nil)
        }
        continuation?.resume(returning: data)
    }
}
