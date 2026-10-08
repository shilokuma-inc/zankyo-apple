import Foundation
import Testing
@testable import Zankyo

struct LibraryDeletionMessageTests {
    @Test
    func titleCountsSongs() throws {
        let song = try Self.entry(title: "Neon", isSample: false)

        #expect(LibraryView.deletionTitle([song]) == "この曲を消しますか？")
        #expect(LibraryView.deletionTitle([song, try Self.entry(title: "Drive", isSample: false)]) == "2 曲を消しますか？")
    }

    @Test
    func singleSongNamesTheSong() throws {
        #expect(LibraryView.deletionMessage([try Self.entry(title: "Neon", isSample: false)]).contains("「Neon」の譜面と音源"))
        #expect(LibraryView.deletionMessage([try Self.entry(title: "カノン", isSample: true)]).contains("サンプル楽曲を戻す"))
    }

    @Test
    func severalSongsTellHowToGetThemBack() throws {
        let imported = try Self.entry(title: "Neon", isSample: false)
        let sample = try Self.entry(title: "カノン", isSample: true)

        // 取り込んだ曲だけ: 取り込み直す
        let importedOnly = LibraryView.deletionMessage([imported, try Self.entry(title: "Drive", isSample: false)])
        #expect(importedOnly.hasPrefix("選んだ 2 曲の譜面と音源"))
        #expect(!importedOnly.contains("サンプル"))
        // サンプル楽曲だけ: 戻せる
        let samplesOnly = LibraryView.deletionMessage([sample, try Self.entry(title: "きらきら星", isSample: true)])
        #expect(samplesOnly.hasPrefix("選んだ 2 曲を端末から消します"))
        #expect(samplesOnly.contains("サンプル楽曲を戻す"))
        // 混ざっている: 両方
        let mixed = LibraryView.deletionMessage([imported, sample])
        #expect(mixed.contains("取り込み直して"))
        #expect(mixed.contains("サンプル楽曲は「サンプル楽曲を戻す」"))
    }

    private static func entry(title: String, isSample: Bool) throws -> LibraryEntry {
        let json = """
            {"hash":"\(String(repeating: "ab", count: 20))","mapID":"1f33","name":"\(title)","songName":"\(title)","songSubName":"",
             "songAuthorName":"Band","mapperName":"Mapper","importedAt":"2026-10-07T12:00:00Z","isSample":\(isSample)}
            """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LibraryEntry.self, from: Data(json.utf8))
    }
}
