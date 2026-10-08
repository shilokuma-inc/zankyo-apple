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
    private static let expertV5 = #"{ "version": "5.0.0", "colorNotes": [], "colorNotesData": [] }"#

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

        await #expect(throws: MapLoadError.unsupportedBeatmap("5.0.0")) {
            try await store.loadNotes(hash: Self.hash, info: info, difficulty: expert)
        }
    }

    @Test
    func usesAudioDataTimelineForV4Map() async throws {
        let info = InfoFixtures.v4
            .replacingOccurrences(of: "song.ogg", with: "song.egg")
            .replacingOccurrences(of: "\"bpm\": 140", with: "\"bpm\": 60")
        // 0.5 秒の位置から 120 BPM（44.1kHz で 22,050 サンプル目が拍 0）
        let audioData = #"{ "version": "4.0.0", "songFrequency": 44100, "bpmData": [{ "si": 22050, "ei": 66150, "sb": 0, "eb": 2 }] }"#
        let beatmap = #"{ "version": "4.1.0", "colorNotes": [{ "b": 2 }], "colorNotesData": [{ "d": 3 }] }"#
        let store = try Self.makeStore(files: [
            (name: "Info.dat", data: Data(info.utf8)),
            (name: "BPMInfo.dat", data: Data(audioData.utf8)),
            (name: "NormalStandard.dat", data: Data(beatmap.utf8)),
            (name: "song.egg", data: try Data(contentsOf: try TestFixtures.sineSong))
        ])
        defer { try? FileManager.default.removeItem(at: store.downloadsDirectory.deletingLastPathComponent()) }
        let loaded = try await store.loadInfo(hash: Self.hash)
        let normal = try #require(loaded.difficulties.first { $0.difficulty == .normal })

        let notes = try await store.loadNotes(hash: Self.hash, info: loaded, difficulty: normal)

        // Info.dat の 60 BPM なら 2 秒だが、音声データの区間に従って 1.5 秒になる
        #expect(notes.map(\.time) == [1.5])
        #expect(notes.map(\.direction) == [.right])
    }

    @Test
    func readsLightshowForV4Map() async throws {
        let info = InfoFixtures.v4.replacingOccurrences(of: "song.ogg", with: "song.egg")
        let beatmap = #"{ "version": "4.1.0", "colorNotes": [{ "b": 2 }], "colorNotesData": [{ "d": 3 }] }"#
        let lightshow = #"{ "version": "4.0.0", "basicEvents": [{ "b": 1, "i": 0 }], "basicEventsData": [{ "t": 2, "i": 6 }] }"#
        let store = try Self.makeStore(files: [
            (name: "Info.dat", data: Data(info.utf8)),
            (name: "NormalStandard.dat", data: Data(beatmap.utf8)),
            (name: "Lightshow.dat", data: Data(lightshow.utf8)),
            (name: "song.egg", data: try Data(contentsOf: try TestFixtures.sineSong))
        ])
        defer { try? FileManager.default.removeItem(at: store.downloadsDirectory.deletingLastPathComponent()) }
        let loaded = try await store.loadInfo(hash: Self.hash)
        let normal = try #require(loaded.difficulties.first { $0.difficulty == .normal })
        #expect(normal.lightshowFilename == "Lightshow.dat")

        let chart = try await store.loadChart(hash: Self.hash, info: loaded, difficulty: normal)

        // 140 BPM なので拍 1 は 60 / 140 秒
        #expect(chart.notes.count == 1)
        #expect(chart.lighting.events.map(\.group) == [.leftLasers])
        #expect(abs((chart.lighting.events.first?.time ?? 0) - 60.0 / 140) < 0.0001)
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

    @Test
    func loadsCoverDownscaled() async throws {
        let store = try Self.makeStore(files: [
            (name: "Info.dat", data: Data(InfoFixtures.v2(coverFilename: "cover.png").utf8)),
            (name: "cover.png", data: try TestImage.make(width: 1024, height: 1024))
        ])
        defer { try? FileManager.default.removeItem(at: store.downloadsDirectory.deletingLastPathComponent()) }
        let info = try await store.loadInfo(hash: Self.hash)

        let cover = try #require(await store.loadCover(hash: Self.hash, info: info))

        #expect(cover.width == CoverImage.maxPixelSize)
        #expect(cover.height == CoverImage.maxPixelSize)
    }

    @Test
    func coverIsNilWhenMapHasNoImage() async throws {
        // Info.dat は cover.jpg を指すが、ZIP に入っていない
        let store = try Self.makeStore()
        defer { try? FileManager.default.removeItem(at: store.downloadsDirectory.deletingLastPathComponent()) }
        let info = try await store.loadInfo(hash: Self.hash)

        #expect(await store.loadCover(hash: Self.hash, info: info) == nil)
    }

    @Test
    func loadsListCoverFromZipWithoutExtracting() async throws {
        let store = try Self.makeStore(files: [
            (name: "Info.dat", data: Data(InfoFixtures.v2(coverFilename: "cover.png").utf8)),
            (name: "cover.png", data: try TestImage.make(width: 1024, height: 1024))
        ])
        defer { try? FileManager.default.removeItem(at: store.downloadsDirectory.deletingLastPathComponent()) }

        let cover = try #require(await store.loadListCover(hash: Self.hash))

        #expect(cover.width == CoverImage.maxPixelSize)
        // 一覧のためだけに展開しない
        #expect(!FileManager.default.fileExists(atPath: store.mapsDirectory.appending(path: Self.hash).path(percentEncoded: false)))
    }

    @Test
    func loadsListCoverFromExtractedFolder() async throws {
        let store = try Self.makeStore(files: [
            (name: "Info.dat", data: Data(InfoFixtures.v2(coverFilename: "cover.png").utf8)),
            (name: "cover.png", data: try TestImage.make(width: 64, height: 64))
        ])
        defer { try? FileManager.default.removeItem(at: store.downloadsDirectory.deletingLastPathComponent()) }
        _ = try await store.loadInfo(hash: Self.hash)
        // 展開済みなら ZIP が無くても読める
        try FileManager.default.removeItem(at: store.downloadsDirectory.appending(path: "\(Self.hash).zip"))

        let cover = try #require(await store.loadListCover(hash: Self.hash))

        #expect(cover.width == 64)
    }

    @Test
    func listCoverIsNilWhenMapHasNoImageOrIsMissing() async throws {
        // Info.dat は cover.jpg を指すが、ZIP に入っていない
        let store = try Self.makeStore()
        defer { try? FileManager.default.removeItem(at: store.downloadsDirectory.deletingLastPathComponent()) }

        #expect(await store.loadListCover(hash: Self.hash) == nil)
        #expect(await store.loadListCover(hash: String(repeating: "cd", count: 20)) == nil)
        #expect(await store.loadListCover(hash: "../\(Self.hash)") == nil)
    }

    private static func makeStore(files: [(name: String, data: Data)]) throws -> LocalMapStore {
        let store = try makeStore(writeZip: false)
        try TestZip.make(files).write(to: store.downloadsDirectory.appending(path: "\(hash).zip"))
        return store
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
                (name: "ExpertStandard.dat", data: Data(expertV5.utf8)),
                (name: "song.egg", data: try Data(contentsOf: try TestFixtures.sineSong))
            ])
            try zip.write(to: store.downloadsDirectory.appending(path: "\(hash).zip"))
        }
        return store
    }
}
