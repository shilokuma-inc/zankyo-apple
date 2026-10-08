import Foundation
import Testing
@testable import Zankyo

/// アプリ全体の試聴。一覧からも曲の詳細からも始め・止められ、画面を移っても鳴り続ける
struct SongPreviewCenterTests {
    @Test
    func togglesPreviewFromList() async throws {
        let fixture = try PreviewFixture()
        defer { fixture.remove() }
        let center = fixture.center

        center.toggle(fixture.first)
        #expect(center.isLoading(fixture.first.hash))
        try await fixture.waitUntil { center.isPlaying(fixture.first.hash) }
        #expect(!center.isLoading(fixture.first.hash))
        #expect(fixture.previewer.played.count == 1)

        // 同じ曲をもう一度押すと止める
        center.toggle(fixture.first)
        #expect(center.playingHash == nil)
        #expect(!fixture.previewer.isPlaying)
    }

    @Test
    func previewingAnotherSongStopsThePrevious() async throws {
        let fixture = try PreviewFixture()
        defer { fixture.remove() }
        let center = fixture.center
        center.toggle(fixture.first)
        try await fixture.waitUntil { center.isPlaying(fixture.first.hash) }

        center.toggle(fixture.second)
        // 読んでいる間は前の曲を鳴らさない（同時に鳴らすのは 1 曲）
        #expect(!center.isPlaying(fixture.first.hash))
        #expect(!fixture.previewer.isPlaying)
        try await fixture.waitUntil { center.isPlaying(fixture.second.hash) }
        #expect(fixture.previewer.played.count == 2)
    }

    @Test
    func pressingSongsQuicklyPlaysOnlyTheLast() async throws {
        let fixture = try PreviewFixture()
        defer { fixture.remove() }
        let center = fixture.center

        // 1 曲目を読み終える前に 2 曲目を押す。1 曲目は鳴らさず、2 曲目だけを鳴らす
        center.toggle(fixture.first)
        center.toggle(fixture.second)
        #expect(center.isLoading(fixture.second.hash))
        try await fixture.waitUntil { center.isPlaying(fixture.second.hash) }

        #expect(fixture.previewer.played.count == 1)
    }

    @Test
    func stoppingWhileLoadingDoesNotPlay() async throws {
        let fixture = try PreviewFixture()
        defer { fixture.remove() }
        let center = fixture.center

        center.toggle(fixture.first)
        center.stop()
        try await Task.sleep(for: .milliseconds(500))

        #expect(center.playingHash == nil)
        #expect(center.loadingHash == nil)
        #expect(fixture.previewer.played.isEmpty)
    }

    @Test
    func reportsSongThatCannotBePlayed() async throws {
        let fixture = try PreviewFixture(song: Data("not ogg".utf8))
        defer { fixture.remove() }
        let center = fixture.center

        center.toggle(fixture.first)
        try await fixture.waitUntil { center.error != nil }

        #expect(center.playingHash == nil)
        #expect(center.loadingHash == nil)
    }

    @Test
    func previewFromDetailKeepsPlayingAfterLeaving() async throws {
        let fixture = try PreviewFixture()
        defer { fixture.remove() }
        let center = fixture.center
        var model: SongDetailModel? = SongDetailModel(entry: fixture.first, maps: fixture.maps, preview: center)
        await model?.load()
        await model?.togglePreview()
        #expect(model?.isPreviewing == true)

        // 曲の詳細の画面を閉じて（モデルが無くなって）も鳴り続け、一覧で同じ曲が試聴中と分かる
        model = nil
        #expect(center.isPlaying(fixture.first.hash))
        #expect(fixture.previewer.isPlaying)
    }

    @Test
    func detailShowsPreviewStartedFromList() async throws {
        let fixture = try PreviewFixture()
        defer { fixture.remove() }
        let center = fixture.center
        center.toggle(fixture.first)
        try await fixture.waitUntil { center.isPlaying(fixture.first.hash) }

        let model = SongDetailModel(entry: fixture.first, maps: fixture.maps, preview: center)
        #expect(model.isPreviewing)

        // 曲の詳細で止められる
        await model.togglePreview()
        #expect(!model.isPreviewing)
        #expect(center.playingHash == nil)
    }

    @Test
    func startingPlayStopsPreviewOfAnotherSong() async throws {
        let fixture = try PreviewFixture()
        defer { fixture.remove() }
        let center = fixture.center
        center.toggle(fixture.second)
        try await fixture.waitUntil { center.isPlaying(fixture.second.hash) }
        let model = SongDetailModel(entry: fixture.first, maps: fixture.maps, preview: center)
        await model.load()
        let easy = try #require(model.info?.difficulties.first { $0.difficulty == .easy })

        await model.prepare(easy)

        #expect(model.play != nil)
        #expect(center.playingHash == nil)
        #expect(!fixture.previewer.isPlaying)
    }
}

/// 0.5 秒の曲（sine.egg）の譜面を 2 曲取り込んだ状態。試聴は鳴らさずに記録する
private struct PreviewFixture {
    static let easy = """
        { "_version": "2.0.0", "_notes": [
          { "_time": 2, "_lineIndex": 0, "_lineLayer": 0, "_type": 0, "_cutDirection": 2 }
        ] }
        """

    let maps: LocalMapStore
    let center: SongPreviewCenter
    let previewer = PreviewRecorder()
    let first: LibraryEntry
    let second: LibraryEntry
    private let root: URL

    /// - Parameter song: 音源のファイルの中身。nil なら 0.5 秒のサイン波
    init(song: Data? = nil) throws {
        root = try TestFixtures.temporaryDirectory()
        maps = LocalMapStore(
            downloadsDirectory: root.appending(path: "Downloads", directoryHint: .isDirectory),
            mapsDirectory: root.appending(path: "Maps", directoryHint: .isDirectory)
        )
        try FileManager.default.createDirectory(at: maps.downloadsDirectory, withIntermediateDirectories: true)
        let zip = TestZip.make([
            (name: "Info.dat", data: Data(InfoFixtures.v2().utf8)),
            (name: "EasyStandard.dat", data: Data(Self.easy.utf8)),
            (name: "song.egg", data: try song ?? Data(contentsOf: try TestFixtures.sineSong))
        ])
        first = try Self.entry(hash: String(repeating: "ab", count: 20))
        second = try Self.entry(hash: String(repeating: "ef", count: 20))
        for entry in [first, second] {
            try zip.write(to: maps.downloadsDirectory.appending(path: "\(entry.hash).zip"))
        }
        center = SongPreviewCenter(previewer: previewer, maps: maps)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    /// 条件を満たすまで待つ（読み込みとデコードはメインスレッドの外で進む）
    func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition())
    }

    private static func entry(hash: String) throws -> LibraryEntry {
        let json = """
            {"hash":"\(hash)","mapID":"1f33","name":"Test Map","songName":"Test Song","songSubName":"",
             "songAuthorName":"Zankyo Band","mapperName":"Shilokuma","importedAt":"2026-10-07T12:00:00Z"}
            """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LibraryEntry.self, from: Data(json.utf8))
    }
}

/// 鳴らさずに、鳴らそうとした区間を記録する
private final class PreviewRecorder: SongPreviewing {
    private(set) var isPlaying = false
    private(set) var played: [Range<TimeInterval>] = []

    func play(_ song: DecodedSong, range: Range<TimeInterval>) throws {
        played.append(range)
        isPlaying = true
    }

    func stop() {
        isPlaying = false
    }
}
