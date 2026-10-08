import Foundation

/// 譜面の照明。Beat Saber の basic event のうち、背景の光（奥のレーザー・リング・左右のレーザー・中央の光）と、
/// その動き（リングの回転・左右のレーザーの速さ）だけを、曲の先頭からの秒に直して持つ
///
/// 光の色は Beat Saber の赤・青・白で、赤は左のセイバー、青は右のセイバーの色（画面ではテーマの左右のノーツの色に当てる）
nonisolated struct Lighting: Sendable, Hashable {
    /// 光の点け消し。時刻の順
    let events: [LightEvent]
    /// リングを回す時刻。時刻の順
    let ringSpins: [TimeInterval]
    /// 左右のレーザーを振る速さの変化。時刻の順
    let laserSpeeds: [LaserSpeed]

    static let empty = Lighting(events: [], ringSpins: [], laserSpeeds: [])
    /// 読むイベントの上限（照明の多い譜面でも演出に足りる数）
    static let maxEvents = 100_000
    /// レーザーの速さの上限（Beat Saber の譜面でよく使われる 0〜20 程度に収める）
    static let maxLaserSpeed: Double = 20

    /// 光の点け消しが 1 つも無い
    var isEmpty: Bool { events.isEmpty }

    /// basic event（拍・type・value・floatValue）から作る。拍は `timeline` で秒に直す。知らない type・value や不正な値は読まない
    static func from(_ basicEvents: [BasicLightEvent], timeline: BeatTimeline) -> Lighting {
        var events: [LightEvent] = []
        var ringSpins: [TimeInterval] = []
        var laserSpeeds: [LaserSpeed] = []
        for basic in basicEvents.prefix(maxEvents) {
            guard let beat = basic.beat, beat.isFinite, beat >= 0, let type = basic.type else { continue }
            let time = timeline.seconds(atBeat: beat)
            guard time.isFinite, time >= 0 else { continue }
            switch type {
            case 8:
                ringSpins.append(time)
            case 12, 13:
                guard let value = basic.value else { continue }
                let speed = min(max(Double(value), 0), maxLaserSpeed)
                laserSpeeds.append(LaserSpeed(time: time, side: type == 12 ? .left : .right, speed: speed))
            default:
                guard let group = LightGroup(rawValue: type), let value = basic.value,
                      let (action, color) = Self.action(forValue: value) else { continue }
                // `floatValue` は v2.5 以降の明るさ。無い・不正なら 1
                let brightness = basic.floatValue.flatMap { $0.isFinite ? min(max($0, 0), 1.5) : nil } ?? 1
                events.append(LightEvent(time: time, group: group, action: action, color: color, brightness: brightness))
            }
        }
        return Lighting(
            events: events.sorted { $0.time < $1.time },
            ringSpins: ringSpins.sorted(),
            laserSpeeds: laserSpeeds.sorted { $0.time < $1.time }
        )
    }

    /// basic event の value を、光の動きと色に直す。0 は消灯、1〜4 は青、5〜8 は赤、9〜12 は白（点灯・点滅・フェード・移り変わり）
    static func action(forValue value: Int) -> (LightAction, LightColor)? {
        guard value != 0 else { return (.off, .right) }
        guard (1...12).contains(value) else { return nil }
        let color: LightColor = switch value {
        case 1...4: .right
        case 5...8: .left
        default: .white
        }
        let action: LightAction = switch (value - 1) % 4 {
        case 1: .flash
        case 2: .fade
        // 0: 点灯、3: 次のイベントへの移り変わり（色を変えながら点いている）
        default: .on
        }
        return (action, color)
    }
}

/// 譜面に書かれた basic event 1 つ。形式（v2 / v3 / v4）の差は読む側が吸収する
nonisolated struct BasicLightEvent: Sendable, Hashable {
    let beat: Double?
    let type: Int?
    let value: Int?
    let floatValue: Double?
}

/// 光の点け消し 1 つ
nonisolated struct LightEvent: Sendable, Hashable {
    /// 曲の先頭からの秒
    let time: TimeInterval
    let group: LightGroup
    let action: LightAction
    let color: LightColor
    /// 明るさ（0〜1.5。1 がふつう）
    let brightness: Double
}

