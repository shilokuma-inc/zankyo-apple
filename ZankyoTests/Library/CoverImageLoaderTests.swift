import Foundation
import Testing
@testable import Zankyo

nonisolated struct CoverImageLoaderTests {
    private static let url = URL(string: "https://cdn.beatsaver.com/abcdef.jpg")!  // swiftlint:disable:this force_unwrapping

    @Test
    func loadsAndDownscalesCover() async throws {
        let body = try TestImage.make(width: 1024, height: 1024)
        let loader = CoverImageLoader(session: StubURLProtocol.makeSession { try Self.response($0, body: body) })

        let image = try #require(await loader.load(Self.url))

        #expect(image.width == CoverImage.maxPixelSize)
    }

    @Test
    func ignoresUntrustedHost() async throws {
        let body = try TestImage.make(width: 16, height: 16)
        let loader = CoverImageLoader(session: StubURLProtocol.makeSession { try Self.response($0, body: body) })

        #expect(await loader.load(try #require(URL(string: "https://evil.example.com/a.png"))) == nil)
        #expect(await loader.load(try #require(URL(string: "http://cdn.beatsaver.com/a.png"))) == nil)
    }

    @Test
    func failsOnErrorStatus() async throws {
        let body = try TestImage.make(width: 16, height: 16)
        let loader = CoverImageLoader(session: StubURLProtocol.makeSession { try Self.response($0, body: body, status: 404) })

        #expect(await loader.load(Self.url) == nil)
    }

    @Test
    func stopsWhenDeclaredSizeIsTooLarge() async throws {
        let body = try TestImage.make(width: 16, height: 16)
        let loader = CoverImageLoader(session: StubURLProtocol.makeSession {
            try Self.response($0, body: body, headers: ["Content-Length": "\(CoverImage.maxBytes + 1)"])
        })

        #expect(await loader.load(Self.url) == nil)
    }

    @Test
    func stopsWhenBodyExceedsLimit() async throws {
        // 大きさを宣言しない応答でも、受け取った量が上限を超えたら打ち切る
        let body = try TestImage.make(width: 64, height: 64)
        let session = StubURLProtocol.makeSession { try Self.response($0, body: body) }

        #expect(await CoverImageLoader(session: session, maxBytes: body.count - 1).load(Self.url) == nil)
        #expect(await CoverImageLoader(session: session, maxBytes: body.count).load(Self.url) != nil)
    }

    private static func response(
        _ request: URLRequest,
        body: Data,
        status: Int = 200,
        headers: [String: String]? = nil
    ) throws -> (HTTPURLResponse, Data) {
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers))
        return (response, body)
    }
}
