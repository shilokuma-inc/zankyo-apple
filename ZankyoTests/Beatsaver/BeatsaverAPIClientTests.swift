import Foundation
import os
import Testing
@testable import Zankyo

struct BeatsaverAPIClientTests {
    // MARK: - 検索

    @Test
    func searchDecodesMapsAndPaging() async throws {
        let session = StubURLProtocol.makeSession(handler: StubURLProtocol.json(BeatsaverFixtures.searchResponse(maps: [
            BeatsaverFixtures.map(id: "1f33"),
            BeatsaverFixtures.map(id: "abc")
        ], pages: 4)))
        let client = BeatsaverAPIClient(session: session)

        let page = try await client.search(query: "believer", page: 0)

        #expect(page.maps.map(\.id) == ["1f33", "abc"])
        #expect(page.totalPages == 4)
        #expect(page.hasNextPage)
        let map = try #require(page.maps.first)
        #expect(map.name == "Believer - American Authors")
        #expect(map.mapperName == "NovaShaft")
        #expect(map.pageURL.absoluteString == "https://beatsaver.com/maps/1f33")
        #expect(map.metadata.bpm == 120)
        let version = try #require(map.latestVersion)
        #expect(version.hash == BeatsaverFixtures.hash)
        #expect(version.downloadURL.host == "r2cdn.beatsaver.com")
        #expect(version.coverURL != nil)
        #expect(version.difficulties.map(\.difficulty) == ["Hard", "Expert"])
    }

    @Test
    func searchSendsQueryPageAndUserAgent() async throws {
        let captured = OSAllocatedUnfairLock<URLRequest?>(initialState: nil)
        let json = StubURLProtocol.json(BeatsaverFixtures.searchResponse(maps: [], pages: 0))
        let session = StubURLProtocol.makeSession { request in
            captured.withLock { $0 = request }
            return try json(request)
        }
        let client = BeatsaverAPIClient(session: session, userAgent: "Zankyo/1.0 (test)")

        _ = try await client.search(query: "  american authors \n", page: 2)

        let request = try #require(captured.withLock { $0 })
        let url = try #require(request.url)
        #expect(url.host == "api.beatsaver.com")
        #expect(url.path == "/search/text/2")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "q", value: "american authors")))
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Zankyo/1.0 (test)")
    }

    @Test
    func defaultUserAgentIdentifiesTheApp() {
        #expect(BeatsaverAPIClient.defaultUserAgent.hasPrefix("Zankyo/"))
        #expect(BeatsaverAPIClient.defaultUserAgent.contains("github.com/shilokuma-inc/zankyo-apple"))
    }

