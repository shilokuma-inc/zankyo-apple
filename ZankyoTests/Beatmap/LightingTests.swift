import Foundation
import Testing
@testable import Zankyo

struct LightingTests {
    /// 120 BPM（1 拍 0.5 秒）
    private let timeline = BeatTimeline(bpm: 120)

    @Test(arguments: [
        (0, LightAction.off), (1, .on), (2, .flash), (3, .fade), (4, .on),
        (5, .on), (6, .flash), (7, .fade), (8, .on), (9, .on), (10, .flash), (11, .fade), (12, .on)
    ])
    func valueMapsToAction(value: Int, action: LightAction) throws {
        let (mapped, _) = try #require(Lighting.action(forValue: value))
        #expect(mapped == action)
    }

    @Test
    func valueMapsToColor() {
        // 1〜4 は青（右のセイバー）、5〜8 は赤（左）、9〜12 は白
        #expect(Lighting.action(forValue: 2)?.1 == .right)
        #expect(Lighting.action(forValue: 6)?.1 == .left)
        #expect(Lighting.action(forValue: 10)?.1 == .white)
        #expect(Lighting.action(forValue: 13) == nil)
        #expect(Lighting.action(forValue: -1) == nil)
    }

    @Test
    func readsV2Events() throws {
        let data = """
            { "_version": "2.2.0",
              "_notes": [{ "_time": 1, "_lineIndex": 1, "_lineLayer": 0, "_type": 0, "_cutDirection": 1 }],
              "_events": [
                { "_time": 4, "_type": 2, "_value": 6, "_floatValue": 0.5 },
                { "_time": 2, "_type": 0, "_value": 1 },
                { "_time": 3, "_type": 8, "_value": 0 },
                { "_time": 3, "_type": 12, "_value": 99 },
                { "_time": 5, "_type": 100, "_floatValue": 120 },
                { "_time": 6, "_type": 5, "_value": 1 },
                { "_time": 7, "_type": 1, "_value": 42 }
              ] }
            """
        let lighting = try BeatmapParser.parse(Data(data.utf8), bpm: 120).lighting

        // 時刻の順に並べ、BPM 変化（100）・知らない type（5）・知らない value（42）は読まない
        #expect(lighting.events.map(\.time) == [1, 2])
        #expect(lighting.events.map(\.group) == [.back, .leftLasers])
        #expect(lighting.events[0].brightness == 1)
        #expect(lighting.events[1].action == .flash)
        #expect(lighting.events[1].color == .left)
        #expect(lighting.events[1].brightness == 0.5)
        #expect(lighting.ringSpins == [1.5])
        // 速さは上限で止める
        #expect(lighting.laserSpeeds == [LaserSpeed(time: 1.5, side: .left, speed: Lighting.maxLaserSpeed)])
    }

    @Test
    func readsV3BasicEvents() throws {
        let data = """
            { "version": "3.3.0",
              "colorNotes": [{ "b": 1, "x": 1, "y": 0, "c": 1, "d": 0 }],
              "basicBeatmapEvents": [{ "b": 2, "et": 3, "i": 3, "f": 1 }, { "b": -1, "et": 0, "i": 1, "f": 1 }] }
            """
        let lighting = try BeatmapParser.parse(Data(data.utf8), bpm: 120).lighting

        // 負の拍は読まない
        #expect(lighting.events == [LightEvent(time: 1, group: .rightLasers, action: .fade, color: .right, brightness: 1)])
    }

    @Test
    func v4DifficultyHasNoLightingAndLightshowFileIsRead() throws {
        let beatmap = #"{ "version": "4.0.0", "colorNotes": [{ "b": 1 }], "colorNotesData": [{ "d": 1 }] }"#
        #expect(try BeatmapParser.parse(Data(beatmap.utf8), bpm: 120).lighting.isEmpty)

        // 値が 0 のキーは省かれる（`{}` は拍 0・中身 0、中身 `{ "t": 4 }` は中央の光の value 0 = 消灯）。明るさが省かれたら 1
        let lightshow = """
            { "version": "4.0.0",
              "basicEvents": [{ "b": 2, "i": 1 }, {}, { "b": 3, "i": 9 }],
              "basicEventsData": [{ "t": 4 }, { "t": 1, "i": 7 }] }
            """
        let lighting = LightshowParser.parse(Data(lightshow.utf8), timeline: timeline)

        #expect(lighting.events == [
            LightEvent(time: 0, group: .center, action: .off, color: .right, brightness: 1),
            LightEvent(time: 1, group: .rings, action: .fade, color: .left, brightness: 1)
        ])
    }

    @Test
    func brokenLightshowIsEmpty() {
        #expect(LightshowParser.parse(Data("not json".utf8), timeline: timeline).isEmpty)
    }
}
