import Foundation
import Testing
@testable import Zankyo

struct AudioDataParserTests {
    @Test
    func readsV4Regions() throws {
        // 0〜10 秒は 120 BPM（拍 0〜20）、10〜15 秒は 240 BPM（拍 20〜40）
        let json = """
        { "version": "4.0.0", "songChecksum": "", "songSampleCount": 661500, "songFrequency": 44100,
          "bpmData": [{ "si": 441000, "ei": 661500, "sb": 20, "eb": 40 }, { "si": 0, "ei": 441000, "sb": 0, "eb": 20 }],
          "lufsData": [] }
        """
        let timeline = try #require(AudioDataParser.timeline(from: Data(json.utf8)))

        #expect(timeline.seconds(atBeat: 10) == 5)
        #expect(timeline.seconds(atBeat: 20) == 10)
        #expect(timeline.seconds(atBeat: 30) == 12.5)
    }

    @Test
    func readsLegacyBPMInfo() throws {
        let json = """
        { "_version": "2.0.0", "_songSampleCount": 441000, "_songFrequency": 44100,
          "_regions": [{ "_startSampleIndex": 44100, "_endSampleIndex": 441000, "_startBeat": 0, "_endBeat": 18 }] }
        """
        let timeline = try #require(AudioDataParser.timeline(from: Data(json.utf8)))

        // 1 秒の位置が拍 0、以降 (18 拍 / 9 秒) = 120 BPM
        #expect(timeline.seconds(atBeat: 0) == 1)
        #expect(timeline.seconds(atBeat: 4) == 3)
    }

    @Test
    func extendsFirstRegionBeforeItsStart() throws {
        let json = #"{ "songFrequency": 1000, "bpmData": [{ "si": 2000, "ei": 4000, "sb": 2, "eb": 4 }] }"#
        let timeline = try #require(AudioDataParser.timeline(from: Data(json.utf8)))

        // 拍 2 が 2 秒・60 BPM なので、拍 0 は 0 秒
        #expect(timeline.seconds(atBeat: 0) == 0)
        #expect(timeline.seconds(atBeat: 1) == 1)
    }

    @Test
    func keepsFastRegions() throws {
        // 速度を変える演出の区間（1,000 BPM 超）も、そのまま使う
        let json = """
        { "songFrequency": 1000, "bpmData": [
          { "si": 0, "ei": 1000, "sb": 0, "eb": 1 },
          { "si": 1000, "ei": 1100, "sb": 1, "eb": 3 },
          { "si": 1100, "ei": 2100, "sb": 3, "eb": 4 } ] }
        """
        let timeline = try #require(AudioDataParser.timeline(from: Data(json.utf8)))

        #expect(timeline.bpm(atBeat: 2) == 1_200)
        #expect(abs(timeline.seconds(atBeat: 3.5) - 1.6) < 1e-9)
    }

    @Test
    func skipsRegionsWithNegativeBeat() throws {
        let json = """
        { "songFrequency": 1000, "bpmData": [
          { "si": 0, "ei": 1000, "sb": -1, "eb": 0 },
          { "si": 1000, "ei": 3000, "sb": 0, "eb": 2 } ] }
        """
        let timeline = try #require(AudioDataParser.timeline(from: Data(json.utf8)))

        #expect(timeline.seconds(atBeat: 0) == 1)
        #expect(timeline.seconds(atBeat: 1) == 2)
    }

    @Test(arguments: [
        "not json",
        #"{ "songFrequency": 44100, "bpmData": [] }"#,
        #"{ "bpmData": [{ "si": 0, "ei": 100, "sb": 0, "eb": 1 }] }"#,
        #"{ "songFrequency": 0, "bpmData": [{ "si": 0, "ei": 100, "sb": 0, "eb": 1 }] }"#,
        #"{ "songFrequency": 44100, "bpmData": [{ "si": 100, "ei": 100, "sb": 0, "eb": 1 }] }"#,
        // 秒が戻る区間の並び
        #"{ "songFrequency": 1000, "bpmData": [{ "si": 5000, "ei": 6000, "sb": 0, "eb": 1 }, { "si": 0, "ei": 1000, "sb": 1, "eb": 2 }] }"#
    ])
    func rejectsInvalidData(json: String) {
        #expect(AudioDataParser.timeline(from: Data(json.utf8)) == nil)
    }
}
