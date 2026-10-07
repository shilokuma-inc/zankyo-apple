import CryptoKit
import Foundation
import os
import Testing
@testable import Zankyo

nonisolated struct MapDownloaderTests {
    private static let info = Data(
        #"{"_version":"2.0.0","_difficultyBeatmapSets":[{"_difficultyBeatmaps":[{"_beatmapFilename":"Easy.dat"}]}]}"#.utf8
    )
    private static let beatmap = Data("easy".utf8)
    /// 譜面として読める最小の ZIP
    private static let body = TestZip.make([("Info.dat", info), ("Easy.dat", beatmap)])
    /// `body` の譜面ハッシュ（ZIP 全体の SHA-1 ではない）
    private static let mapHash = sha1(info + beatmap)

    @Test
    func savesZipNamedByHash() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let hash = Self.mapHash
        let captured = OSAllocatedUnfairLock<URLRequest?>(initialState: nil)
        let session = StubURLProtocol.makeSession { request in
            captured.withLock { $0 = request }
            return try Self.response(request, body: Self.body)
        }
        let downloader = MapDownloader(session: session, directory: directory, userAgent: "Zankyo/1.0 (test)")
        let progress = OSAllocatedUnfairLock<[Double]>(initialState: [])

        let file = try await downloader.download(try Self.version(hash: hash)) { value in
            progress.withLock { $0.append(value) }
        }

        #expect(file == directory.appending(path: "\(hash).zip"))
        #expect(try Data(contentsOf: file) == Self.body)
        #expect(downloader.downloadedFile(hash: hash) == file)
        #expect(progress.withLock { $0.last } == 1)
        let request = try #require(captured.withLock { $0 })
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Zankyo/1.0 (test)")
        #expect(request.url?.host == "r2cdn.beatsaver.com")
    }

    @Test
    func rejectsHashMismatch() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let hash = String(repeating: "0", count: 40)
        let session = StubURLProtocol.makeSession { try Self.response($0, body: Self.body) }
        let downloader = MapDownloader(session: session, directory: directory)

        await #expect(throws: MapDownloadError.hashMismatch) {
            try await downloader.download(try Self.version(hash: hash)) { _ in }
        }
        #expect(downloader.downloadedFile(hash: hash) == nil)
    }

    @Test
    func rejectsZipWithoutBeatmaps() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // ZIP の署名はあっても、Info.dat が無いものは保存しない
        let body = TestZip.make([("readme.txt", Data("hello".utf8))])
        let hash = Self.mapHash
        let session = StubURLProtocol.makeSession { try Self.response($0, body: body) }
        let downloader = MapDownloader(session: session, directory: directory)

        await #expect(throws: MapDownloadError.invalidMap) {
            try await downloader.download(try Self.version(hash: hash)) { _ in }
        }
        #expect(downloader.downloadedFile(hash: hash) == nil)
    }

    @Test
    func rejectsNonZipBody() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // ハッシュが一致しても、ZIP の署名が無いものは保存しない
        let body = Data("<html>not found</html>".utf8)
        let hash = Self.sha1(body)
        let session = StubURLProtocol.makeSession { try Self.response($0, body: body) }
        let downloader = MapDownloader(session: session, directory: directory)

        await #expect(throws: MapDownloadError.notZip) {
            try await downloader.download(try Self.version(hash: hash)) { _ in }
        }
        #expect(downloader.downloadedFile(hash: hash) == nil)
    }

    @Test
    func rejectsOversizedZip() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let body = Data(repeating: 0x50, count: 2_048)
        let hash = Self.sha1(body)
        let session = StubURLProtocol.makeSession { try Self.response($0, body: body) }
        let downloader = MapDownloader(session: session, directory: directory, maxBytes: 1_024)

        await #expect(throws: MapDownloadError.tooLarge) {
            try await downloader.download(try Self.version(hash: hash)) { _ in }
        }
        #expect(downloader.downloadedFile(hash: hash) == nil)
    }

    @Test
    func rejectsDeclaredOversizedZip() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let hash = Self.sha1(Self.body)
        let session = StubURLProtocol.makeSession { request in
            try Self.response(request, body: Self.body, headers: ["Content-Length": "4096"])
        }
        let downloader = MapDownloader(session: session, directory: directory, maxBytes: 1_024)

        await #expect(throws: MapDownloadError.tooLarge) {
            try await downloader.download(try Self.version(hash: hash)) { _ in }
        }
    }

    @Test
    func reportsHTTPStatus() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = StubURLProtocol.makeSession { try Self.response($0, body: Data(), status: 404) }
        let downloader = MapDownloader(session: session, directory: directory)

        await #expect(throws: MapDownloadError.httpStatus(404)) {
            try await downloader.download(try Self.version(hash: Self.sha1(Data()))) { _ in }
        }
    }

    @Test
    func reportsTransportError() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = StubURLProtocol.makeSession { _ in throw URLError(.notConnectedToInternet) }
        let downloader = MapDownloader(session: session, directory: directory)

        await #expect(throws: MapDownloadError.transport(.notConnectedToInternet)) {
            try await downloader.download(try Self.version(hash: Self.sha1(Self.body))) { _ in }
        }
    }

    @Test
    func cancelledBeforeStartDoesNotRequest() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let requested = OSAllocatedUnfairLock(initialState: false)
        let session = StubURLProtocol.makeSession { request in
            requested.withLock { $0 = true }
            return try Self.response(request, body: Self.body)
        }
        let downloader = MapDownloader(session: session, directory: directory)
        let version = try Self.version(hash: Self.mapHash)

        // 取得を始める前に中止されたタスク
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await downloader.download(version) { _ in }
        }

        await #expect(throws: MapDownloadError.cancelled) {
            try await task.value
        }
        #expect(!requested.withLock { $0 })
        #expect(downloader.downloadedFile(hash: Self.mapHash) == nil)
    }

    @Test
    func downloadedFileRejectsInvalidHash() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let downloader = MapDownloader(directory: directory)

        #expect(downloader.downloadedFile(hash: "../../etc/passwd") == nil)
        #expect(downloader.downloadedFile(hash: String(repeating: "a", count: 40)) == nil)
    }

    // MARK: - 補助

    static func version(hash: String) throws -> BeatsaverMapVersion {
        let json = BeatsaverFixtures.map(id: "1f33", versions: "[\(BeatsaverFixtures.version(hash: hash))]")
        let map = try JSONDecoder().decode(BeatsaverMap.self, from: Data(json.utf8))
        return try #require(map.latestVersion)
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

    private static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ZankyoTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func sha1(_ data: Data) -> String {
        Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
