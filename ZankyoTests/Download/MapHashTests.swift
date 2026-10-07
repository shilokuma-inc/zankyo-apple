import Foundation
import Testing
@testable import Zankyo

nonisolated struct MapHashTests {
    private static let infoV2 = Data("""
        {"_version":"2.1.0","_difficultyBeatmapSets":[
          {"_difficultyBeatmaps":[{"_beatmapFilename":"Easy.dat"},{"_beatmapFilename":"Hard.dat"}]},
          {"_difficultyBeatmaps":[{"_beatmapFilename":"OneSaberExpert.dat"}]}
        ]}
        """.utf8)
    private static let infoV4 = Data("""
        {"version":"4.0.1","audio":{"songFilename":"song.egg","audioDataFilename":"AudioData.dat"},
         "difficultyBeatmaps":[
           {"beatmapDataFilename":"Easy.dat","lightshowDataFilename":"Lightshow.dat"},
           {"beatmapDataFilename":"Hard.dat","lightshowDataFilename":"Lightshow.dat"}
         ]}
        """.utf8)

    @Test
    func hashesInfoAndBeatmapsInOrderForV2() throws {
        let easy = Data("easy".utf8)
        let hard = Data("hard".utf8)
        let oneSaber = Data("one saber".utf8)
        // 音源・カバー画像はハッシュに含めない
        let zip = try Self.write([
            ("song.egg", Data("audio".utf8)),
            ("Hard.dat", hard),
            ("Info.dat", Self.infoV2),
            ("OneSaberExpert.dat", oneSaber),
            ("Easy.dat", easy),
            ("cover.jpg", Data("cover".utf8))
        ])
        defer { try? FileManager.default.removeItem(at: zip) }

        let hash = try MapHash.compute(zipAt: zip)

        #expect(hash == MapDownloaderTests.sha1(Self.infoV2 + easy + hard + oneSaber))
    }

    @Test
    func hashesAudioDataAndRepeatedLightshowForV4() throws {
        let audioData = Data("audio data".utf8)
        let easy = Data("easy".utf8)
        let hard = Data("hard".utf8)
        let lightshow = Data("lightshow".utf8)
        let zip = try Self.write([
            ("Info.dat", Self.infoV4),
            ("AudioData.dat", audioData),
            ("Easy.dat", easy),
            ("Hard.dat", hard),
            ("Lightshow.dat", lightshow)
        ])
        defer { try? FileManager.default.removeItem(at: zip) }

        let hash = try MapHash.compute(zipAt: zip)

        // 同じライトショーを指す難易度が複数あれば、そのたびに足す
        #expect(hash == MapDownloaderTests.sha1(Self.infoV4 + audioData + easy + lightshow + hard + lightshow))
    }

    @Test
    func matchesFilenamesCaseInsensitively() throws {
        let info = Self.infoV2(beatmapFilename: "ExpertPlus.dat")
        let beatmap = Data("expert plus".utf8)
        let zip = try Self.write([("info.dat", info), ("expertplus.dat", beatmap)])
        defer { try? FileManager.default.removeItem(at: zip) }

        #expect(try MapHash.compute(zipAt: zip) == MapDownloaderTests.sha1(info + beatmap))
    }

    @Test
    func rejectsMissingBeatmapFile() throws {
        let zip = try Self.write([("Info.dat", Self.infoV2), ("Easy.dat", Data("easy".utf8))])
        defer { try? FileManager.default.removeItem(at: zip) }

        #expect(throws: MapArchiveError.invalidMap) {
            try MapHash.compute(zipAt: zip)
        }
    }

    @Test
    func rejectsMissingInfo() throws {
        let zip = try Self.write([("Easy.dat", Data("easy".utf8))])
        defer { try? FileManager.default.removeItem(at: zip) }

        #expect(throws: MapArchiveError.invalidMap) {
            try MapHash.compute(zipAt: zip)
        }
    }

    @Test
    func rejectsPathInBeatmapFilename() throws {
        let info = Self.infoV2(beatmapFilename: "../Easy.dat")
        let zip = try Self.write([("Info.dat", info), ("Easy.dat", Data("easy".utf8))])
        defer { try? FileManager.default.removeItem(at: zip) }

        #expect(throws: MapArchiveError.invalidMap) {
            try MapHash.compute(zipAt: zip)
        }
    }

    @Test
    func rejectsWhenTotalExceedsLimit() throws {
        let info = Self.infoV2(beatmapFilename: "Easy.dat")
        let beatmap = Data(count: 1_024)
        let zip = try Self.write([("Info.dat", info), ("Easy.dat", beatmap)])
        defer { try? FileManager.default.removeItem(at: zip) }

        #expect(throws: MapArchiveError.tooLarge) {
            try MapHash.compute(zipAt: zip, maxTotalBytes: 1_023)
        }
        #expect(try MapHash.compute(zipAt: zip, maxTotalBytes: 1_024) == MapDownloaderTests.sha1(info + beatmap))
    }

    @Test
    func rejectsNonZipFile() throws {
        let zip = try Self.write(raw: Data("PK\u{3}\u{4} broken".utf8))
        defer { try? FileManager.default.removeItem(at: zip) }

        #expect(throws: MapArchiveError.invalidMap) {
            try MapHash.compute(zipAt: zip)
        }
    }

    // MARK: - 補助

    /// 難易度が 1 つだけの v2 の Info.dat
    private static func infoV2(beatmapFilename: String) -> Data {
        Data(#"{"_version":"2.0.0","_difficultyBeatmapSets":[{"_difficultyBeatmaps":[{"_beatmapFilename":"\#(beatmapFilename)"}]}]}"#.utf8)
    }

    private static func write(_ files: [(String, Data)]) throws -> URL {
        try write(raw: TestZip.make(files.map { (name: $0.0, data: $0.1) }))
    }

    private static func write(raw data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ZankyoTests-\(UUID().uuidString).zip", directoryHint: .notDirectory)
        try data.write(to: url)
        return url
    }
}