/// 光の置き場所。Beat Saber の basic event の type と同じ番号
nonisolated enum LightGroup: Int, Sendable, Hashable, CaseIterable {
    /// 奥のレーザー
    case back = 0
    /// リング
    case rings = 1
    /// 左のレーザー
    case leftLasers = 2
    /// 右のレーザー
    case rightLasers = 3
    /// 中央の光
    case center = 4
}

nonisolated enum LightAction: Sendable, Hashable {
    case off
    /// 点いたまま
    case on
    /// 強く光ってから、点いた明るさに落ち着く
    case flash
    /// 強く光ってから、消えていく
    case fade
}

nonisolated enum LightColor: Sendable, Hashable {
    /// 赤（左のセイバーの色）
    case left
    /// 青（右のセイバーの色）
    case right
    case white
}

/// 左右のレーザーを振る速さの変化（type 12 が左、13 が右）
nonisolated struct LaserSpeed: Sendable, Hashable {
    nonisolated enum Side: Sendable, Hashable {
        case left
        case right
    }

    let time: TimeInterval
    let side: Side
    /// 0 で止まる。大きいほど速く振る
    let speed: Double
}

/// v4 の難易度ごとのライトショーのファイル（Info.dat の `lightshowDataFilename`）から basic event を読む。
/// v4 は拍（`basicEvents` の `b` と、中身の番号 `i`）と中身（`basicEventsData` の `t`・`i`・`f`）に分かれ、値が 0 のキーは省かれる
nonisolated enum LightshowParser {
    /// ファイルの上限。ライトショーには 1 ファイル 27MB 近いものがあるので、譜面と同じ余裕を持たせる
    static let maxBytes = BeatmapParser.maxBytes

    /// 読めない・上限を超えるときは照明なし（照明が無くても遊べるので、エラーにしない）
    static func parse(_ data: Data, timeline: BeatTimeline) -> Lighting {
        guard data.count <= maxBytes, let file = try? JSONDecoder().decode(LightshowV4.self, from: data) else { return .empty }
        let basicEvents = file.basicEvents.map { event -> BasicLightEvent in
            let content = event.index.flatMap { file.basicEventsData.indices.contains($0) ? file.basicEventsData[$0] : nil }
            // 中身が無いイベントは、拍を nil にして除く
            return BasicLightEvent(
                beat: content == nil ? nil : event.beat,
                type: content?.type,
                value: content?.value,
                floatValue: content?.floatValue
            )
        }
        return Lighting.from(basicEvents, timeline: timeline)
    }
}

nonisolated private struct LightshowV4: Decodable {
    let basicEvents: [LightshowV4Event]
    /// 番号で引くので、読めない要素も詰めずに nil として残す
    let basicEventsData: [LightshowV4EventData?]

    private enum CodingKeys: String, CodingKey {
        case basicEvents, basicEventsData
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        basicEvents = container.lenient(LossyDecodableArray<LightshowV4Event>.self, forKey: .basicEvents)?.elements ?? []
        basicEventsData = container.lenient([Lenient<LightshowV4EventData>].self, forKey: .basicEventsData)?.map(\.value) ?? []
    }
}

nonisolated private struct LightshowV4Event: Decodable {
    let beat: Double?
    let index: Int?

    private enum CodingKeys: String, CodingKey {
        case beat = "b"
        case index = "i"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        beat = container.contains(.beat) ? container.lenient(Double.self, forKey: .beat) : 0
        index = container.contains(.index) ? container.lenient(Int.self, forKey: .index) : 0
    }
}

nonisolated private struct LightshowV4EventData: Decodable {
    let type: Int?
    let value: Int?
    let floatValue: Double?

    private enum CodingKeys: String, CodingKey {
        case type = "t"
        case value = "i"
        case floatValue = "f"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = container.contains(.type) ? container.lenient(Int.self, forKey: .type) : 0
        value = container.contains(.value) ? container.lenient(Int.self, forKey: .value) : 0
        // 明るさが省かれていたら、ふつうの明るさ（1）とみなす（0 として読むと、点けたはずの光が見えなくなる）
        floatValue = container.lenient(Double.self, forKey: .floatValue)
    }
}
