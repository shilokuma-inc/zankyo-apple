import Foundation
import Testing
@testable import Zankyo

struct PlayResultTests {
    @Test(arguments: [
        (0.95, Rank.rankSS), (0.9, .rankSS), (0.89, .rankS), (0.8, .rankS), (0.7, .rankA), (0.65, .rankA),
        (0.5, .rankB), (0.4, .rankC), (0.35, .rankC), (0.25, .rankD), (0.2, .rankD), (0.1, .rankE), (0, .rankE)
    ])
    func ranksFollowBeatSaber(accuracy: Double, expected: Rank) {
        #expect(Rank(accuracy: accuracy) == expected)
    }

    @Test
    func summarizesJudge() {
        var judge = Judge(notes: [
            FaceNote(beat: 2, time: 1, direction: .left),
            FaceNote(beat: 4, time: 2, direction: .right)
        ])
        judge.cut(CutEvent(timestamp: 0, direction: .left, peakRate: 4), at: 1)
        judge.advance(to: 5)
        let playedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let result = judge.result(playedAt: playedAt)

        #expect(result.score == 115)
        #expect(result.maxScore == 230)
        #expect(result.accuracy == 0.5)
        #expect(result.rank == .rankB)
        #expect(result.hitCount == 1)
        #expect(result.missCount == 1)
        #expect(result.noteCount == 2)
        #expect(!result.isFullCombo)
        #expect(result.scoringVersion == ScoringRules.version)
    }

    @Test
    func emptyBeatmapHasZeroAccuracy() {
        #expect(Self.result(score: 0, maxScore: 0).accuracy == 0)
    }

    static func result(score: Int, maxScore: Int = 1_000, scoringVersion: Int = ScoringRules.version) -> PlayResult {
        PlayResult(
            score: score,
            maxScore: maxScore,
            maxCombo: 10,
            hitCount: 10,
            missCount: 0,
            noteCount: 10,
            playedAt: Date(timeIntervalSince1970: 1_800_000_000),
            scoringVersion: scoringVersion
        )
    }
}

struct HighScoreStoreTests {
    private static let key = ScoreKey(mapHash: String(repeating: "ab", count: 20), characteristic: .standard, difficulty: .expert)

    @Test
    func keepsOnlyBestAndPersists() throws {
        let file = try Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = HighScoreStore(fileURL: file)

        #expect(store.best(for: Self.key) == nil)
        #expect(store.record(PlayResultTests.result(score: 500), for: Self.key))
        #expect(!store.record(PlayResultTests.result(score: 400), for: Self.key))
        #expect(!store.record(PlayResultTests.result(score: 500), for: Self.key))
        #expect(store.record(PlayResultTests.result(score: 600), for: Self.key))

        let reloaded = HighScoreStore(fileURL: file)
        #expect(reloaded.best(for: Self.key) == PlayResultTests.result(score: 600))
        let otherDifficulty = ScoreKey(mapHash: Self.key.mapHash, characteristic: .standard, difficulty: .hard)
        #expect(reloaded.best(for: otherDifficulty) == nil)
    }

    @Test
    func writesDocumentedFormat() throws {
        let file = try Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        HighScoreStore(fileURL: file).record(PlayResultTests.result(score: 500), for: Self.key)

        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect(json["version"] as? Int == HighScoreStore.fileVersion)
        let records = try #require(json["records"] as? [String: Any])
        let record = try #require(records["s1/\(Self.key.mapHash)/Standard/Expert"] as? [String: Any])
        #expect(record["score"] as? Int == 500)
        #expect(record["playedAt"] as? String == "2027-01-15T08:00:00Z")
        #expect(record["scoringVersion"] as? Int == 1)
    }

    @Test
    func doesNotCompareAcrossScoringVersions() throws {
        let file = try Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = HighScoreStore(fileURL: file)

        // 古い計算方法の高い点数は、今の計算方法のハイスコアにしない
        store.record(PlayResultTests.result(score: 9_999, scoringVersion: 0), for: Self.key)
        #expect(store.best(for: Self.key) == nil)
        #expect(store.record(PlayResultTests.result(score: 100), for: Self.key))
    }

    @Test
    func movesBrokenFileAsideAndStartsEmpty() throws {
        let file = try Self.temporaryFile()
        let directory = file.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not json".utf8).write(to: file)

        let store = HighScoreStore(fileURL: file)

        #expect(store.best(for: Self.key) == nil)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        #expect(names.contains { $0.hasPrefix("HighScores.json.broken-") })
        #expect(store.record(PlayResultTests.result(score: 1), for: Self.key))
    }

    @Test
    func doesNotOverwriteNewerFormat() throws {
        let file = try Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let newer = Data(#"{ "version": 99, "records": {}, "somethingNew": true }"#.utf8)
        try newer.write(to: file)

        let store = HighScoreStore(fileURL: file)
        store.record(PlayResultTests.result(score: 500), for: Self.key)

        #expect(store.isReadOnly)
        #expect(try Data(contentsOf: file) == newer)
    }

    @Test
    func doesNotMoveNewerFormatWithUnknownRecords() throws {
        let file = try Self.temporaryFile()
        let directory = file.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        // 新しいアプリでは記録の形が変わっているかもしれない（必須の項目が増えた・型が変わった）
        let newer = Data(#"{ "version": 2, "records": { "s2/abc/Standard/Expert": { "points": "many" } } }"#.utf8)
        try newer.write(to: file)

        let store = HighScoreStore(fileURL: file)
        store.record(PlayResultTests.result(score: 500), for: Self.key)

        #expect(store.isReadOnly)
        #expect(try Data(contentsOf: file) == newer)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        #expect(names == ["HighScores.json"])
    }

    private static func temporaryFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ZankyoTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "HighScores.json", directoryHint: .notDirectory)
    }
}

struct GameSessionResultTests {
    @Test
    func finishingRecordsHighScore() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ZankyoTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HighScoreStore(fileURL: directory.appending(path: "HighScores.json"))
        let key = ScoreKey(mapHash: String(repeating: "cd", count: 20), characteristic: .standard, difficulty: .easy)
        let notes = [FaceNote(beat: 2, time: 1, direction: nil)]
        let session = GameSession(
            notes: notes,
            clock: SilentSongClock(duration: 3),
            input: RecordedMotionInput(samples: []),
            scoreKey: key,
            highScores: store
        )

        await session.play()
        session.finish()

        let result = try #require(session.result)
        #expect(session.phase == .finished)
        #expect(result.missCount == 1)
        #expect(session.isNewRecord)
        #expect(session.previousBest == nil)
        #expect(store.best(for: key) == result)
    }
}
