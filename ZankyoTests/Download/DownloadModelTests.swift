import Foundation
import os
import Testing
@testable import Zankyo

@MainActor
struct DownloadModelTests {
    @Test
    func downloadsAndMarksAsDownloaded() async throws {
        let downloader = FakeMapDownloader { _, progress in
            progress(0.5)
            return URL(filePath: "/tmp/a.zip")
        }
        let model = DownloadModel(downloader: downloader)
        let map = try Self.map(id: "1f33")
        #expect(model.state(for: map) == .notDownloaded)

        model.start(map)
        #expect(model.state(for: map) == .downloading(nil))
        #expect(model.isDownloading)
        await model.waitUntilFinished()

        #expect(model.state(for: map) == .downloaded)
        #expect(!model.isDownloading)
        #expect(downloader.requestedHashes == [BeatsaverFixtures.hash])
    }

    @Test
    func startsOnlyOneDownloadAtATime() async throws {
        let gate = DownloadGate()
        let downloader = FakeMapDownloader { _, _ in
            await gate.wait()
            return URL(filePath: "/tmp/a.zip")
        }
        let model = DownloadModel(downloader: downloader)
        let first = try Self.map(id: "aaa")
        let second = try Self.map(id: "bbb")

        model.start(first)
        model.start(second)

        #expect(model.state(for: second) == .notDownloaded)
        await gate.open()
        await model.waitUntilFinished()
        #expect(downloader.requestedHashes.count == 1)
    }

    @Test
    func failureIsShownAndCanRetry() async throws {
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        let downloader = FakeMapDownloader { _, _ in
            let attempt = attempts.withLock { value in
                value += 1
                return value
            }
            if attempt == 1 { throw MapDownloadError.hashMismatch }
            return URL(filePath: "/tmp/a.zip")
        }
        let model = DownloadModel(downloader: downloader)
        let map = try Self.map(id: "1f33")

        model.start(map)
        await model.waitUntilFinished()
        #expect(model.state(for: map) == .failed(.hashMismatch))

        model.start(map)
        await model.waitUntilFinished()
        #expect(model.state(for: map) == .downloaded)
    }

    @Test
    func cancelReturnsToNotDownloaded() async throws {
        let downloader = FakeMapDownloader { _, _ in
            try await Task.sleep(for: .seconds(60))
            return URL(filePath: "/tmp/a.zip")
        }
        let model = DownloadModel(downloader: downloader)
        let map = try Self.map(id: "1f33")

        model.start(map)
        model.cancel()
        await model.waitUntilFinished()

        #expect(model.state(for: map) == .notDownloaded)
        #expect(!model.isDownloading)
    }

    @Test
    func fileFromEarlierLaunchCountsAsDownloaded() throws {
        let downloader = FakeMapDownloader(existing: [BeatsaverFixtures.hash]) { _, _ in
            Issue.record("取得済みのものを取得し直してはいけない")
            return URL(filePath: "/tmp/a.zip")
        }
        let model = DownloadModel(downloader: downloader)

        #expect(model.state(for: try Self.map(id: "1f33")) == .downloaded)
    }

    @Test
    func addsDownloadedMapToLibraryAndForgetsDeleted() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ZankyoTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = LibraryStore(
            directory: root.appending(path: "Library"),
            downloadsDirectory: root.appending(path: "Downloads"),
            mapsDirectory: root.appending(path: "Maps")
        )
        let model = DownloadModel(downloader: FakeMapDownloader { _, _ in URL(filePath: "/tmp/a.zip") }, library: library)
        let map = try Self.map(id: "1f33")

        model.start(map)
        await model.waitUntilFinished()

        #expect(library.entries.map(\.mapID) == ["1f33"])
        #expect(library.contains(hash: BeatsaverFixtures.hash))
        let entry = try #require(library.entries.first)
        library.delete(entry)
        model.forget(hash: entry.hash)
        #expect(model.state(for: map) == .notDownloaded)
    }

    nonisolated private static func map(id: String) throws -> BeatsaverMap {
        try JSONDecoder().decode(BeatsaverMap.self, from: Data(BeatsaverFixtures.map(id: id).utf8))
    }
}

/// 取得の結果を差し替えられる `MapDownloading`
nonisolated private final class FakeMapDownloader: MapDownloading {
    typealias Handler = @Sendable (BeatsaverMapVersion, @escaping @Sendable (Double) -> Void) async throws -> URL

    private let handler: Handler
    private let existing: Set<String>
    private let requests = OSAllocatedUnfairLock<[String]>(initialState: [])

    var requestedHashes: [String] {
        requests.withLock { $0 }
    }

    init(existing: Set<String> = [], handler: @escaping Handler) {
        self.existing = existing
        self.handler = handler
    }

    func download(
        _ version: BeatsaverMapVersion,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws(MapDownloadError) -> URL {
        requests.withLock { $0.append(version.hash) }
        do {
            return try await handler(version, progress)
        } catch let error as MapDownloadError {
            throw error
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .storage
        }
    }

    func downloadedFile(hash: String) -> URL? {
        existing.contains(hash) ? URL(filePath: "/tmp/\(hash).zip") : nil
    }
}

/// `open()` が呼ばれるまで `wait()` を待たせる
private actor DownloadGate {
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
