import Foundation
import Testing
@testable import Zankyo

/// 同梱したサンプル楽曲が、取り込んだ曲と同じ道筋でそのまま遊べること
struct SampleSongCatalogTests {
    @Test
    func listsBundledSongs() {
        let catalog = SampleSongCatalog()

        #expect(catalog.version >= 1)
        #expect(catalog.songs.count == 8)
        #expect(Set(catalog.songs.map(\.id)).count == catalog.songs.count)
        #expect(Set(catalog.songs.map(\.hash)).count == catalog.songs.count)
    }

    @Test
    func missingCatalogIsEmpty() throws {
        // 一覧の無いバンドル（テストのバンドル）では、サンプル楽曲なしで動く
        let catalog = SampleSongCatalog(bundle: Bundle(for: BundleToken.self))

        #expect(catalog.version == 0)
        #expect(catalog.songs.isEmpty)
    }

    @Test(arguments: SampleSongCatalog().songs)
    func bundledSongIsPlayable(song: SampleSong) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "SampleSongTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let downloads = root.appending(path: "Downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let zip = downloads.appending(path: "\(song.hash).zip")
        try FileManager.default.copyItem(at: song.archive, to: zip)

        // 一覧のハッシュが、譜面の中身から beatsaver と同じ方式で計算したものと合う
        #expect(try MapHash.compute(zipAt: zip) == song.hash)

        let maps = LocalMapStore(downloadsDirectory: downloads, mapsDirectory: root.appending(path: "Maps"))
        let info = try await maps.loadInfo(hash: song.hash)
        #expect(info.title == song.songName)
        #expect(info.difficulties.map(\.difficulty) == [.easy, .normal, .hard])
        #expect(info.difficulties.allSatisfy { $0.characteristic == .standard })

        // 易しいほどノーツが少なく、変換で間引かれない（生成時に 0.4 秒以上空けている）
        var counts: [Int] = []
        for difficulty in info.difficulties {
            let notes = try await maps.loadNotes(hash: song.hash, info: info, difficulty: difficulty)
            let raw = try BeatmapParser.parse(
                Data(contentsOf: root.appending(path: "Maps/\(song.hash)/\(difficulty.beatmapFilename.lowercased())")),
                bpm: info.bpm,
                songTimeOffset: info.songTimeOffset
            )
            #expect(notes.count == raw.notes.count)
            counts.append(notes.count)
        }
        #expect(counts == counts.sorted() && Set(counts).count == counts.count)

        let audio = try await maps.loadSong(hash: song.hash, info: info)
        #expect((50...70).contains(audio.duration))
        #expect(await maps.loadCover(hash: song.hash, info: info) != nil)
    }
}

@MainActor
struct SampleSongInstallerTests {
    @Test
    func installsOnceAndRestoresDeletedSongs() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "SampleSongInstallerTests-\(UUID().uuidString)")
        let suite = "ZankyoTests.SampleSongs.\(UUID().uuidString)"
        defer {
            try? FileManager.default.removeItem(at: root)
            UserDefaults().removePersistentDomain(forName: suite)
        }
        let downloads = root.appending(path: "Downloads")
        let library = LibraryStore(
            directory: root.appending(path: "Library"),
            downloadsDirectory: downloads,
            mapsDirectory: root.appending(path: "Maps")
        )
        let catalog = SampleSongCatalog()
        let installer = SampleSongInstaller(catalog: catalog, downloadsDirectory: downloads, suiteName: suite)

        installer.installIfNeeded(into: library)

        // 一覧の順に並び、取り込んだ曲と同じ置き場所に ZIP がある
        #expect(library.entries.map(\.hash) == catalog.songs.map(\.hash))
        #expect(library.entries.allSatisfy { $0.isSample && $0.pageURL == nil && $0.isValid })
        for song in catalog.songs {
            #expect(FileManager.default.fileExists(atPath: downloads.appending(path: "\(song.hash).zip").path(percentEncoded: false)))
        }
        #expect(installer.missingSongs(in: library).isEmpty)

        // 消した曲は、起動し直しても（同じ版なら）入れ直さない
        let deleted = try #require(library.entries.dropFirst().first)
        #expect(library.delete(deleted))
        installer.installIfNeeded(into: library)
        #expect(installer.missingSongs(in: library).map(\.hash) == [deleted.hash])

        // 戻すと、元の位置に入る
        installer.restore(into: library)
        #expect(library.entries.map(\.hash) == catalog.songs.map(\.hash))
    }

    @Test
    func samplesStayBelowImportedSongs() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "SampleSongInstallerTests-\(UUID().uuidString)")
        let suite = "ZankyoTests.SampleSongs.\(UUID().uuidString)"
        defer {
            try? FileManager.default.removeItem(at: root)
            UserDefaults().removePersistentDomain(forName: suite)
        }
        let downloads = root.appending(path: "Downloads")
        let library = LibraryStore(
            directory: root.appending(path: "Library"),
            downloadsDirectory: downloads,
            mapsDirectory: root.appending(path: "Maps")
        )
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        try Data([1]).write(to: downloads.appending(path: "\(BeatsaverFixtures.hash).zip"))
        let map = try JSONDecoder().decode(BeatsaverMap.self, from: Data(BeatsaverFixtures.map(id: "1f33").utf8))
        library.add(map: map, version: try #require(map.latestVersion))

        SampleSongInstaller(downloadsDirectory: downloads, suiteName: suite).installIfNeeded(into: library)

        #expect(library.entries.first?.hash == BeatsaverFixtures.hash)
        #expect(library.entries.dropFirst().allSatisfy { $0.isSample })
    }
}

struct LibraryEntryTests {
    @Test
    func decodesEntryWrittenBeforeSamples() throws {
        // サンプル楽曲より前の一覧には isSample が無い
        let json = """
        { "hash": "\(BeatsaverFixtures.hash)", "mapID": "1f33", "name": "Map", "songName": "Song", "songSubName": "",
          "songAuthorName": "Artist", "mapperName": "Mapper", "importedAt": 1000 }
        """
        let entry = try JSONDecoder().decode(LibraryEntry.self, from: Data(json.utf8))

        #expect(!entry.isSample)
        #expect(entry.pageURL?.absoluteString == "https://beatsaver.com/maps/1f33")
    }
}

private final class BundleToken {}
