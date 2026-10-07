import Foundation
import Testing
@testable import Zankyo

nonisolated struct LocalMapStoreTests {
    private static let hash = String(repeating: "ab", count: 20)
    private static let beatmaps = [
        InfoFixtures.v2Beatmap("Easy", "EasyStandard.dat"),
        InfoFixtures.v2Beatmap("Expert", "ExpertStandard.dat")
    ]
    private static let info = InfoFixtures.v2(
        bpm: "120",
        sets: #"[{ "_beatmapCharacteristicName": "Standard", "_difficultyBeatmaps": [\#(beatmaps.joined(separator: ","))] }]"#
    )
    private static let easy = """
        { "_version": "2.0.0", "_notes": [
          { "_time": 2, "_lineIndex": 0, "_lineLayer": 0, "_type": 0, "_cutDirection": 2 },
          { "_time": 4, "_lineIndex": 3, "_lineLayer": 0, "_type": 1, "_cutDirection": 1 }
        ] }
        """
    private static let expertV4 = #"{ "version": "4.1.0", "colorNotes": [], "colorNotesData": [] }"#

    @Test
    func extractsOnFirstLoadAndReadsInfo() async throws {
        let store = try Self.makeStore()
        defer { try? FileManager.default.removeItem(at: store.downloadsDirectory.deletingLastPathComponent()) }

        let info = try await store.loadInfo(hash: Self.hash)

        #expect(info.title == "Test Song")
        #expect(info.difficulties.map(\.difficulty) == [.easy, .expert])
        let folder = store.mapsDirectory.appending(path: Self.hash)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "info.dat").path(percentEncoded: false)))
    }

    @Test
    func loadsNotesInSongSeconds() async throws {
        let store = try Self.makeStore()
        defer { try? FileManager.default.removeItem(at: store.downloadsDirectory.deletingLastPathComponent()) }
        let info = try await store.loadInfo(hash: Self.hash)
        let easy = try #require(info.difficulties.first { $0.difficulty == .easy })

        let notes = try await store.loadNotes(hash: Self.hash, info: info, difficulty: easy)

        // 120 BPM・`_songTimeOffset` 0.25 秒なので、拍 2 は 1.25 秒
        #expect(notes.map(\.time) == [1.25, 2.25])
        #expect(notes.map(\.direction) == [.left, .down])
    }

    @Test
    func reportsUnsupportedBeatmapVersion() async throws {
        let store = try Self.makeStore()
        defer { try? FileManager.default.removeItem(at: store.downloadsDirectory.deletingLastPathComponent()) }
        let info = try await store.loadInfo(hash: Self.hash)
        let expert = try #require(info.difficulties.first { $0.difficulty == .expert })

        await #expect(throws: MapLoadError.unsupportedBeatmap("4.1.0")) {
            try await store.loadNotes(hash: Self.hash, info: info, difficulty: expert)
        }
    }

    @Test
    func decodesSong() async throws {
        let store = try Self.makeStore()
        defer { try? FileManager.default.removeItem(at: store.downloadsDirectory.deletingLastPathComponent()) }
        let info = try await store.loadInfo(hash: Self.hash)

        let song = try await store.loadSong(hash: Self.hash, info: info)

        #expect(song.frameCount == 22_050)
    }

    @Test
    func reportsMapWithoutPlayableDifficulty() async throws {
        let beatmap = InfoFixtures.v2Beatmap("Easy", "Easy.dat")
        let lightshowOnly = InfoFixtures.v2(sets: #"[{ "_beatmapCharacteristicName": "Lightshow", "_difficultyBeatmaps": [\#(beatmap)] }]"#)
        let store = try Self.makeStore(info: lightshowOnly)
        defer { try? FileManager.default.removeItem(at: store.downloadsDirectory.deletingLastPathComponent()) }

        await #expect(throws: MapLoadError.noPlayableDifficulty) {
            try await store.loadInfo(hash: Self.hash)
        }
    }

    @Test
    func reportsMissingDownload() async throws {
        let store = try Self.makeStore(writeZip: false)
        defer { try? FileManager.default.removeItem(at: store.downloadsDirectory.deletingLastPathComponent()) }

        await #expect(throws: MapLoadError.notDownloaded) {
            try await store.loadInfo(hash: Self.hash)
        }
        await #expect(throws: MapLoadError.notDownloaded) {
            try await store.loadInfo(hash: "../../etc")
        }
    }

    private static func makeStore(writeZip: Bool = true, info: String = info) throws -> LocalMapStore {
        let root = try TestFixtures.temporaryDirectory()
        let store = LocalMapStore(
            downloadsDirectory: root.appending(path: "Downloads", directoryHint: .isDirectory),
            mapsDirectory: root.appending(path: "Maps", directoryHint: .isDirectory)
        )
        try FileManager.default.createDirectory(at: store.downloadsDirectory, withIntermediateDirectories: true)
        if writeZip {
            let zip = TestZip.make([
                (name: "Info.dat", data: Data(info.utf8)),
                (name: "EasyStandard.dat", data: Data(easy.utf8)),
                (name: "ExpertStandard.dat", data: Data(expertV4.utf8)),
                (name: "song.egg", data: try Data(contentsOf: try TestFixtures.sineSong))
            ])
            try zip.write(to: store.downloadsDirectory.appending(path: "\(hash).zip"))
        }
        return store
    }
}
