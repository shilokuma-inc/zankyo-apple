import Foundation

nonisolated enum BeatmapParseError: Error, Equatable, Sendable {
    /// ファイルが上限より大きい
    case tooLarge
    /// JSON として読めない
    case malformed
    /// v2 / v3 以外の形式。v4 の譜面は MVP では遊べない（Discussion #3 の決定）
    case unsupportedVersion(String)
    /// 切るノーツが 1 つも無い
    case noNotes
}

/// 難易度譜面（`.dat`）を読み、ノーツを曲の先頭からの秒に置く。ZIP の中身は信用しない入力として扱う
nonisolated enum BeatmapParser {
    /// 譜面ファイルの上限。ライティングのイベントが多い譜面には 1 ファイル 27MB 近いものがあるので、余裕を持たせる
    static let maxBytes = 64 * 1_024 * 1_024
    /// 読み込むノーツの上限（ExpertPlus の長い曲でも数千個）
    static let maxNotes = 20_000

    /// - Parameters:
    ///   - bpm: Info.dat の BPM（拍 0 の BPM）
    ///   - songTimeOffset: Info.dat の `_songTimeOffset`（秒。v4 の Info.dat なら 0）
    static func parse(_ data: Data, bpm: Double, songTimeOffset: Double = 0) throws(BeatmapParseError) -> Beatmap {
        guard data.count <= maxBytes else { throw .tooLarge }
        let probe: BeatmapVersionProbe
        do {
            probe = try JSONDecoder().decode(BeatmapVersionProbe.self, from: data)
        } catch {
            throw .malformed
        }
        let format: Beatmap.Format
        let raw: RawBeatmap
        switch probe.majorVersion {
        case "2":
            format = .v2
            raw = try decode(BeatmapV2.self, from: data).raw
        case "3":
            format = .v3
            raw = try decode(BeatmapV3.self, from: data).raw
        case nil where probe.hasV2Notes:
            // 初期の v2 には `_version` が無いものがある
            format = .v2
            raw = try decode(BeatmapV2.self, from: data).raw
        default:
            throw .unsupportedVersion(String((probe.version ?? "").prefix(16)))
        }

        let timeline = BeatTimeline(bpm: bpm, changes: raw.bpmChanges, offset: songTimeOffset)
        // 切れるノーツだけを選んでから拍の順に並べ、上限を当てる（不正なノーツで上限を使い切らないため）
        let notes = raw.notes
            .compactMap { note -> BeatmapNote? in
                guard let beat = note.beat, beat.isFinite, beat >= 0,
                      let color = note.color.flatMap(NoteColor.init(rawValue:)),
                      let direction = note.cutDirection.flatMap(CutDirection.init(rawValue:)) else { return nil }
                // 極端に大きな拍は秒に直すと有限でなくなる
                let time = timeline.seconds(atBeat: beat)
                guard time.isFinite else { return nil }
                return BeatmapNote(
                    beat: beat,
                    time: time,
                    lineIndex: BeatsaverValidation.clamp(note.lineIndex, to: 0...3),
                    lineLayer: BeatsaverValidation.clamp(note.lineLayer, to: 0...2),
                    color: color,
                    cutDirection: direction
                )
            }
            .sorted { $0.beat < $1.beat }
            .prefix(maxNotes)
        guard !notes.isEmpty else { throw .noNotes }
        return Beatmap(format: format, notes: Array(notes), timeline: timeline)
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws(BeatmapParseError) -> Value {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw .malformed
        }
    }
}

// MARK: - 形式に依らない中間表現

nonisolated private struct RawNote {
    let beat: Double?
    let lineIndex: Int?
    let lineLayer: Int?
    /// 0 = 赤 / 1 = 青。爆弾など切らないものは nil
    let color: Int?
    let cutDirection: Int?
}

nonisolated private struct RawBeatmap {
    let notes: [RawNote]
    let bpmChanges: [(beat: Double, bpm: Double)]
}

// MARK: - JSON の形

/// 形式の判定用。v2 は `_version`、v3 / v4 は `version`
nonisolated private struct BeatmapVersionProbe: Decodable {
    let version: String?
    let hasV2Notes: Bool

    var majorVersion: String? {
        version?.split(separator: ".").first.map(String.init)
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case legacyVersion = "_version"
        case notes = "_notes"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = container.lenient(String.self, forKey: .version) ?? container.lenient(String.self, forKey: .legacyVersion)
        hasV2Notes = container.contains(.notes)
    }
}

