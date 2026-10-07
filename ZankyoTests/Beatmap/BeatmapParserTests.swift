import Foundation
import Testing
@testable import Zankyo

struct BeatmapParserTests {
    // MARK: - v2

    @Test
    func parsesV2NotesInSeconds() throws {
        let json = """
        { "_version": "2.6.0", "_notes": [
          { "_time": 4, "_lineIndex": 3, "_lineLayer": 2, "_type": 1, "_cutDirection": 3 },
          { "_time": 2, "_lineIndex": 0, "_lineLayer": 0, "_type": 0, "_cutDirection": 0 },
          { "_time": 3, "_lineIndex": 1, "_lineLayer": 0, "_type": 3, "_cutDirection": 0 }
        ], "_obstacles": [], "_events": [] }
        """
        let beatmap = try BeatmapParser.parse(Data(json.utf8), bpm: 120)

        #expect(beatmap.format == .v2)
        // 爆弾（type 3）は除き、拍の順に並べる。120 BPM なので 1 拍 = 0.5 秒
        #expect(beatmap.notes == [
            BeatmapNote(beat: 2, time: 1, lineIndex: 0, lineLayer: 0, color: .red, cutDirection: .up),
            BeatmapNote(beat: 4, time: 2, lineIndex: 3, lineLayer: 2, color: .blue, cutDirection: .right)
        ])
    }

    @Test
    func appliesSongTimeOffset() throws {
        let json = #"{ "_version": "2.0.0", "_notes": [{ "_time": 2, "_type": 0, "_cutDirection": 8 }] }"#
        let beatmap = try BeatmapParser.parse(Data(json.utf8), bpm: 60, songTimeOffset: 0.25)

        #expect(beatmap.notes.map(\.time) == [2.25])
        #expect(beatmap.notes.map(\.cutDirection) == [.any])
    }

    @Test
    func appliesV2BPMChangesFromEventsAndBPMChanges() throws {
        // 拍 4 から 60 BPM（`_events` の type 100）、拍 8 から 240 BPM（`_BPMChanges`）
        let json = """
        { "_version": "2.2.0",
          "_notes": [
            { "_time": 4, "_type": 0, "_cutDirection": 1 },
            { "_time": 6, "_type": 0, "_cutDirection": 1 },
            { "_time": 10, "_type": 1, "_cutDirection": 1 }
          ],
          "_events": [{ "_time": 4, "_type": 100, "_value": 0, "_floatValue": 60 }, { "_time": 1, "_type": 1, "_value": 3 }],
          "_BPMChanges": [{ "_time": 8, "_BPM": 240 }]
        }
        """
        let beatmap = try BeatmapParser.parse(Data(json.utf8), bpm: 120)

        // 拍 0〜4: 120 BPM で 2 秒 / 拍 4〜8: 60 BPM で 4 秒 / 拍 8〜: 240 BPM で 1 拍 0.25 秒
        #expect(beatmap.notes.map(\.time) == [2, 4, 6.5])
    }

    @Test
    func treatsVersionlessNotesAsV2() throws {
        let json = #"{ "_notes": [{ "_time": 1, "_type": 1, "_cutDirection": 2 }] }"#
        let beatmap = try BeatmapParser.parse(Data(json.utf8), bpm: 60)

        #expect(beatmap.format == .v2)
        #expect(beatmap.notes.map(\.cutDirection) == [.left])
    }

    // MARK: - v3

    @Test
    func parsesV3ColorNotesAndBPMEvents() throws {
        let json = """
        { "version": "3.3.0",
          "bpmEvents": [{ "b": 0, "m": 60 }, { "b": 2, "m": 120 }],
          "colorNotes": [
            { "b": 3, "x": 2, "y": 1, "c": 1, "d": 7, "a": 0 },
            { "b": 1, "x": 1, "y": 0, "c": 0, "d": 4, "a": 0 }
          ],
          "bombNotes": [{ "b": 1.5, "x": 0, "y": 0 }],
          "obstacles": [], "sliders": [], "burstSliders": []
        }
        """
        let beatmap = try BeatmapParser.parse(Data(json.utf8), bpm: 200)

        #expect(beatmap.format == .v3)
        // 拍 0 の BPM 変化が Info.dat の BPM を置き換える。拍 0〜2 は 60 BPM（2 秒）、拍 2〜 は 120 BPM
        #expect(beatmap.notes == [
            BeatmapNote(beat: 1, time: 1, lineIndex: 1, lineLayer: 0, color: .red, cutDirection: .upLeft),
            BeatmapNote(beat: 3, time: 2.5, lineIndex: 2, lineLayer: 1, color: .blue, cutDirection: .downRight)
        ])
    }

    // MARK: - 信用しない入力

    @Test
    func dropsInvalidNotesAndClampsPositions() throws {
        let json = """
        { "version": "3.0.0", "colorNotes": [
          { "b": -1, "x": 0, "y": 0, "c": 0, "d": 0 },
          { "b": 1, "x": 0, "y": 0, "c": 2, "d": 0 },
          { "b": 2, "x": 0, "y": 0, "c": 0, "d": 1090 },
          { "b": "3", "x": 0, "y": 0, "c": 0, "d": 0 },
          { "b": 4, "x": 1000, "y": -5, "c": 1, "d": 1 },
          "broken"
        ] }
        """
        let beatmap = try BeatmapParser.parse(Data(json.utf8), bpm: 60)

        #expect(beatmap.notes == [BeatmapNote(beat: 4, time: 4, lineIndex: 3, lineLayer: 0, color: .blue, cutDirection: .down)])
    }

    @Test
    func ignoresInvalidBPMChanges() throws {
        let json = """
        { "version": "3.0.0",
          "bpmEvents": [{ "b": 1, "m": 0 }, { "b": -2, "m": 60 }, { "b": 1, "m": 100000 }],
          "colorNotes": [{ "b": 2, "x": 0, "y": 0, "c": 0, "d": 0 }]
        }
        """
        let beatmap = try BeatmapParser.parse(Data(json.utf8), bpm: 60)

        #expect(beatmap.notes.map(\.time) == [2])
        #expect(beatmap.timeline.segments.count == 1)
    }

    @Test
    func limitsNoteCount() throws {
        let notes = (0..<(BeatmapParser.maxNotes + 10))
            .map { #"{ "b": \#($0), "x": 0, "y": 0, "c": 0, "d": 8 }"# }
            .joined(separator: ",")
        let json = #"{ "version": "3.0.0", "colorNotes": [\#(notes)] }"#
        let beatmap = try BeatmapParser.parse(Data(json.utf8), bpm: 120)

        #expect(beatmap.notes.count == BeatmapParser.maxNotes)
        #expect(beatmap.notes.last?.beat == Double(BeatmapParser.maxNotes - 1))
    }

    @Test
    func limitCountsOnlyPlayableNotes() throws {
        // 上限を超える数の不正なノーツの後ろにある、切れるノーツを捨てない
        let invalid = (0..<BeatmapParser.maxNotes)
            .map { #"{ "b": \#($0), "x": 0, "y": 0, "c": 0, "d": 99 }"# }
            .joined(separator: ",")
        let json = #"{ "version": "3.0.0", "colorNotes": [\#(invalid), { "b": 30000, "x": 0, "y": 0, "c": 1, "d": 0 }] }"#
        let beatmap = try BeatmapParser.parse(Data(json.utf8), bpm: 120)

        #expect(beatmap.notes.map(\.beat) == [30_000])
    }

    @Test
    func dropsNotesWhoseTimeIsNotFinite() throws {
        let json = """
        { "_version": "2.0.0", "_notes": [
          { "_time": 1e308, "_type": 0, "_cutDirection": 0 },
          { "_time": 1, "_type": 1, "_cutDirection": 0 }
        ] }
        """
        let beatmap = try BeatmapParser.parse(Data(json.utf8), bpm: 1)

        #expect(beatmap.notes.map(\.beat) == [1])
    }

    @Test(arguments: [
        #"{ "_version": "2.0.0", "_notes": [{ "_time": 1, "_type": 3, "_cutDirection": 0 }] }"#,
        #"{ "version": "3.0.0", "colorNotes": [], "bombNotes": [{ "b": 1, "x": 0, "y": 0 }] }"#,
        #"{ "version": "3.0.0" }"#
    ])
    func rejectsBeatmapWithoutNotes(json: String) {
        #expect(throws: BeatmapParseError.noNotes) {
            try BeatmapParser.parse(Data(json.utf8), bpm: 120)
        }
    }

    @Test
    func rejectsV4AsUnsupported() {
        let json = #"{ "version": "4.0.0", "colorNotes": [{ "b": 1, "r": 0, "i": 0 }], "colorNotesData": [] }"#
        #expect(throws: BeatmapParseError.unsupportedVersion("4.0.0")) {
            try BeatmapParser.parse(Data(json.utf8), bpm: 120)
        }
    }

    @Test(arguments: ["not json", "[]", ""])
    func rejectsMalformedJSON(json: String) {
        #expect(throws: BeatmapParseError.malformed) {
            try BeatmapParser.parse(Data(json.utf8), bpm: 120)
        }
    }

    @Test
    func rejectsTooLargeFile() {
        let data = Data(repeating: 0x20, count: BeatmapParser.maxBytes + 1)
        #expect(throws: BeatmapParseError.tooLarge) {
            try BeatmapParser.parse(data, bpm: 120)
        }
    }
}

