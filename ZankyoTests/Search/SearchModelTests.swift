import Foundation
import Testing
@testable import Zankyo

@MainActor
struct SearchModelTests {
    @Test
    func submitLoadsFirstPage() async throws {
        let client = FakeBeatsaverClient { query, page in
            #expect(query == "believer")
            #expect(page == 0)
            return try Self.page(ids: ["1f33", "abc"], page: 0, totalPages: 3)
        }
        let model = SearchModel(client: client)
        model.query = "  believer \n"

        await model.submit()

        #expect(model.phase == .loaded)
        #expect(model.maps.map(\.id) == ["1f33", "abc"])
        #expect(model.submittedQuery == "believer")
        #expect(model.hasNextPage)
    }

    @Test
    func blankQueryDoesNotSearch() async {
        let client = FakeBeatsaverClient { _, _ in
            Issue.record("空の検索語で API を呼んではいけない")
            return BeatsaverSearchPage(maps: [], page: 0, totalPages: 0)
        }
        let model = SearchModel(client: client)
        model.query = "   "

        await model.submit()

        #expect(model.phase == .idle)
        #expect(await client.requests.isEmpty)
    }

    @Test
    func failureIsShown() async {
        let client = FakeBeatsaverClient { _, _ in throw BeatsaverClientError.transport(.notConnectedToInternet) }
        let model = SearchModel(client: client)
        model.query = "believer"

        await model.submit()

        #expect(model.phase == .failed(.transport(.notConnectedToInternet)))
        #expect(model.maps.isEmpty)
    }

    @Test
    func nextPageAppendsWithoutDuplicates() async throws {
        let client = FakeBeatsaverClient { _, page in
            switch page {
            case 0: try Self.page(ids: ["a1", "a2"], page: 0, totalPages: 2)
            default: try Self.page(ids: ["a2", "a3"], page: 1, totalPages: 2)
            }
        }
        let model = SearchModel(client: client)
        model.query = "believer"
        await model.submit()

        await model.loadNextPage()

        #expect(model.maps.map(\.id) == ["a1", "a2", "a3"])
        #expect(!model.hasNextPage)
        #expect(await client.requests.map(\.page) == [0, 1])
    }

    @Test
    func nextPageFailureKeepsShownResults() async throws {
        let client = FakeBeatsaverClient { _, page in
            guard page == 0 else { throw BeatsaverClientError.httpStatus(503) }
            return try Self.page(ids: ["a1"], page: 0, totalPages: 2)
        }
        let model = SearchModel(client: client)
        model.query = "believer"
        await model.submit()

        await model.loadNextPage()

        #expect(model.phase == .loaded)
        #expect(model.maps.map(\.id) == ["a1"])
        #expect(model.nextPageError == .httpStatus(503))
        #expect(model.hasNextPage)
        #expect(!model.isLoadingNextPage)
    }

    @Test
    func newSearchIgnoresResultOfOlderSearch() async throws {
        let gate = AsyncGate()
        let client = FakeBeatsaverClient { query, _ in
            if query == "old" {
                await gate.wait()
                return try Self.page(ids: ["0ld"], page: 0, totalPages: 1)
            }
            return try Self.page(ids: ["eee"], page: 0, totalPages: 1)
        }
        let model = SearchModel(client: client)
        model.query = "old"
        let oldSearch = Task { await model.submit() }
        while await client.requests.isEmpty {
            await Task.yield()
        }

        model.query = "new"
        await model.submit()
        await gate.open()
        await oldSearch.value

        #expect(model.submittedQuery == "new")
        #expect(model.maps.map(\.id) == ["eee"])
    }

    @Test
    func doesNotLoadPastLastPage() async throws {
        let client = FakeBeatsaverClient { _, _ in try Self.page(ids: ["a1"], page: 0, totalPages: 1) }
        let model = SearchModel(client: client)
        model.query = "believer"
        await model.submit()

        await model.loadNextPage()

        #expect(await client.requests.map(\.page) == [0])
    }

    nonisolated private static func page(ids: [String], page: Int, totalPages: Int) throws -> BeatsaverSearchPage {
        let maps = try ids.map { id in
            try JSONDecoder().decode(BeatsaverMap.self, from: Data(BeatsaverFixtures.map(id: id).utf8))
        }
        return BeatsaverSearchPage(maps: maps, page: page, totalPages: totalPages)
    }
}

/// 検索の応答を差し替えられる `BeatsaverClient`
private actor FakeBeatsaverClient: BeatsaverClient {
    typealias SearchHandler = @Sendable (_ query: String, _ page: Int) async throws -> BeatsaverSearchPage

    private(set) var requests: [(query: String, page: Int)] = []
    private let handler: SearchHandler

    init(search handler: @escaping SearchHandler) {
        self.handler = handler
    }

    func search(query: String, page: Int) async throws(BeatsaverClientError) -> BeatsaverSearchPage {
        requests.append((query, page))
        do {
            return try await handler(query, page)
        } catch let error as BeatsaverClientError {
            throw error
        } catch {
            throw .invalidResponse
        }
    }

    func map(id: String) async throws(BeatsaverClientError) -> BeatsaverMap {
        throw .notFound
    }

    func map(hash: String) async throws(BeatsaverClientError) -> BeatsaverMap {
        throw .notFound
    }
}

/// `open()` が呼ばれるまで `wait()` を待たせる
private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