nonisolated private struct BeatmapV2: Decodable {
    let notes: [BeatmapV2Note]
    let events: [BeatmapV2Event]
    let bpmChanges: [BeatmapV2BPMChange]

    var raw: RawBeatmap {
        // BPM 変化は `_BPMChanges`（エディタの拡張）と、`_events` の type 100 のどちらかで書かれる
        let fromEvents = events.compactMap { event -> (beat: Double, bpm: Double)? in
            guard event.type == 100, let beat = event.time, let bpm = event.floatValue else { return nil }
            return (beat, bpm)
        }
        let fromChanges = bpmChanges.compactMap { change -> (beat: Double, bpm: Double)? in
            guard let beat = change.time, let bpm = change.bpm else { return nil }
            return (beat, bpm)
        }
        return RawBeatmap(
            notes: notes.map { note in
                // type 0 = 赤 / 1 = 青 / 3 = 爆弾（切らないので除く）
                RawNote(
                    beat: note.time,
                    lineIndex: note.lineIndex,
                    lineLayer: note.lineLayer,
                    color: note.type.flatMap { (0...1).contains($0) ? $0 : nil },
                    cutDirection: note.cutDirection
                )
            },
            bpmChanges: fromEvents + fromChanges
        )
    }

    private enum CodingKeys: String, CodingKey {
        case notes = "_notes"
        case events = "_events"
        case bpmChanges = "_BPMChanges"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notes = container.lenient(LossyDecodableArray<BeatmapV2Note>.self, forKey: .notes)?.elements ?? []
        events = container.lenient(LossyDecodableArray<BeatmapV2Event>.self, forKey: .events)?.elements ?? []
        bpmChanges = container.lenient(LossyDecodableArray<BeatmapV2BPMChange>.self, forKey: .bpmChanges)?.elements ?? []
    }
}

nonisolated private struct BeatmapV3: Decodable {
    let colorNotes: [BeatmapV3ColorNote]
    let bpmEvents: [BeatmapV3BPMEvent]

    var raw: RawBeatmap {
        RawBeatmap(
            notes: colorNotes.map { note in
                RawNote(
                    beat: note.beat,
                    lineIndex: note.lineIndex,
                    lineLayer: note.lineLayer,
                    color: note.color,
                    cutDirection: note.direction
                )
            },
            bpmChanges: bpmEvents.compactMap { event in
                guard let beat = event.beat, let bpm = event.bpm else { return nil }
                return (beat, bpm)
            }
        )
    }

    private enum CodingKeys: String, CodingKey {
        case colorNotes, bpmEvents
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 爆弾（`bombNotes`）・壁・アーク・チェーンは使わないので読まない
        colorNotes = container.lenient(LossyDecodableArray<BeatmapV3ColorNote>.self, forKey: .colorNotes)?.elements ?? []
        bpmEvents = container.lenient(LossyDecodableArray<BeatmapV3BPMEvent>.self, forKey: .bpmEvents)?.elements ?? []
    }
}

nonisolated private struct BeatmapV2Note: Decodable {
    let time: Double?
    let lineIndex: Int?
    let lineLayer: Int?
    let type: Int?
    let cutDirection: Int?

    private enum CodingKeys: String, CodingKey {
        case time = "_time"
        case lineIndex = "_lineIndex"
        case lineLayer = "_lineLayer"
        case type = "_type"
        case cutDirection = "_cutDirection"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        time = container.lenient(Double.self, forKey: .time)
        lineIndex = container.lenient(Int.self, forKey: .lineIndex)
        lineLayer = container.lenient(Int.self, forKey: .lineLayer)
        type = container.lenient(Int.self, forKey: .type)
        cutDirection = container.lenient(Int.self, forKey: .cutDirection)
    }
}

nonisolated private struct BeatmapV2Event: Decodable {
    let time: Double?
    let type: Int?
    let floatValue: Double?

    private enum CodingKeys: String, CodingKey {
        case time = "_time"
        case type = "_type"
        case floatValue = "_floatValue"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        time = container.lenient(Double.self, forKey: .time)
        type = container.lenient(Int.self, forKey: .type)
        floatValue = container.lenient(Double.self, forKey: .floatValue)
    }
}

nonisolated private struct BeatmapV2BPMChange: Decodable {
    let time: Double?
    let bpm: Double?

    private enum CodingKeys: String, CodingKey {
        case time = "_time"
        case bpm = "_BPM"
        case lowercaseBPM = "_bpm"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        time = container.lenient(Double.self, forKey: .time)
        bpm = container.lenient(Double.self, forKey: .bpm) ?? container.lenient(Double.self, forKey: .lowercaseBPM)
    }
}

nonisolated private struct BeatmapV3ColorNote: Decodable {
    let beat: Double?
    let lineIndex: Int?
    let lineLayer: Int?
    let color: Int?
    let direction: Int?

    private enum CodingKeys: String, CodingKey {
        case beat = "b"
        case lineIndex = "x"
        case lineLayer = "y"
        case color = "c"
        case direction = "d"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        beat = container.lenient(Double.self, forKey: .beat)
        lineIndex = container.lenient(Int.self, forKey: .lineIndex)
        lineLayer = container.lenient(Int.self, forKey: .lineLayer)
        color = container.lenient(Int.self, forKey: .color)
        direction = container.lenient(Int.self, forKey: .direction)
    }
}

nonisolated private struct BeatmapV3BPMEvent: Decodable {
    let beat: Double?
    let bpm: Double?

    private enum CodingKeys: String, CodingKey {
        case beat = "b"
        case bpm = "m"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        beat = container.lenient(Double.self, forKey: .beat)
        bpm = container.lenient(Double.self, forKey: .bpm)
    }
}
