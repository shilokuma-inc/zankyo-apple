import Foundation
import Testing
@testable import Zankyo

struct SongInfoParserTests {
    // MARK: - v2

    @Test
    func parsesV2() throws {
        let info = try SongInfoParser.parse(Data(InfoFixtures.v2().utf8))

        #expect(info.format == .v2)
        #expect(info.title == "Test Song")
        #expect(info.subTitle == "Short Ver.")
        #expect(info.artist == "Zankyo Band")
        #expect(info.mapper == "Shilokuma")
        #expect(info.bpm == 128)
        #expect(info.songTimeOffset == 0.25)
        #expect(info.songFilename == "song.egg")
        #expect(info.coverImageFilename == "cover.jpg")
        #expect(info.audioDataFilename == nil)
        #expect(info.previewStartTime == 12.5)
        #expect(info.previewDuration == 10)
        #expect(info.difficulties.map(\.difficulty) == [.easy, .expertPlus, .hard])
        #expect(info.difficulties.map(\.characteristic) == [.standard, .standard, .oneSaber])
        let expertPlus = info.difficulties[1]
        #expect(expertPlus.beatmapFilename == "ExpertPlusStandard.dat")
        #expect(expertPlus.noteJumpSpeed == 18)
        #expect(expertPlus.noteJumpStartBeatOffset == -0.5)
    }

    @Test
    func dropsLightshowUnknownAndDuplicateDifficulties() throws {
        let sets = """
        [
          { "_beatmapCharacteristicName": "Lightshow", "_difficultyBeatmaps": [\(InfoFixtures.v2Beatmap("Easy", "Lightshow.dat"))] },
          { "_beatmapCharacteristicName": "Lawless", "_difficultyBeatmaps": [\(InfoFixtures.v2Beatmap("Easy", "Lawless.dat"))] },
          { "_beatmapCharacteristicName": "Standard", "_difficultyBeatmaps": [
            \(InfoFixtures.v2Beatmap("Normal", "NormalStandard.dat")),
            \(InfoFixtures.v2Beatmap("Normal", "NormalStandard2.dat")),
            \(InfoFixtures.v2Beatmap("Insane", "Insane.dat"))
          ] }
        ]
        """
        let info = try SongInfoParser.parse(Data(InfoFixtures.v2(sets: sets).utf8))

        #expect(info.difficulties.count == 1)
        #expect(info.difficulties.first?.beatmapFilename == "NormalStandard.dat")
    }

    @Test(arguments: ["../Easy.dat", "/etc/passwd", "sub/Easy.dat", "..", "a\\\\b.dat", ""])
    func dropsDifficultyWithUnsafeFilename(filename: String) throws {
        let sets = """
        [{ "_beatmapCharacteristicName": "Standard", "_difficultyBeatmaps": [
          \(InfoFixtures.v2Beatmap("Easy", filename)),
          \(InfoFixtures.v2Beatmap("Hard", "HardStandard.dat"))
        ] }]
        """
        let info = try SongInfoParser.parse(Data(InfoFixtures.v2(sets: sets).utf8))

        #expect(info.difficulties.map(\.beatmapFilename) == ["HardStandard.dat"])
    }

