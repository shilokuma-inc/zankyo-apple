import Foundation
import Testing
@testable import Zankyo

struct BeatsaverMapTests {
    private func decode(_ json: String) throws -> BeatsaverMap {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BeatsaverMap.self, from: Data(json.utf8))
    }

    @Test
    func toleratesMissingOptionalFields() throws {
        let map = try decode(#"{"id": "ab", "versions": [\#(BeatsaverFixtures.version())]}"#)

        #expect(map.name.isEmpty)
        #expect(map.metadata == .empty)
        #expect(map.stats == .empty)
        #expect(map.mapperName.isEmpty)
        #expect(!map.isNSFW)
        #expect(!map.isGenerated)
    }

    @Test
    func toleratesWrongTypesInOptionalFields() throws {
        let map = try decode(#"{"id": "ab", "name": 42, "description": [], "nsfw": "yes", "versions": [\#(BeatsaverFixtures.version())]}"#)

        #expect(map.name.isEmpty)
        #expect(map.description.isEmpty)
        #expect(!map.isNSFW)
    }

    @Test
    func clampsOutOfRangeValues() throws {
        let json = #"""
        {
          "id": "ab",
          "metadata": { "bpm": -5, "duration": 99999999, "levelAuthorName": "" },
          "stats": { "upvotes": -1, "score": 3.5 },
          "uploader": { "id": 1, "name": "uploader" },
          "versions": [\#(BeatsaverFixtures.version())]
        }
        """#
        let map = try decode(json)

        #expect(map.metadata.bpm == 0)
        #expect(map.metadata.duration == 3_600)
        #expect(map.stats.upvotes == 0)
        #expect(map.stats.score == 1)
        // 譜面にマッパー名が無ければ、アップロードしたユーザー名を出す
        #expect(map.mapperName == "uploader")
    }

    @Test
    func truncatesHugeStrings() throws {
        let huge = String(repeating: "あ", count: 10_000)
        let map = try decode(#"{"id": "ab", "name": "\#(huge)", "description": "\#(huge)", "versions": [\#(BeatsaverFixtures.version())]}"#)

        #expect(map.name.count == 200)
        #expect(map.description.count == 2_000)
    }

    @Test
    func rejectsMapWithoutPlayableVersion() {
        #expect(throws: DecodingError.self) {
            try decode(#"{"id": "ab", "versions": []}"#)
        }
        #expect(throws: DecodingError.self) {
            try decode(#"{"id": "ab"}"#)
        }
    }

    @Test(arguments: [
        "http://r2cdn.beatsaver.com/a.zip",
        "https://evil.example.com/a.zip",
        "https://beatsaver.com.evil.example/a.zip",
        "file:///etc/passwd",
        "not a url"
    ])
    func dropsVersionWithUntrustedDownloadURL(url: String) {
        let json = #"{"id": "ab", "versions": [\#(BeatsaverFixtures.version(downloadURL: url))]}"#

        #expect(throws: DecodingError.self) {
            try decode(json)
        }
    }

    @Test
    func dropsUnpublishedAndMalformedVersions() throws {
        let versions = [
            BeatsaverFixtures.version(hash: String(repeating: "1", count: 40), state: "Testplay"),
            BeatsaverFixtures.version(hash: "nothex"),
            BeatsaverFixtures.version(hash: String(repeating: "2", count: 40))
        ].joined(separator: ",")
        let map = try decode(#"{"id": "ab", "versions": [\#(versions)]}"#)

        #expect(map.versions.map(\.hash) == [String(repeating: "2", count: 40)])
    }

    @Test
    func dropsVersionWithMalformedStateButKeepsMissingState() throws {
        let published = #""state": "Published""#
        let versions = [
            BeatsaverFixtures.version(hash: String(repeating: "3", count: 40)).replacingOccurrences(of: published, with: #""state": 1"#),
            BeatsaverFixtures.version(hash: String(repeating: "4", count: 40)).replacingOccurrences(of: published, with: #""state": null"#)
        ].joined(separator: ",")
        let map = try decode(#"{"id": "ab", "versions": [\#(versions)]}"#)

        #expect(map.versions.map(\.hash) == [String(repeating: "4", count: 40)])
    }

    @Test
    func latestVersionIsTheNewest() throws {
        let versions = [
            BeatsaverFixtures.version(hash: String(repeating: "a", count: 40), createdAt: "2020-01-01T00:00:00Z"),
            BeatsaverFixtures.version(hash: String(repeating: "b", count: 40), createdAt: "2024-01-01T00:00:00Z")
        ].joined(separator: ",")
        let map = try decode(#"{"id": "ab", "versions": [\#(versions)]}"#)

        #expect(map.latestVersion?.hash == String(repeating: "b", count: 40))
    }

    @Test
    func untrustedCoverAndPreviewBecomeNil() throws {
        let version = BeatsaverFixtures.version()
            .replacingOccurrences(of: "https://cdn.beatsaver.com", with: "https://example.com")
        let map = try decode(#"{"id": "ab", "versions": [\#(version)]}"#)

        #expect(map.latestVersion?.coverURL == nil)
        #expect(map.latestVersion?.previewURL == nil)
    }

    @Test
    func trustedHosts() throws {
        #expect(BeatsaverHost.isTrusted(try #require(URL(string: "https://beatsaver.com/maps/1"))))
        #expect(BeatsaverHost.isTrusted(try #require(URL(string: "https://r2cdn.beatsaver.com/a.zip"))))
        #expect(!BeatsaverHost.isTrusted(try #require(URL(string: "https://notbeatsaver.com/a.zip"))))
        #expect(!BeatsaverHost.isTrusted(try #require(URL(string: "http://beatsaver.com/a.zip"))))
    }
}
