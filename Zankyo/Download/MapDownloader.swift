import CryptoKit
import Foundation
import os

/// 譜面 ZIP を取得して、アプリ専用のディレクトリに保存する。画面やテストからはこのプロトコル越しに使う
nonisolated protocol MapDownloading: Sendable {
    /// `version` の ZIP を取得し、保存したファイルの場所を返す。`progress` には 0〜1 の進み具合を渡す
    func download(
        _ version: BeatsaverMapVersion,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws(MapDownloadError) -> URL
    /// 取得済みの ZIP の場所。無ければ nil
    func downloadedFile(hash: String) -> URL?
}

nonisolated enum MapDownloadError: Error, Equatable, Sendable {
    /// beatsaver 以外のホストを指す URL（取得していない）
    case untrustedURL
    /// ZIP がサイズの上限を超えた（途中で打ち切った）
    case tooLarge
    /// 2xx 以外の応答
    case httpStatus(Int)
    /// 取得した ZIP のハッシュが API の値と一致しない（壊れた・すり替えられた）
    case hashMismatch
    /// 中止した
    case cancelled
    /// 通信エラー（オフラインなど）
    case transport(URLError.Code)
    /// 保存に失敗した（空き容量不足など）
    case storage
}

/// アプリが読み書きするディレクトリ。すべて Application Support 配下のアプリ専用の場所に置く
nonisolated enum AppDirectories {
    /// 取得した譜面 ZIP（展開前）の置き場所
    static var downloads: URL {
        URL.applicationSupportDirectory.appending(path: "Zankyo/Downloads", directoryHint: .isDirectory)
    }
}

/// beatsaver の CDN から ZIP を取得する実装
nonisolated struct MapDownloader: MapDownloading {
    /// ZIP の上限。beatsaver の譜面 ZIP は数 MB〜十数 MB が多いので、十分な余裕を持たせる
    static let maxBytes: Int64 = 50 * 1_024 * 1_024

    private let session: URLSession
    private let directory: URL
    private let maxBytes: Int64
    private let userAgent: String

    init(
        session: URLSession = .shared,
        directory: URL = AppDirectories.downloads,
        maxBytes: Int64 = Self.maxBytes,
        userAgent: String = BeatsaverAPIClient.defaultUserAgent
    ) {
        self.session = session
        self.directory = directory
        self.maxBytes = maxBytes
        self.userAgent = userAgent
    }

    func downloadedFile(hash: String) -> URL? {
        guard BeatsaverValidation.isValidHash(hash) else { return nil }
        let file = fileURL(hash: hash)
        return FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) ? file : nil
    }

    func download(
        _ version: BeatsaverMapVersion,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws(MapDownloadError) -> URL {
        guard BeatsaverHost.isTrusted(version.downloadURL), BeatsaverValidation.isValidHash(version.hash) else {
            throw .untrustedURL
        }
        let temporary = try await fetch(version.downloadURL, progress: progress)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let size = (try? temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? .max
        guard size <= maxBytes else { throw .tooLarge }
        guard try Self.sha1(of: temporary) == version.hash.lowercased() else { throw .hashMismatch }

        let destination = fileURL(hash: version.hash)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: temporary, to: destination)
        } catch {
            throw .storage
        }
        progress(1)
        return destination
    }

    /// 一時ファイルに取得する。上限を超えたら打ち切る
    private func fetch(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws(MapDownloadError) -> URL {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let temporary = FileManager.default.temporaryDirectory
            .appending(path: "zankyo-download-\(UUID().uuidString).zip", directoryHint: .notDirectory)
        guard FileManager.default.createFile(atPath: temporary.path(percentEncoded: false), contents: nil),
              let handle = try? FileHandle(forWritingTo: temporary) else {
            throw .storage
        }
        let delegate = DownloadTaskDelegate(handle: handle, maxBytes: maxBytes, progress: progress)
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                delegate.start(session: session, request: request, continuation: continuation)
            }
        } onCancel: {
            delegate.cancel()
        }
        do {
            try result.get()
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        return temporary
    }

    private func fileURL(hash: String) -> URL {
        // hash は 16 進数 40 桁に検証済みなので、パスの区切りや `..` は入らない
        directory.appending(path: "\(hash.lowercased()).zip", directoryHint: .notDirectory)
    }

    /// ファイルの SHA-1（beatsaver の `hash` と同じ形式の小文字 16 進数）
    private static func sha1(of file: URL) throws(MapDownloadError) -> String {
        guard let handle = try? FileHandle(forReadingFrom: file) else { throw .storage }
        defer { try? handle.close() }
        var hasher = Insecure.SHA1()
        while true {
            let chunk: Data?
            do {
                chunk = try handle.read(upToCount: 1_024 * 1_024)
            } catch {
                throw .storage
            }
            // 末尾に達すると空の Data ではなく nil が返る
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// 受信した塊ごとにファイルへ書き、進み具合を伝える。応答が不正なときや上限を超えたときは打ち切る
///
/// `URLSession.bytes(for:)` は 1 バイトずつ読むので数十 MB では遅すぎる。
/// `download(for:delegate:)` は途中で打ち切るための受信量を task delegate に渡さないので、データタスクの delegate で受ける
nonisolated private final class DownloadTaskDelegate: NSObject, URLSessionDataDelegate, Sendable {
    private struct State {
        var task: URLSessionDataTask?
        var continuation: CheckedContinuation<Result<Void, MapDownloadError>, Never>?
        var received: Int64 = 0
        var expected: Int64 = 0
        /// 自分で打ち切った理由（通信エラーより優先して返す）
        var failure: MapDownloadError?
        var isCancelled = false
    }

    private let handle: FileHandle
    private let maxBytes: Int64
    private let progress: @Sendable (Double) -> Void
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(handle: FileHandle, maxBytes: Int64, progress: @escaping @Sendable (Double) -> Void) {
        self.handle = handle
        self.maxBytes = maxBytes
        self.progress = progress
    }

    func start(
        session: URLSession,
        request: URLRequest,
        continuation: CheckedContinuation<Result<Void, MapDownloadError>, Never>
    ) {
        let task = session.dataTask(with: request)
        task.delegate = self
        let isCancelled = state.withLock { state in
            state.task = task
            state.continuation = continuation
            return state.isCancelled
        }
        // 開始前に中止されていたら、通信せずに終える
        if isCancelled {
            finish(.failure(.cancelled))
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
        guard (200..<300).contains(status) else {
            fail(.httpStatus(status))
            completionHandler(.cancel)
            return
        }
        // 宣言されたサイズが上限を超えるなら、本文を受け取らずに打ち切る
        guard response.expectedContentLength <= maxBytes else {
            fail(.tooLarge)
            completionHandler(.cancel)
            return
        }
        state.withLock { $0.expected = max(response.expectedContentLength, 0) }
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        // CDN の転送先も beatsaver のホストに限る。それ以外へは転送せず、転送の応答（3xx）のまま失敗させる
        guard let url = request.url, BeatsaverHost.isTrusted(url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let (received, expected) = state.withLock { state in
            state.received += Int64(data.count)
            return (state.received, state.expected)
        }
        guard received <= maxBytes else {
            fail(.tooLarge)
            dataTask.cancel()
            return
        }
        do {
            try handle.write(contentsOf: data)
        } catch {
            fail(.storage)
            dataTask.cancel()
            return
        }
        if expected > 0 {
            progress(min(Double(received) / Double(expected), 1))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let (failure, isCancelled) = state.withLock { ($0.failure, $0.isCancelled) }
        if let failure {
            finish(.failure(failure))
        } else if isCancelled {
            finish(.failure(.cancelled))
        } else if let error = error as? URLError {
            finish(.failure(error.code == .cancelled ? .cancelled : .transport(error.code)))
        } else if error != nil {
            finish(.failure(.transport(.unknown)))
        } else {
            finish(.success(()))
        }
    }

    private func fail(_ error: MapDownloadError) {
        state.withLock { state in
            if state.failure == nil {
                state.failure = error
            }
        }
    }

    /// 1 度だけ結果を返す
    private func finish(_ result: Result<Void, MapDownloadError>) {
        try? handle.close()
        let continuation = state.withLock { state in
            defer { state.continuation = nil }
            return state.continuation
        }
        continuation?.resume(returning: result)
    }
}