    @Test(arguments: ["../song.egg", "/tmp/song.egg", "music/song.egg", ""])
    func rejectsUnsafeSongFilename(filename: String) {
        #expect(throws: SongInfoParseError.invalidSongFilename) {
            try SongInfoParser.parse(Data(InfoFixtures.v2(songFilename: filename).utf8))
        }
    }

    @Test
    func unsafeCoverFilenameBecomesNil() throws {
        let info = try SongInfoParser.parse(Data(InfoFixtures.v2(coverFilename: "../cover.jpg").utf8))

        #expect(info.coverImageFilename == nil)
    }

    @Test(arguments: ["0", "-120", "100000", "\"fast\""])
    func rejectsInvalidBPM(bpm: String) {
        #expect(throws: SongInfoParseError.invalidBPM) {
            try SongInfoParser.parse(Data(InfoFixtures.v2(bpm: bpm).utf8))
        }
    }

    @Test
    func rejectsWhenNoPlayableDifficulty() {
        let sets = #"[{ "_beatmapCharacteristicName": "Lightshow", "_difficultyBeatmaps": [\#(InfoFixtures.v2Beatmap("Easy", "a.dat"))] }]"#

        #expect(throws: SongInfoParseError.noPlayableDifficulty) {
            try SongInfoParser.parse(Data(InfoFixtures.v2(sets: sets).utf8))
        }
    }

    @Test
    func toleratesWrongTypesInOptionalFields() throws {
        let json = InfoFixtures.v2()
            .replacingOccurrences(of: #""_songSubName": "Short Ver.""#, with: #""_songSubName": 42"#)
            .replacingOccurrences(of: #""_songTimeOffset": 0.25"#, with: #""_songTimeOffset": "late""#)
        let info = try SongInfoParser.parse(Data(json.utf8))

        #expect(info.subTitle.isEmpty)
        #expect(info.songTimeOffset == 0)
    }

    @Test
    func clampsOutOfRangeNumbers() throws {
        let sets = """
        [{ "_beatmapCharacteristicName": "Standard", "_difficultyBeatmaps": [
          { "_difficulty": "Easy", "_beatmapFilename": "Easy.dat", "_noteJumpMovementSpeed": 9999, "_noteJumpStartBeatOffset": -9999 }
        ] }]
        """
        let info = try SongInfoParser.parse(Data(InfoFixtures.v2(sets: sets).utf8))

        #expect(info.difficulties.first?.noteJumpSpeed == 100)
        #expect(info.difficulties.first?.noteJumpStartBeatOffset == -10)
    }

    @Test(arguments: [("-1", "10"), ("12", "0"), ("12", "-3"), ("\"abc\"", "null"), ("1e9", "10")])
    func ignoresInvalidPreview(startTime: String, duration: String) throws {
        let info = try SongInfoParser.parse(Data(InfoFixtures.v2(previewStartTime: startTime, previewDuration: duration).utf8))

        // 範囲外・型違いの値は無いものとみなす（正しい方の値は残す）
        let start = Double(startTime).flatMap { (0...900).contains($0) ? $0 : nil }
        let length = Double(duration).flatMap { $0 > 0 && $0 <= 900 ? $0 : nil }
        #expect(info.previewStartTime == start)
        #expect(info.previewDuration == length)
    }

    // MARK: - v4

    @Test
    func parsesV4() throws {
        let info = try SongInfoParser.parse(Data(InfoFixtures.v4.utf8))

        #expect(info.format == .v4)
        #expect(info.title == "Test Song")
        #expect(info.subTitle == "Short Ver.")
        #expect(info.artist == "Zankyo Band")
        #expect(info.mapper == "Shilokuma, Guest")
        #expect(info.bpm == 140)
        #expect(info.songTimeOffset == 0)
        #expect(info.songFilename == "song.ogg")
        #expect(info.coverImageFilename == "cover.png")
        #expect(info.audioDataFilename == "BPMInfo.dat")
        #expect(info.previewStartTime == 10)
        #expect(info.previewDuration == 10)
        #expect(info.difficulties.map(\.difficulty) == [.normal, .expert])
        #expect(info.difficulties.map(\.beatmapFilename) == ["NormalStandard.dat", "ExpertStandard.dat"])
    }

    // MARK: - 形式

    @Test(arguments: [#"{ "_version": "3.0.0" }"#, #"{ "version": "5.0.0" }"#, "{}"])
    func rejectsUnsupportedVersion(json: String) {
        #expect(throws: SongInfoParseError.self) {
            try SongInfoParser.parse(Data(json.utf8))
        }
    }

    @Test
    func rejectsMalformedJSON() {
        #expect(throws: SongInfoParseError.malformed) {
            try SongInfoParser.parse(Data("{not json".utf8))
        }
    }

    @Test
    func rejectsTooLargeFile() {
        let data = Data(repeating: 0x20, count: SongInfoParser.maxBytes + 1)

        #expect(throws: SongInfoParseError.tooLarge) {
            try SongInfoParser.parse(data)
        }
    }
}

