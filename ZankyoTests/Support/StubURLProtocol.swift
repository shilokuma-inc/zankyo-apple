import Foundation
import os
import Testing

/// 実ネットワークに出ずに、決めた応答を返す URLProtocol。
///
/// テストは並行に走るので、ハンドラはセッションごとの ID（リクエストヘッダ）で引き分ける。
nonisolated final class StubURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let stubIDHeader = "X-Zankyo-Stub-ID"
    private static let handlers = OSAllocatedUnfairLock<[String: Handler]>(initialState: [:])

    /// スタブを通る URLSession を作る。`handler` はリクエストごとに呼ばれる
    static func makeSession(handler: @escaping Handler) -> URLSession {
        let id = UUID().uuidString
        handlers.withLock { $0[id] = handler }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Self.self]
        configuration.httpAdditionalHeaders = [stubIDHeader: id]
        return URLSession(configuration: configuration)
    }

    /// 決まった JSON を返すハンドラ
    static func json(_ body: String, status: Int = 200) -> Handler {
        { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
            return (response, Data(body.utf8))
        }
    }

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: Self.stubIDHeader),
              let handler = Self.handlers.withLock({ $0[id] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
