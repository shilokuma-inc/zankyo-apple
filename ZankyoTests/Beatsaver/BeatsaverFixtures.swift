import Foundation

/// beatsaver API の応答を模した自作の JSON（実データは使わない）
nonisolated enum BeatsaverFixtures {
    static let hash = "fa40913a26648327853df36717d578f531208862"

    /// マップ 1 件の JSON。`extra` はトップレベルに差し込むキー（末尾にカンマを付ける）
    static func map(id: String, extra: String = "", versions: String? = nil) -> String {
        """
        {
          "id": "\(id)",
          "name": "Believer - American Authors",
          "description": "テスト用の説明",
          \(extra)
          "uploader": { "id": 13320, "name": "novashaft" },
          "metadata": {
            "bpm": 120.0, "duration": 186, "songName": "Believer", "songSubName": "",
            "songAuthorName": "American Authors", "levelAuthorName": "NovaShaft"
          },
          "stats": { "upvotes": 241, "downvotes": 5, "score": 0.9568 },
          "uploaded": "2018-11-09T15:25:44Z",
          "automapper": false,
          "versions": \(versions ?? "[\(version())]")
        }
        """
    }

    static func version(
        hash: String = Self.hash,
        state: String = "Published",
        createdAt: String = "2018-11-09T15:25:44Z",
        downloadURL: String? = nil
    ) -> String {
        """
        {
          "hash": "\(hash)",
          "key": "1f33",
          "state": "\(state)",
          "createdAt": "\(createdAt)",
          "diffs": [
            { "njs": 10.0, "notes": 513, "nps": 1.642, "characteristic": "Standard", "difficulty": "Hard", "seconds": 312.475 },
            { "njs": 16.0, "notes": 900, "nps": 2.9, "characteristic": "Standard", "difficulty": "Expert", "seconds": 312.475 }
          ],
          "downloadURL": "\(downloadURL ?? "https://r2cdn.beatsaver.com/\(hash).zip")",
          "coverURL": "https://cdn.beatsaver.com/\(hash).jpg",
          "previewURL": "https://cdn.beatsaver.com/\(hash).mp3"
        }
        """
    }

    static func searchResponse(maps: [String], pages: Int) -> String {
        """
        { "docs": [\(maps.joined(separator: ","))], "info": { "total": \(maps.count), "pages": \(pages) } }
        """
    }
}
