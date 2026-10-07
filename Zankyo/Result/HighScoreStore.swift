import Foundation
import os

/// ハイスコアを分ける単位（曲・characteristic・難易度）
nonisolated struct ScoreKey: Sendable, Hashable {
    /// 譜面 ZIP の SHA-1（beatsaver の `hash`）。同じ曲でも譜面が更新されたら別のハイスコアにする
    let mapHash: String
    let characteristic: BeatmapCharacteristic
    let difficulty: BeatmapDifficulty

    /// 保存ファイルの中のキー。スコアの計算方法のバージョンを頭に付け、違うバージョンの点数を同じ枠で比べない
    func storageKey(scoringVersion: Int) -> String {
        "s\(scoringVersion)/\(mapHash.lowercased())/\(characteristic.rawValue)/\(difficulty.rawValue)"
    }
}

/// 曲・難易度ごとのハイスコア。Application Support 配下の JSON ファイル 1 つに保存する
///
/// 保存形式（`HighScores.json`。形式を変えるときは `fileVersion` を上げ、古い形式を読めるようにする）:
/// ```json
/// {
///   "version": 1,
///   "records": {
///     "s1/<譜面の SHA-1>/Standard/Expert": {
///       "score": 12345, "maxScore": 23000, "maxCombo": 120, "hitCount": 118, "missCount": 2,
///       "noteCount": 120, "playedAt": "2026-10-07T12:00:00Z", "scoringVersion": 1
///     }
///   }
/// }
/// ```
/// - キーの `s1` は `ScoringRules.version`。計算方法を変えたら新しい枠に記録し、古い枠は消さずに残す
/// - 読めないファイルは `.broken-<時刻>` を付けて退避し、空から始める。新しいアプリが書いた未知の版は上書きしない
final class HighScoreStore {
    static let fileVersion = 1

    private let fileURL: URL
    private var records: [String: PlayResult] = [:]
    /// 新しいアプリが書いた形式などで、上書きすると記録を壊すとき
    private(set) var isReadOnly = false
    private let logger = Logger(subsystem: "jp.shilokuma.Zankyo", category: "HighScoreStore")

    init(fileURL: URL = HighScoreStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    nonisolated static var defaultFileURL: URL {
        URL.applicationSupportDirectory.appending(path: "Zankyo/HighScores.json", directoryHint: .notDirectory)
    }

    /// 今の計算方法でのハイスコア
    func best(for key: ScoreKey) -> PlayResult? {
        records[key.storageKey(scoringVersion: ScoringRules.version)]
    }

    /// 結果を記録し、ハイスコアを更新したら true を返す
    @discardableResult
    func record(_ result: PlayResult, for key: ScoreKey) -> Bool {
        let storageKey = key.storageKey(scoringVersion: result.scoringVersion)
        if let current = records[storageKey], current.score >= result.score {
            return false
        }
        records[storageKey] = result
        save()
        return true
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let file = try Self.decoder.decode(HighScoreFile.self, from: data)
            guard file.version <= Self.fileVersion else {
                // 新しいアプリが書いた形式。読めた分だけ使い、上書きしない
                isReadOnly = true
                records = file.records ?? [:]
                return
            }
            records = file.records ?? [:]
        } catch {
            logger.error("ハイスコアのファイルを読めないので退避する: \(error.localizedDescription, privacy: .public)")
            let broken = fileURL.appendingPathExtension("broken-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.moveItem(at: fileURL, to: broken)
        }
    }

    private func save() {
        guard !isReadOnly else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try Self.encoder.encode(HighScoreFile(version: Self.fileVersion, records: records))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("ハイスコアを保存できなかった: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    nonisolated private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// 保存ファイルの形
nonisolated private struct HighScoreFile: Codable {
    let version: Int
    let records: [String: PlayResult]?
}
