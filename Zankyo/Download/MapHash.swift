import CryptoKit
import Foundation

/// beatsaver の `hash`（譜面ハッシュ）を、取得した ZIP の中身から計算する。
///
/// `hash` は ZIP 全体の SHA-1 ではなく、次のファイルの中身をこの順につなげたものの SHA-1:
/// - v2 / v3: `Info.dat` → `_difficultyBeatmapSets` の各 `_beatmapFilename`
/// - v4: `Info.dat` → `audio.audioDataFilename` → 各 `difficultyBeatmaps` の `beatmapDataFilename`・`lightshowDataFilename`
///
/// どちらも出てきた順で、同じファイルを何度指していても毎回足す。ZIP の中身の扱いは `MapArchive` に任せる
nonisolated enum MapHash {
    /// ハッシュの対象として展開する量の合計の上限（ZIP 爆弾よけ）。展開しながらハッシュに足すのでメモリには載せない。
    /// ライトショーだけで 1 ファイル 20MB を超え、複数の難易度で同じものを指す譜面もあるので、ZIP の上限より大きく取る
    static let maxTotalBytes: UInt64 = 256 * 1_024 * 1_024
    /// ハッシュの対象にするファイル数の上限
    static let maxFiles = 256

    static func compute(zipAt url: URL, maxTotalBytes: UInt64 = maxTotalBytes) throws(MapArchiveError) -> String {
        let archive = try MapArchive(url: url)
        guard let infoEntry = archive.entry(named: "Info.dat") else { throw .invalidMap }
        let info = try archive.read(infoEntry, limit: UInt64(SongInfoParser.maxBytes))
        let filenames = try hashedFilenames(info: info)
        guard filenames.count <= maxFiles else { throw .tooLarge }

        var hasher = Insecure.SHA1()
        hasher.update(data: info)
        var remaining = maxTotalBytes
        for filename in filenames {
            guard let entry = archive.entry(named: filename) else { throw .invalidMap }
            let size = try archive.stream(entry, limit: remaining) { hasher.update(data: $0) }
            remaining -= size
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// ハッシュに足すファイルの名前を、足す順に返す
    private static func hashedFilenames(info: Data) throws(MapArchiveError) -> [String] {
        let decoder = JSONDecoder()
        var names: [String?] = []
        do {
            let probe = try decoder.decode(HashVersionProbe.self, from: info)
            if probe.version?.hasPrefix("4") == true {
                let infoV4 = try decoder.decode(HashInfoV4.self, from: info)
                if let audioDataFilename = infoV4.audio?.audioDataFilename {
                    names.append(audioDataFilename)
                }
                for beatmap in infoV4.difficultyBeatmaps ?? [] {
                    names.append(beatmap.beatmapDataFilename)
                    if let lightshowDataFilename = beatmap.lightshowDataFilename {
                        names.append(lightshowDataFilename)
                    }
                }
            } else {
                let infoV2 = try decoder.decode(HashInfoV2.self, from: info)
                names = (infoV2.difficultyBeatmapSets ?? []).flatMap { set in
                    (set.difficultyBeatmaps ?? []).map(\.beatmapFilename)
                }
            }
        } catch {
            throw .invalidMap
        }
        guard !names.isEmpty else { throw .invalidMap }
        return try names.map { name throws(MapArchiveError) in
            guard let valid = SongInfoParser.validFilename(name) else { throw .invalidMap }
            return valid
        }
    }
}

// MARK: - Info.dat のうちハッシュに要る部分（`SongInfoParser` の型と名前がぶつからないよう接頭辞を付ける）

nonisolated private struct HashVersionProbe: Decodable {
    let version: String?
}

nonisolated private struct HashInfoV2: Decodable {
    let difficultyBeatmapSets: [HashInfoV2BeatmapSet]?

    enum CodingKeys: String, CodingKey {
        case difficultyBeatmapSets = "_difficultyBeatmapSets"
    }
}

nonisolated private struct HashInfoV2BeatmapSet: Decodable {
    let difficultyBeatmaps: [HashInfoV2Beatmap]?

    enum CodingKeys: String, CodingKey {
        case difficultyBeatmaps = "_difficultyBeatmaps"
    }
}

nonisolated private struct HashInfoV2Beatmap: Decodable {
    let beatmapFilename: String?

    enum CodingKeys: String, CodingKey {
        case beatmapFilename = "_beatmapFilename"
    }
}

nonisolated private struct HashInfoV4: Decodable {
    let audio: HashInfoV4Audio?
    let difficultyBeatmaps: [HashInfoV4Beatmap]?
}

nonisolated private struct HashInfoV4Audio: Decodable {
    let audioDataFilename: String?
}

nonisolated private struct HashInfoV4Beatmap: Decodable {
    let beatmapDataFilename: String?
    let lightshowDataFilename: String?
}