struct BeatTimelineTests {
    @Test
    func convertsBeatsAcrossBPMChanges() {
        let timeline = BeatTimeline(bpm: 120, changes: [(beat: 8, bpm: 240), (beat: 4, bpm: 60)], offset: 1)

        #expect(timeline.seconds(atBeat: 0) == 1)
        #expect(timeline.seconds(atBeat: 4) == 3)
        #expect(timeline.seconds(atBeat: 8) == 7)
        #expect(timeline.seconds(atBeat: 12) == 8)
        #expect(timeline.bpm(atBeat: 5) == 60)
        // 拍 0 より前は最初の BPM で延ばす
        #expect(timeline.seconds(atBeat: -2) == 0)
    }

    @Test
    func limitCountsOnlyValidChanges() {
        let invalid = Array(repeating: (beat: 1.0, bpm: 0.0), count: BeatTimeline.maxChanges)
        let timeline = BeatTimeline(bpm: 120, changes: invalid + [(beat: 0, bpm: 60)])

        #expect(timeline.bpm(atBeat: 1) == 60)
    }

    @Test
    func laterChangeAtSameBeatWins() {
        let timeline = BeatTimeline(bpm: 120, changes: [(beat: 0, bpm: 90), (beat: 0, bpm: 60)])

        #expect(timeline.segments == [BeatTimeline.Segment(beat: 0, seconds: 0, bpm: 60)])
        #expect(timeline.seconds(atBeat: 3) == 3)
    }
}