    @Test(arguments: ["", "   ", String(repeating: "a", count: 101)])
    func searchRejectsInvalidQueryWithoutRequest(query: String) async {
        let session = StubURLProtocol.makeSession { _ in
            Issue.record("リクエストを送ってはいけない")
            throw URLError(.badURL)
        }
        let client = BeatsaverAPIClient(session: session)

        await #expect(throws: BeatsaverClientError.invalidRequest) {
            try await client.search(query: query, page: 0)
        }
    }

    @Test(arguments: [-1, 1_000])
    func searchRejectsOutOfRangePage(page: Int) async {
        let client = BeatsaverAPIClient(session: StubURLProtocol.makeSession(handler: StubURLProtocol.json("{}")))

        await #expect(throws: BeatsaverClientError.invalidRequest) {
            try await client.search(query: "a", page: page)
        }
    }

    @Test
    func searchExcludesNSFWAndGeneratedMapsByDefault() async throws {
        let session = StubURLProtocol.makeSession(handler: StubURLProtocol.json(BeatsaverFixtures.searchResponse(maps: [
            BeatsaverFixtures.map(id: "1", extra: #""nsfw": true,"#),
            BeatsaverFixtures.map(id: "2", extra: #""automapper": true,"#),
            BeatsaverFixtures.map(id: "3", extra: #""declaredAi": "SongAndMap","#),
            BeatsaverFixtures.map(id: "4", extra: #""declaredAi": "None", "nsfw": false,"#)
        ], pages: 1)))
        let client = BeatsaverAPIClient(session: session)

        let page = try await client.search(query: "a", page: 0)

        #expect(page.maps.map(\.id) == ["4"])
        #expect(!page.hasNextPage)
    }

    @Test
    func searchKeepsExcludedMapsWhenFilterIsOff() async throws {
        let session = StubURLProtocol.makeSession(handler: StubURLProtocol.json(BeatsaverFixtures.searchResponse(maps: [
            BeatsaverFixtures.map(id: "1", extra: #""nsfw": true,"#),
            BeatsaverFixtures.map(id: "2", extra: #""automapper": true,"#)
        ], pages: 1)))
        let filter = BeatsaverContentFilter(excludesNSFW: false, excludesGenerated: false)
        let client = BeatsaverAPIClient(session: session, filter: filter)

        let page = try await client.search(query: "a", page: 0)

        #expect(page.maps.map(\.id) == ["1", "2"])
    }

    @Test
    func searchDropsBrokenMapsAndKeepsTheRest() async throws {
        let session = StubURLProtocol.makeSession(handler: StubURLProtocol.json(BeatsaverFixtures.searchResponse(maps: [
            // キーが 16 進数でない
            BeatsaverFixtures.map(id: "../x"),
            // 型が違う
            #"{"id": 12, "versions": []}"#,
            // 遊べるバージョンが無い
            #"{"id": "aa", "versions": []}"#,
            BeatsaverFixtures.map(id: "0ab1"),
            // オブジェクトでない要素では、そこで読み取りを打ち切る
            #""not a map""#
        ], pages: 1)))
        let client = BeatsaverAPIClient(session: session)

        let page = try await client.search(query: "a", page: 0)

        #expect(page.maps.map(\.id) == ["0ab1"])
    }

    // MARK: - ID / ハッシュ

    @Test
    func mapByIDRequestsLowercasedKey() async throws {
        let captured = OSAllocatedUnfairLock<URL?>(initialState: nil)
        let json = StubURLProtocol.json(BeatsaverFixtures.map(id: "1f33"))
        let session = StubURLProtocol.makeSession { request in
            captured.withLock { $0 = request.url }
            return try json(request)
        }
        let client = BeatsaverAPIClient(session: session)

        let map = try await client.map(id: "1F33")

        #expect(map.id == "1f33")
        #expect(captured.withLock { $0 }?.path == "/maps/id/1f33")
    }

    @Test
    func mapByHashRequestsHashPath() async throws {
        let captured = OSAllocatedUnfairLock<URL?>(initialState: nil)
        let json = StubURLProtocol.json(BeatsaverFixtures.map(id: "1f33"))
        let session = StubURLProtocol.makeSession { request in
            captured.withLock { $0 = request.url }
            return try json(request)
        }
        let client = BeatsaverAPIClient(session: session)

        _ = try await client.map(hash: BeatsaverFixtures.hash.uppercased())

        #expect(captured.withLock { $0 }?.path == "/maps/hash/\(BeatsaverFixtures.hash)")
    }

    @Test(arguments: ["", "../../etc", "1f33/x", "123456789", "xyz", "１ｆ３３"])
    func mapRejectsInvalidID(id: String) async {
        let client = BeatsaverAPIClient(session: StubURLProtocol.makeSession(handler: StubURLProtocol.json("{}")))

        await #expect(throws: BeatsaverClientError.invalidRequest) {
            try await client.map(id: id)
        }
    }

    @Test(arguments: ["", "abc", String(repeating: "g", count: 40), String(repeating: "a", count: 41), String(repeating: "Ａ", count: 40)])
    func mapRejectsInvalidHash(hash: String) async {
        let client = BeatsaverAPIClient(session: StubURLProtocol.makeSession(handler: StubURLProtocol.json("{}")))

        await #expect(throws: BeatsaverClientError.invalidRequest) {
            try await client.map(hash: hash)
        }
    }

    @Test
    func mapThrowsExcludedForNSFWMap() async {
        let json = StubURLProtocol.json(BeatsaverFixtures.map(id: "1f33", extra: #""nsfw": true,"#))
        let session = StubURLProtocol.makeSession(handler: json)
        let client = BeatsaverAPIClient(session: session)

        await #expect(throws: BeatsaverClientError.excluded) {
            try await client.map(id: "1f33")
        }
    }

    // MARK: - 応答のエラー

    @Test
    func notFoundStatusMapsToNotFound() async {
        let session = StubURLProtocol.makeSession(handler: StubURLProtocol.json(#"{"success": false}"#, status: 404))
        let client = BeatsaverAPIClient(session: session)

        await #expect(throws: BeatsaverClientError.notFound) {
            try await client.map(id: "1f33")
        }
    }

    @Test
    func serverErrorStatusIsReported() async {
        let session = StubURLProtocol.makeSession(handler: StubURLProtocol.json("", status: 503))
        let client = BeatsaverAPIClient(session: session)

        await #expect(throws: BeatsaverClientError.httpStatus(503)) {
            try await client.search(query: "a", page: 0)
        }
    }

    @Test
    func oversizedResponseIsRejected() async {
        let body = String(repeating: " ", count: BeatsaverAPIClient.maxResponseBytes + 1)
        let session = StubURLProtocol.makeSession(handler: StubURLProtocol.json(body))
        let client = BeatsaverAPIClient(session: session)

        await #expect(throws: BeatsaverClientError.responseTooLarge) {
            try await client.search(query: "a", page: 0)
        }
    }

    @Test
    func declaredOversizedResponseIsRejectedBeforeReading() async {
        let session = StubURLProtocol.makeSession { request in
            let url = try #require(request.url)
            let headers = ["Content-Length": String(BeatsaverAPIClient.maxResponseBytes + 1)]
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers))
            return (response, Data("{}".utf8))
        }
        let client = BeatsaverAPIClient(session: session)

        await #expect(throws: BeatsaverClientError.responseTooLarge) {
            try await client.search(query: "a", page: 0)
        }
    }

    @Test
    func malformedJSONIsInvalidResponse() async {
        let session = StubURLProtocol.makeSession(handler: StubURLProtocol.json("{not json"))
        let client = BeatsaverAPIClient(session: session)

        await #expect(throws: BeatsaverClientError.invalidResponse) {
            try await client.map(id: "1f33")
        }
    }

    @Test
    func transportErrorIsReported() async {
        let session = StubURLProtocol.makeSession { _ in throw URLError(.notConnectedToInternet) }
        let client = BeatsaverAPIClient(session: session)

        await #expect(throws: BeatsaverClientError.transport(.notConnectedToInternet)) {
            try await client.search(query: "a", page: 0)
        }
    }
}
