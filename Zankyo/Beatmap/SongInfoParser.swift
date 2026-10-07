import Foundation

nonisolated enum SongInfoParseError: Error, Equatable, Sendable {
    /// ファイルが上限より大きい
    case tooLarge
    /// JSON として読めない、または必須の値が無い
    case malformed
    /// v2 / v4 以外の形式
    case unsupportedVersion(String)
    /// 音源のファイル名が無い・不正
    case invalidSongFilename
    /// BPM が無い・範囲外
    case invalidBPM
    /// 遊べる難易度が 1 つも無い
    case noPlayableDifficulty
}

/// `Info.dat` を読む。ZIP の中身は信用しない入力として扱い、ファイル名・数値・件数を検証する
nonisolated enum SongInfoParser {
    /// `Info.dat` の上限。通常は数 KB なので、十分な余裕を持たせる
    static let maxBytes = 1_024 * 1_024
    /// 読み込む難易度の上限（characteristic × 5 段階を大きく超えるものは打ち切る）
    static let maxDifficulties = 64
    static let bpmRange: ClosedRange<Double> = 1...1_000
    /// 試聴区間として受け付ける始まりと長さ（秒）。曲の長さの上限（15 分）に合わせる
    static let previewStartRange: ClosedRange<Double> = 0...(15 * 60)
    static let previewDurationRange: ClosedRange<Double> = 0.1...(15 * 60)

    static func parse(_ data: Data) throws(SongInfoParseError) -> SongInfo {
        guard data.count <= maxBytes else { throw .tooLarge }
        let probe: VersionProbe
        do {
            probe = try JSONDecoder().decode(VersionProbe.self, from: data)
        } catch {
            throw .malformed
        }
        switch probe.majorVersion {
        case "2":
            return try parseV2(data)
        case "4":
            return try parseV4(data)
        default:
            throw .unsupportedVersion(String((probe.version ?? "").prefix(16)))
        }
    }

    // MARK: - v2

    private static func parseV2(_ data: Data) throws(SongInfoParseError) -> SongInfo {
        let info: InfoV2
        do {
            info = try JSONDecoder().decode(InfoV2.self, from: data)
        } catch {
            throw .malformed
        }
        guard let songFilename = validFilename(info.songFilename) else { throw .invalidSongFilename }
        let bpm = try validBPM(info.beatsPerMinute)
        let difficulties = (info.difficultyBeatmapSets ?? []).flatMap { set -> [DifficultyInfo] in
            guard let characteristic = set.characteristic.flatMap(BeatmapCharacteristic.init(rawValue:)) else { return [] }
            return (set.difficultyBeatmaps ?? []).compactMap { beatmap in
                difficulty(
                    characteristic: characteristic,
                    name: beatmap.difficulty,
                    filename: beatmap.beatmapFilename,
                    noteJumpSpeed: beatmap.noteJumpMovementSpeed,
                    noteJumpStartBeatOffset: beatmap.noteJumpStartBeatOffset
                )
            }
        }
        return SongInfo(
            format: .v2,
            title: text(info.songName),
            subTitle: text(info.songSubName),
            artist: text(info.songAuthorName),
            mapper: text(info.levelAuthorName),
            bpm: bpm,
            songTimeOffset: clamp(info.songTimeOffset, to: -60...60),
            songFilename: songFilename,
            coverImageFilename: validFilename(info.coverImageFilename),
            audioDataFilename: nil,
            previewStartTime: valid(info.previewStartTime, in: previewStartRange),
            previewDuration: valid(info.previewDuration, in: previewDurationRange),
            difficulties: try playable(difficulties)
        )
    }

    // MARK: - v4

    private static func parseV4(_ data: Data) throws(SongInfoParseError) -> SongInfo {
        let info: InfoV4
        do {
            info = try JSONDecoder().decode(InfoV4.self, from: data)
        } catch {
            throw .malformed
        }
        guard let songFilename = validFilename(info.audio?.songFilename) else { throw .invalidSongFilename }
        let bpm = try validBPM(info.audio?.bpm)
        let beatmaps = info.difficultyBeatmaps ?? []
        let difficulties = beatmaps.compactMap { beatmap -> DifficultyInfo? in
            guard let characteristic = beatmap.characteristic.flatMap(BeatmapCharacteristic.init(rawValue:)) else { return nil }
            return difficulty(
                characteristic: characteristic,
                name: beatmap.difficulty,
                filename: beatmap.beatmapDataFilename,
                noteJumpSpeed: beatmap.noteJumpMovementSpeed,
                noteJumpStartBeatOffset: beatmap.noteJumpStartBeatOffset
            )
        }
        // v4 はマッパーが難易度ごとにあるので、重複を除いて出てきた順につなぐ
        var mappers: [String] = []
        for name in beatmaps.flatMap({ $0.beatmapAuthors?.mappers ?? [] }) where !mappers.contains(name) {
            mappers.append(name)
        }
        return SongInfo(
            format: .v4,
            title: text(info.song?.title),
            subTitle: text(info.song?.subTitle),
            artist: text(info.song?.author),
            mapper: text(mappers.prefix(8).joined(separator: ", ")),
            bpm: bpm,
            songTimeOffset: 0,
            songFilename: songFilename,
            coverImageFilename: validFilename(info.coverImageFilename),
            audioDataFilename: validFilename(info.audio?.audioDataFilename),
            previewStartTime: valid(info.audio?.previewStartTime, in: previewStartRange),
            previewDuration: valid(info.audio?.previewDuration, in: previewDurationRange),
            difficulties: try playable(difficulties)
        )
    }

    // MARK: - 検証

    /// ZIP 内の 1 ファイルを指す名前か。パスの区切り・`..`・絶対パス・制御文字を含むものは拒否する
    static func validFilename(_ name: String?) -> String? {
        guard let name, !name.isEmpty, name.utf8.count <= 255 else { return nil }
        guard name != ".", name != "..", !name.contains("/"), !name.contains("\\") else { return nil }
        guard !name.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else { return nil }
        return name
    }

    private static func validBPM(_ bpm: Double?) throws(SongInfoParseError) -> Double {
        guard let bpm, bpm.isFinite, bpmRange.contains(bpm) else { throw .invalidBPM }
        return bpm
    }

    private static func difficulty(
        characteristic: BeatmapCharacteristic,
        name: String?,
        filename: String?,
        noteJumpSpeed: Double?,
        noteJumpStartBeatOffset: Double?
    ) -> DifficultyInfo? {
        guard let difficulty = name.flatMap(BeatmapDifficulty.init(rawValue:)),
              let filename = validFilename(filename) else { return nil }
        return DifficultyInfo(
            characteristic: characteristic,
            difficulty: difficulty,
            beatmapFilename: filename,
            noteJumpSpeed: clamp(noteJumpSpeed, to: 0...100),
            noteJumpStartBeatOffset: clamp(noteJumpStartBeatOffset, to: -10...10)
        )
    }

    /// 同じ characteristic・難易度の重複を除き、characteristic の定義順・易しい順に並べる
    private static func playable(_ difficulties: [DifficultyInfo]) throws(SongInfoParseError) -> [DifficultyInfo] {
        var seen: Set<[String]> = []
        let unique = difficulties.prefix(maxDifficulties).filter { info in
            seen.insert([info.characteristic.rawValue, info.difficulty.rawValue]).inserted
        }
        guard !unique.isEmpty else { throw .noPlayableDifficulty }
        let order = BeatmapCharacteristic.allCases
        return unique.sorted { lhs, rhs in
            let left = order.firstIndex(of: lhs.characteristic) ?? 0
            let right = order.firstIndex(of: rhs.characteristic) ?? 0
            return left == right ? lhs.difficulty < rhs.difficulty : left < right
        }
    }

    private static func text(_ value: String?) -> String {
        BeatsaverValidation.clamp(value, maxLength: 200)
    }

    /// 範囲の中の有限の値。無い・範囲外なら nil
    private static func valid(_ value: Double?, in range: ClosedRange<Double>) -> Double? {
        guard let value, value.isFinite, range.contains(value) else { return nil }
        return value
    }

    private static func clamp(_ value: Double?, to range: ClosedRange<Double>) -> Double {
        guard let value, value.isFinite else { return 0 }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

// MARK: - JSON の形

/// 形式の判定用。v2 は `_version`、v4 は `version`
nonisolated private struct VersionProbe: Decodable {
    let version: String?

    var majorVersion: String? {
        version?.split(separator: ".").first.map(String.init)
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case legacyVersion = "_version"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = (try? container.decodeIfPresent(String.self, forKey: .version))
            ?? (try? container.decodeIfPresent(String.self, forKey: .legacyVersion))
    }
}

nonisolated private struct InfoV2: Decodable {
    let songName: String?
    let songSubName: String?
    let songAuthorName: String?
    let levelAuthorName: String?
    let beatsPerMinute: Double?
    let songTimeOffset: Double?
    let songFilename: String?
    let coverImageFilename: String?
    let previewStartTime: Double?
    let previewDuration: Double?
    let difficultyBeatmapSets: [InfoV2BeatmapSet]?

    private enum CodingKeys: String, CodingKey {
        case songName = "_songName"
        case songSubName = "_songSubName"
        case songAuthorName = "_songAuthorName"
        case levelAuthorName = "_levelAuthorName"
        case beatsPerMinute = "_beatsPerMinute"
        case songTimeOffset = "_songTimeOffset"
        case songFilename = "_songFilename"
        case coverImageFilename = "_coverImageFilename"
        case previewStartTime = "_previewStartTime"
        case previewDuration = "_previewDuration"
        case difficultyBeatmapSets = "_difficultyBeatmapSets"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        songName = container.lenient(String.self, forKey: .songName)
        songSubName = container.lenient(String.self, forKey: .songSubName)
        songAuthorName = container.lenient(String.self, forKey: .songAuthorName)
        levelAuthorName = container.lenient(String.self, forKey: .levelAuthorName)
        beatsPerMinute = container.lenient(Double.self, forKey: .beatsPerMinute)
        songTimeOffset = container.lenient(Double.self, forKey: .songTimeOffset)
        songFilename = container.lenient(String.self, forKey: .songFilename)
        coverImageFilename = container.lenient(String.self, forKey: .coverImageFilename)
        previewStartTime = container.lenient(Double.self, forKey: .previewStartTime)
        previewDuration = container.lenient(Double.self, forKey: .previewDuration)
        difficultyBeatmapSets = container.lenient(LossyDecodableArray<InfoV2BeatmapSet>.self, forKey: .difficultyBeatmapSets)?.elements
    }
}

nonisolated private struct InfoV4: Decodable {
    let song: InfoV4Song?
    let audio: InfoV4Audio?
    let coverImageFilename: String?
    let difficultyBeatmaps: [InfoV4Beatmap]?

    private enum CodingKeys: String, CodingKey {
        case song, audio, coverImageFilename, difficultyBeatmaps
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        song = container.lenient(InfoV4Song.self, forKey: .song)
        audio = container.lenient(InfoV4Audio.self, forKey: .audio)
        coverImageFilename = container.lenient(String.self, forKey: .coverImageFilename)
        difficultyBeatmaps = container.lenient(LossyDecodableArray<InfoV4Beatmap>.self, forKey: .difficultyBeatmaps)?.elements
    }
}

nonisolated private struct InfoV2BeatmapSet: Decodable {
    let characteristic: String?
    let difficultyBeatmaps: [InfoV2Beatmap]?

    private enum CodingKeys: String, CodingKey {
        case characteristic = "_beatmapCharacteristicName"
        case difficultyBeatmaps = "_difficultyBeatmaps"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        characteristic = container.lenient(String.self, forKey: .characteristic)
        difficultyBeatmaps = container.lenient(LossyDecodableArray<InfoV2Beatmap>.self, forKey: .difficultyBeatmaps)?.elements
    }
}

nonisolated private struct InfoV2Beatmap: Decodable {
    let difficulty: String?
    let beatmapFilename: String?
    let noteJumpMovementSpeed: Double?
    let noteJumpStartBeatOffset: Double?

    private enum CodingKeys: String, CodingKey {
        case difficulty = "_difficulty"
        case beatmapFilename = "_beatmapFilename"
        case noteJumpMovementSpeed = "_noteJumpMovementSpeed"
        case noteJumpStartBeatOffset = "_noteJumpStartBeatOffset"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        difficulty = container.lenient(String.self, forKey: .difficulty)
        beatmapFilename = container.lenient(String.self, forKey: .beatmapFilename)
        noteJumpMovementSpeed = container.lenient(Double.self, forKey: .noteJumpMovementSpeed)
        noteJumpStartBeatOffset = container.lenient(Double.self, forKey: .noteJumpStartBeatOffset)
    }
}

nonisolated private struct InfoV4Song: Decodable {
    let title: String?
    let subTitle: String?
    let author: String?

    private enum CodingKeys: String, CodingKey {
        case title, subTitle, author
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = container.lenient(String.self, forKey: .title)
        subTitle = container.lenient(String.self, forKey: .subTitle)
        author = container.lenient(String.self, forKey: .author)
    }
}

nonisolated private struct InfoV4Audio: Decodable {
    let songFilename: String?
    let audioDataFilename: String?
    let bpm: Double?
    let previewStartTime: Double?
    let previewDuration: Double?

    private enum CodingKeys: String, CodingKey {
        case songFilename, audioDataFilename, bpm, previewStartTime, previewDuration
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        songFilename = container.lenient(String.self, forKey: .songFilename)
        audioDataFilename = container.lenient(String.self, forKey: .audioDataFilename)
        bpm = container.lenient(Double.self, forKey: .bpm)
        previewStartTime = container.lenient(Double.self, forKey: .previewStartTime)
        previewDuration = container.lenient(Double.self, forKey: .previewDuration)
    }
}

nonisolated private struct InfoV4Beatmap: Decodable {
    let characteristic: String?
    let difficulty: String?
    let beatmapAuthors: InfoV4Authors?
    let beatmapDataFilename: String?
    let noteJumpMovementSpeed: Double?
    let noteJumpStartBeatOffset: Double?

    private enum CodingKeys: String, CodingKey {
        case characteristic, difficulty, beatmapAuthors, beatmapDataFilename, noteJumpMovementSpeed, noteJumpStartBeatOffset
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        characteristic = container.lenient(String.self, forKey: .characteristic)
        difficulty = container.lenient(String.self, forKey: .difficulty)
        beatmapAuthors = container.lenient(InfoV4Authors.self, forKey: .beatmapAuthors)
        beatmapDataFilename = container.lenient(String.self, forKey: .beatmapDataFilename)
        noteJumpMovementSpeed = container.lenient(Double.self, forKey: .noteJumpMovementSpeed)
        noteJumpStartBeatOffset = container.lenient(Double.self, forKey: .noteJumpStartBeatOffset)
    }
}

nonisolated private struct InfoV4Authors: Decodable {
    let mappers: [String]

    private enum CodingKeys: String, CodingKey {
        case mappers
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mappers = (container.lenient([String].self, forKey: .mappers) ?? []).prefix(16).map { String($0.prefix(100)) }
    }
}
