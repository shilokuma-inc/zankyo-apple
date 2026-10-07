import Foundation
import Testing
@testable import Zankyo

struct LibraryStoreTests {
    private static let hash = BeatsaverFixtures.hash

    @Test
    func addsEntryWithSizeAndPersists() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeFiles(root: root, zipBytes: 4_096, mapFileBytes: 1_024)
        let store = Self.store(root: root)
        let importedAt = Date(timeIntervalSince1970: 1_800_000_000)

        try store.add(map: Self.map(id: "1f33"), version: Self.version(), importedAt: importedAt)

        let entry = try #require(store.entries.first)
        #expect(entry.hash == Self.hash)
        #expect(entry.mapID == "1f33")
        #expect(entry.pageURL.absoluteString == "https://beatsaver.com/maps/1f33")
        #expect(store.sizes[Self.hash] ?? 0 >= 5_120)
        #expect(store.totalSize == store.sizes[Self.hash])

        let reloaded = Self.store(root: root)
        #expect(reloaded.entries == [entry])
        #expect(reloaded.sizes[Self.hash] == store.sizes[Self.hash])
    }

    @Test
    func addingSameMapAgainReplacesEntry() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeFiles(root: root, zipBytes: 10, mapFileBytes: nil)
        let store = Self.store(root: root)

        try store.add(map: Self.map(id: "1f33"), version: Self.version(), importedAt: Date(timeIntervalSince1970: 1))
        try store.add(map: Self.map(id: "1f33"), version: Self.version(), importedAt: Date(timeIntervalSince1970: 2))

        #expect(store.entries.count == 1)
        #expect(store.entries.first?.importedAt == Date(timeIntervalSince1970: 2))
    }

    @Test
    func deleteRemovesZipFolderAndEntry() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeFiles(root: root, zipBytes: 10, mapFileBytes: 10)
        let store = Self.store(root: root)
        try store.add(map: Self.map(id: "1f33"), version: Self.version())

        store.delete(try #require(store.entries.first))

        #expect(store.entries.isEmpty)
        #expect(store.totalSize == 0)
        #expect(!FileManager.default.fileExists(atPath: Self.zip(root: root).path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: Self.mapFolder(root: root).path(percentEncoded: false)))
        #expect(Self.store(root: root).entries.isEmpty)
    }

    @Test
    func keepsEntryWhenFilesCannotBeRemoved() throws {
        let root = try Self.makeRoot()
        let maps = root.appending(path: "Maps")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: maps.path(percentEncoded: false))
            try? FileManager.default.removeItem(at: root)
        }
        try Self.writeFiles(root: root, zipBytes: 10, mapFileBytes: 10)
        let store = Self.store(root: root)
        try store.add(map: Self.map(id: "1f33"), version: Self.version())
        // 展開したフォルダの親を書き込み不可にして、消せない状態を作る
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: maps.path(percentEncoded: false))

        let deleted = store.delete(try #require(store.entries.first))

        #expect(!deleted)
        #expect(store.entries.count == 1)
        #expect(Self.store(root: root).entries.count == 1)
    }

    @Test
    func treatsAlreadyMissingFilesAsDeleted() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeFiles(root: root, zipBytes: 10, mapFileBytes: nil)
        let store = Self.store(root: root)
        try store.add(map: Self.map(id: "1f33"), version: Self.version())
        try FileManager.default.removeItem(at: Self.zip(root: root))

        #expect(store.delete(try #require(store.entries.first)))
        #expect(store.entries.isEmpty)
    }

    @Test
    func dropsEntriesWhoseFilesAreGone() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeFiles(root: root, zipBytes: 10, mapFileBytes: nil)
        try Self.store(root: root).add(map: Self.map(id: "1f33"), version: Self.version())
        try FileManager.default.removeItem(at: Self.zip(root: root))

        #expect(Self.store(root: root).entries.isEmpty)
    }

    @Test
    func dropsTamperedEntries() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeFiles(root: root, zipBytes: 10, mapFileBytes: nil)
        // ハッシュに見せかけたパスや、beatsaver 以外のジャケットの URL を持つ行は使わない
        let json = """
        { "version": 1, "entries": [
          \(Self.entryJSON(hash: "../../etc", mapID: "1f33", cover: nil)),
          \(Self.entryJSON(hash: Self.hash, mapID: "1f33", cover: "https://evil.example.com/a.jpg")),
          \(Self.entryJSON(hash: Self.hash, mapID: "1f33", cover: "https://cdn.beatsaver.com/a.jpg"))
        ] }
        """
        try Data(json.utf8).write(to: Self.index(root: root))

        let store = Self.store(root: root)

        #expect(store.entries.count == 1)
        #expect(store.entries.first?.coverURL?.host == "cdn.beatsaver.com")
    }

    @Test
    func movesBrokenIndexAsideAndKeepsNewerFormat() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeFiles(root: root, zipBytes: 10, mapFileBytes: nil)

        try Data("not json".utf8).write(to: Self.index(root: root))
        #expect(Self.store(root: root).entries.isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "Library").path(percentEncoded: false))
        #expect(names.contains { $0.hasPrefix("Library.json.broken-") })

        let newer = Data(#"{ "version": 2, "entries": [{ "unknown": true }] }"#.utf8)
        try newer.write(to: Self.index(root: root))
        let store = Self.store(root: root)
        try store.add(map: Self.map(id: "1f33"), version: Self.version())
        #expect(store.isReadOnly)
        #expect(try Data(contentsOf: Self.index(root: root)) == newer)

        // 一覧を書けないときは、ファイルだけを消して一覧と食い違わせない
        let deleted = store.delete(try #require(store.entries.first))
        #expect(!deleted)
        #expect(FileManager.default.fileExists(atPath: Self.zip(root: root).path(percentEncoded: false)))
    }

    // MARK: - 補助

    private static func store(root: URL) -> LibraryStore {
        LibraryStore(
            directory: root.appending(path: "Library"),
            downloadsDirectory: root.appending(path: "Downloads"),
            mapsDirectory: root.appending(path: "Maps")
        )
    }

    private static func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "ZankyoTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root.appending(path: "Library"), withIntermediateDirectories: true)
        return root
    }

    private static func zip(root: URL) -> URL {
        root.appending(path: "Downloads/\(hash).zip")
    }

    private static func mapFolder(root: URL) -> URL {
        root.appending(path: "Maps/\(hash)", directoryHint: .isDirectory)
    }

    private static func index(root: URL) -> URL {
        root.appending(path: "Library/Library.json")
    }

    /// 自作の小さなファイル（中身は検証しないので任意のバイト列）
    private static func writeFiles(root: URL, zipBytes: Int, mapFileBytes: Int?) throws {
        try FileManager.default.createDirectory(at: root.appending(path: "Downloads"), withIntermediateDirectories: true)
        try Data(repeating: 0x50, count: zipBytes).write(to: zip(root: root))
        if let mapFileBytes {
            try FileManager.default.createDirectory(at: mapFolder(root: root), withIntermediateDirectories: true)
            try Data(repeating: 0x7B, count: mapFileBytes).write(to: mapFolder(root: root).appending(path: "Info.dat"))
        }
    }

    private static func map(id: String) throws -> BeatsaverMap {
        try JSONDecoder().decode(BeatsaverMap.self, from: Data(BeatsaverFixtures.map(id: id).utf8))
    }

    private static func version() throws -> BeatsaverMapVersion {
        try #require(try map(id: "1f33").latestVersion)
    }

    private static func entryJSON(hash: String, mapID: String, cover: String?) -> String {
        let coverValue = cover.map { "\"\($0)\"" } ?? "null"
        return """
        { "hash": "\(hash)", "mapID": "\(mapID)", "name": "Map", "songName": "Song", "songSubName": "", "songAuthorName": "Band",
          "mapperName": "Mapper", "coverURL": \(coverValue), "importedAt": "2027-01-15T08:00:00Z" }
        """
    }
}