/// 自作の `Info.dat`（beatsaver の実データは使わない）
nonisolated enum InfoFixtures {
    static func v2Beatmap(_ difficulty: String, _ filename: String) -> String {
        #"{ "_difficulty": "\#(difficulty)", "_difficultyRank": 1, "_beatmapFilename": "\#(filename)", "_noteJumpMovementSpeed": 10 }"#
    }

    static let v2Sets = """
    [
      { "_beatmapCharacteristicName": "OneSaber", "_difficultyBeatmaps": [\(v2Beatmap("Hard", "HardOneSaber.dat"))] },
      { "_beatmapCharacteristicName": "Standard", "_difficultyBeatmaps": [
        { "_difficulty": "ExpertPlus", "_difficultyRank": 9, "_beatmapFilename": "ExpertPlusStandard.dat",
          "_noteJumpMovementSpeed": 18, "_noteJumpStartBeatOffset": -0.5 },
        \(v2Beatmap("Easy", "EasyStandard.dat"))
      ] }
    ]
    """

    static func v2(
        bpm: String = "128",
        songFilename: String = "song.egg",
        coverFilename: String = "cover.jpg",
        previewStartTime: String = "12.5",
        previewDuration: String = "10",
        sets: String = v2Sets
    ) -> String {
        """
        {
          "_version": "2.1.0",
          "_songName": "Test Song",
          "_songSubName": "Short Ver.",
          "_songAuthorName": "Zankyo Band",
          "_levelAuthorName": "Shilokuma",
          "_beatsPerMinute": \(bpm),
          "_songTimeOffset": 0.25,
          "_songFilename": "\(songFilename)",
          "_coverImageFilename": "\(coverFilename)",
          "_previewStartTime": \(previewStartTime),
          "_previewDuration": \(previewDuration),
          "_environmentName": "DefaultEnvironment",
          "_difficultyBeatmapSets": \(sets)
        }
        """
    }

    static let v4 = """
    {
      "version": "4.0.1",
      "song": { "title": "Test Song", "subTitle": "Short Ver.", "author": "Zankyo Band" },
      "audio": {
        "songFilename": "song.ogg", "songDuration": 120, "audioDataFilename": "BPMInfo.dat",
        "bpm": 140, "lufs": 0, "previewStartTime": 10, "previewDuration": 10
      },
      "songPreviewFilename": "song.ogg",
      "coverImageFilename": "cover.png",
      "environmentNames": ["WeaveEnvironment"],
      "difficultyBeatmaps": [
        {
          "characteristic": "Standard", "difficulty": "Expert",
          "beatmapAuthors": { "mappers": ["Shilokuma", "Guest"], "lighters": ["Light"] },
          "environmentNameIdx": 0, "beatmapColorSchemeIdx": 0, "noteJumpMovementSpeed": 16, "noteJumpStartBeatOffset": 0,
          "beatmapDataFilename": "ExpertStandard.dat", "lightshowDataFilename": "Lightshow.dat"
        },
        {
          "characteristic": "Standard", "difficulty": "Normal",
          "beatmapAuthors": { "mappers": ["Shilokuma"], "lighters": [] },
          "noteJumpMovementSpeed": 10, "noteJumpStartBeatOffset": 0,
          "beatmapDataFilename": "NormalStandard.dat", "lightshowDataFilename": "Lightshow.dat"
        },
        {
          "characteristic": "Lightshow", "difficulty": "Easy",
          "beatmapAuthors": { "mappers": [], "lighters": ["Light"] },
          "beatmapDataFilename": "LightshowOnly.dat", "lightshowDataFilename": "Lightshow.dat"
        }
      ]
    }
    """
}
