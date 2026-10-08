import Foundation
import Testing
@testable import Zankyo

struct SongDetailModelTests {
    @Test
    func togglesPreviewOfSong() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model
        await model.load()

        await model.togglePreview()

        // 試聴区間（12.5 秒から 10 秒）は 0.5 秒の曲に収まらないので、頭から全体を鳴らす
        #expect(model.isPreviewing)
        #expect(fixture.previewer.played.count == 1)
        let range = try #require(fixture.previewer.played.first)
        #expect(range.lowerBound == 0)
        #expect(abs(range.upperBound - 0.5) < 0.01)

        await model.togglePreview()

        #expect(!model.isPreviewing)
        #expect(!fixture.previewer.isPlaying)
    }

    @Test
    func startingPlayStopsPreview() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model
        await model.load()
        await model.togglePreview()
        let easy = try #require(model.info?.difficulties.first { $0.difficulty == .easy })

        await model.prepare(easy)

        #expect(model.play != nil)
        #expect(!model.isPreviewing)
        #expect(!fixture.previewer.isPlaying)
    }

    @Test
    func failedPreparationCancelsPendingPreview() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model
        await model.load()
        // Expert+ の譜面ファイルは ZIP に入っていないので、遊ぶ準備は失敗する
        let expertPlus = try #require(model.info?.difficulties.first { $0.difficulty == .expertPlus })

        // 試聴のデコードを待っている間に「スタート」を押し、準備が失敗した
        let preview = Task { await model.togglePreview() }
        for _ in 0..<1_000 where !model.isLoadingPreview {
            await Task.yield()
        }
        try #require(model.isLoadingPreview)
        await model.prepare(expertPlus)
        await preview.value

        #expect(model.playError != nil)
        #expect(!model.isPreviewing)
        #expect(fixture.previewer.played.isEmpty)
    }

    @Test
    func stalePreviewFailureIsNotReported() async throws {
        // 音源が壊れていてデコードに失敗する譜面
        let fixture = try Fixture(song: Data("not ogg".utf8))
        defer { fixture.remove() }
        let model = fixture.model
        await model.load()
        let easy = try #require(model.info?.difficulties.first { $0.difficulty == .easy })

        // 試聴のデコードを待っている間に遊ぶ準備を始め、その準備は画面を離れて取り消された
        let preview = Task { await model.togglePreview() }
        for _ in 0..<1_000 where !model.isLoadingPreview {
            await Task.yield()
        }
        try #require(model.isLoadingPreview)
        let preparation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await model.prepare(easy)
        }
        await preparation.value
        await preview.value

        // 止められた試聴のデコードの失敗は知らせない
        #expect(model.playError == nil)
        #expect(fixture.previewer.played.isEmpty)
    }

    @Test
    func previewDoesNotStartAfterCancellation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model
        await model.load()

        // デコードを待つ間に画面を離れた（タスクを取り消した）
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await model.togglePreview()
        }
        await task.value

        #expect(!model.isPreviewing)
        #expect(fixture.previewer.played.isEmpty)
    }
}

/// 0.5 秒の曲（sine.egg）の譜面を取り込んだ状態のモデル。試聴は鳴らさずに記録する
private struct Fixture {
    static let hash = String(repeating: "cd", count: 20)
    static let easy = """
        { "_version": "2.0.0", "_notes": [
          { "_time": 2, "_lineIndex": 0, "_lineLayer": 0, "_type": 0, "_cutDirection": 2 },
          { "_time": 4, "_lineIndex": 3, "_lineLayer": 0, "_type": 1, "_cutDirection": 1 }
        ] }
        """

    let model: SongDetailModel
    let entry: LibraryEntry
    /// アプリ全体の試聴（画面を移っても鳴り続ける）
    let preview: SongPreviewCenter
    let previewer = RecordingPreviewer()
    private let root: URL

    /// - Parameter song: 音源のファイルの中身。nil なら 0.5 秒のサイン波
    init(song: Data? = nil) throws {
        root = try TestFixtures.temporaryDirectory()
        let store = LocalMapStore(
            downloadsDirectory: root.appending(path: "Downloads", directoryHint: .isDirectory),
            mapsDirectory: root.appending(path: "Maps", directoryHint: .isDirectory)
        )
        try FileManager.default.createDirectory(at: store.downloadsDirectory, withIntermediateDirectories: true)
        let zip = TestZip.make([
            (name: "Info.dat", data: Data(InfoFixtures.v2().utf8)),
            (name: "EasyStandard.dat", data: Data(Self.easy.utf8)),
            (name: "song.egg", data: try song ?? Data(contentsOf: try TestFixtures.sineSong))
        ])
        try zip.write(to: store.downloadsDirectory.appending(path: "\(Self.hash).zip"))

        let json = """
            {"hash":"\(Self.hash)","mapID":"1f33","name":"Test Map","songName":"Test Song","songSubName":"",
             "songAuthorName":"Zankyo Band","mapperName":"Shilokuma","importedAt":"2026-10-07T12:00:00Z"}
            """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(LibraryEntry.self, from: Data(json.utf8))
        preview = SongPreviewCenter(previewer: previewer, maps: store)
        self.entry = entry
        model = SongDetailModel(entry: entry, maps: store, preview: preview)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

/// 鳴らさずに、鳴らそうとした区間を記録する
private final class RecordingPreviewer: SongPreviewing {
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
