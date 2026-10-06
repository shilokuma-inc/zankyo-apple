import Foundation

/// beatsaver のマップ（1 曲分の譜面セット）。
///
/// API のレスポンスは信用しない入力として扱う。必須の値（ID・遊べるバージョン）が欠けたものはデコードに失敗させ、
/// 任意の値は欠損・範囲外でも既定値に丸める。
nonisolated struct BeatsaverMap: Sendable, Hashable, Identifiable {
    /// beatsaver のキー（16 進数。例: `1f33`）
    let id: String
    let name: String
    let description: String
    let uploader: BeatsaverUser
    let metadata: BeatsaverMapMetadata
    let stats: BeatsaverMapStats
    /// マッパー自身が「自動生成（automapper）」と申告したか
    let isAutomapped: Bool
    /// AI による生成の申告（`declaredAi`）。`None` 以外は自動生成として扱う
    let declaredAI: String
    let isNSFW: Bool
    /// 公開中のバージョン。新しいものが先頭（API の並びのまま）
    let versions: [BeatsaverMapVersion]

    /// 遊ぶ対象にするバージョン。公開中（`Published`）のうち最も新しいもの
    var latestVersion: BeatsaverMapVersion? {
        versions.max { $0.createdAt < $1.createdAt }
    }

    /// beatsaver の譜面ページ。マッパーへの帰属表示として画面に出す
    var pageURL: URL {
        // id は 16 進数だけに検証済みなので、URL の組み立てに失敗しない
        URL(string: "https://beatsaver.com/maps/\(id)") ?? BeatsaverHost.site
    }

    /// 画面に出すマッパー名。譜面に書かれた名前を優先し、無ければアップロードしたユーザー名
    var mapperName: String {
        metadata.levelAuthorName.isEmpty ? uploader.name : metadata.levelAuthorName
    }

    /// 自動生成（automapper・AI）の譜面か
    var isGenerated: Bool {
        isAutomapped || declaredAI != "None"
    }
}

nonisolated struct BeatsaverUser: Sendable, Hashable {
    let id: Int
    let name: String
}

nonisolated struct BeatsaverMapMetadata: Sendable, Hashable {
    let songName: String
    let songSubName: String
    let songAuthorName: String
    let levelAuthorName: String
    /// 0 のときは不明
    let bpm: Double
    /// 秒。0 のときは不明
    let duration: Int
}

nonisolated struct BeatsaverMapStats: Sendable, Hashable {
    let upvotes: Int
    let downvotes: Int
    /// 0〜1 の評価
    let score: Double
}

nonisolated struct BeatsaverMapVersion: Sendable, Hashable {
    /// 譜面 ZIP の SHA-1（40 桁の 16 進数・小文字）
    let hash: String
    let createdAt: Date
    let downloadURL: URL
    let coverURL: URL?
    let previewURL: URL?
    let difficulties: [BeatsaverDifficulty]
}

nonisolated struct BeatsaverDifficulty: Sendable, Hashable {
    /// `Standard`・`OneSaber`・`Lightshow` など
    let characteristic: String
    /// `Easy`・`Normal`・`Hard`・`Expert`・`ExpertPlus`
    let difficulty: String
    let notes: Int
    /// 秒あたりのノーツ数
    let notesPerSecond: Double
    /// 譜面の長さ（秒）
    let seconds: Double
}

/// 検索結果の 1 ページ
nonisolated struct BeatsaverSearchPage: Sendable, Hashable {
    let maps: [BeatsaverMap]
    /// 0 起点のページ番号
    let page: Int
    /// 全ページ数。不明なら nil
    let totalPages: Int?

    var hasNextPage: Bool {
        guard let totalPages else { return !maps.isEmpty }
        return page + 1 < totalPages
    }
}

/// 信頼するホスト。API のレスポンスに含まれる URL はここに挙げたホストのものだけを使う
nonisolated enum BeatsaverHost {
    static let api = URL(string: "https://api.beatsaver.com")!  // swiftlint:disable:this force_unwrapping
    static let site = URL(string: "https://beatsaver.com")!  // swiftlint:disable:this force_unwrapping

    /// `beatsaver.com` とそのサブドメイン（`r2cdn`・`cdn`・`cfcdn` など）を https で指す URL か
    static func isTrusted(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "beatsaver.com" || host.hasSuffix(".beatsaver.com")
    }
}

// MARK: - 検証付きのデコード

nonisolated enum BeatsaverValidation {
    /// beatsaver のキー。実際は 1〜6 桁程度の 16 進数だが、余裕を持たせて 8 桁まで受ける
    static func isValidKey(_ key: String) -> Bool {
        (1...8).contains(key.count) && key.allSatisfy(\.isHexDigit)
    }

    static func isValidHash(_ hash: String) -> Bool {
        hash.count == 40 && hash.allSatisfy(\.isHexDigit)
    }

    /// 文字列の長さを抑える（巨大な説明文などで画面やメモリを圧迫させない）
    static func clamp(_ text: String?, maxLength: Int) -> String {
        guard let text else { return "" }
        return text.count > maxLength ? String(text.prefix(maxLength)) : text
    }

    static func clamp(_ value: Double?, to range: ClosedRange<Double>) -> Double {
        guard let value, value.isFinite else { return range.lowerBound }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    static func clamp(_ value: Int?, to range: ClosedRange<Int>) -> Int {
        guard let value else { return range.lowerBound }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    static func trustedURL(_ string: String?) -> URL? {
        guard let string, let url = URL(string: string), BeatsaverHost.isTrusted(url) else { return nil }
        return url
    }
}

/// 要素ごとにデコードし、壊れた要素だけを捨てる配列
nonisolated struct LossyDecodableArray<Element: Decodable>: Decodable {
    let elements: [Element]

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                // 壊れた要素を読み飛ばす。読み飛ばせなければ、そこで打ち切る
                guard (try? container.decode(DiscardedValue.self)) != nil else { break }
            }
        }
        self.elements = elements
    }

    private struct DiscardedValue: Decodable {}
}

extension BeatsaverMap: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, name, description, uploader, metadata, stats, automapper, declaredAi, nsfw, versions
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        guard BeatsaverValidation.isValidKey(id) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "不正なキー: \(id.prefix(16))")
        }
        let versions = try container.decodeIfPresent(LossyDecodableArray<BeatsaverMapVersion>.self, forKey: .versions)?.elements ?? []
        guard !versions.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .versions, in: container, debugDescription: "遊べるバージョンが無い")
        }
        self.id = id
        self.name = BeatsaverValidation.clamp(try container.decodeIfPresent(String.self, forKey: .name), maxLength: 200)
        self.description = BeatsaverValidation.clamp(try? container.decodeIfPresent(String.self, forKey: .description), maxLength: 2_000)
        self.uploader = (try? container.decodeIfPresent(BeatsaverUser.self, forKey: .uploader)) ?? BeatsaverUser(id: 0, name: "")
        self.metadata = (try? container.decodeIfPresent(BeatsaverMapMetadata.self, forKey: .metadata)) ?? .empty
        self.stats = (try? container.decodeIfPresent(BeatsaverMapStats.self, forKey: .stats)) ?? .empty
        self.isAutomapped = (try? container.decodeIfPresent(Bool.self, forKey: .automapper)) ?? false
        self.declaredAI = BeatsaverValidation.clamp(try? container.decodeIfPresent(String.self, forKey: .declaredAi), maxLength: 32)
            .nonEmpty ?? "None"
        self.isNSFW = (try? container.decodeIfPresent(Bool.self, forKey: .nsfw)) ?? false
        self.versions = versions
    }
}

extension BeatsaverUser: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, name
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = BeatsaverValidation.clamp(try? container.decodeIfPresent(Int.self, forKey: .id), to: 0...Int(Int32.max))
        self.name = BeatsaverValidation.clamp(try? container.decodeIfPresent(String.self, forKey: .name), maxLength: 100)
    }
}

extension BeatsaverMapMetadata: Decodable {
    nonisolated static let empty = Self(songName: "", songSubName: "", songAuthorName: "", levelAuthorName: "", bpm: 0, duration: 0)

    private enum CodingKeys: String, CodingKey {
        case songName, songSubName, songAuthorName, levelAuthorName, bpm, duration
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.songName = BeatsaverValidation.clamp(try? container.decodeIfPresent(String.self, forKey: .songName), maxLength: 200)
        self.songSubName = BeatsaverValidation.clamp(try? container.decodeIfPresent(String.self, forKey: .songSubName), maxLength: 200)
        self.songAuthorName = BeatsaverValidation.clamp(
            try? container.decodeIfPresent(String.self, forKey: .songAuthorName),
            maxLength: 200
        )
        self.levelAuthorName = BeatsaverValidation.clamp(
            try? container.decodeIfPresent(String.self, forKey: .levelAuthorName),
            maxLength: 200
        )
        self.bpm = BeatsaverValidation.clamp(try? container.decodeIfPresent(Double.self, forKey: .bpm), to: 0...1_000)
        // 1 曲 1 時間までに丸める
        self.duration = BeatsaverValidation.clamp(try? container.decodeIfPresent(Int.self, forKey: .duration), to: 0...3_600)
    }
}

extension BeatsaverMapStats: Decodable {
    nonisolated static let empty = Self(upvotes: 0, downvotes: 0, score: 0)

    private enum CodingKeys: String, CodingKey {
        case upvotes, downvotes, score
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.upvotes = BeatsaverValidation.clamp(try? container.decodeIfPresent(Int.self, forKey: .upvotes), to: 0...Int(Int32.max))
        self.downvotes = BeatsaverValidation.clamp(try? container.decodeIfPresent(Int.self, forKey: .downvotes), to: 0...Int(Int32.max))
        self.score = BeatsaverValidation.clamp(try? container.decodeIfPresent(Double.self, forKey: .score), to: 0...1)
    }
}

extension BeatsaverMapVersion: Decodable {
    private enum CodingKeys: String, CodingKey {
        case hash, state, createdAt, downloadURL, coverURL, previewURL, diffs
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hash = try container.decode(String.self, forKey: .hash)
        guard BeatsaverValidation.isValidHash(hash) else {
            throw DecodingError.dataCorruptedError(forKey: .hash, in: container, debugDescription: "不正なハッシュ")
        }
        // 公開中のもの以外（テスト中・下書き）は遊ぶ対象にしない。state が無ければ公開中とみなす
        let state = try? container.decodeIfPresent(String.self, forKey: .state)
        guard state == nil || state == "Published" else {
            throw DecodingError.dataCorruptedError(forKey: .state, in: container, debugDescription: "公開中ではない")
        }
        guard let downloadURL = BeatsaverValidation.trustedURL(try? container.decodeIfPresent(String.self, forKey: .downloadURL)) else {
            throw DecodingError.dataCorruptedError(forKey: .downloadURL, in: container, debugDescription: "信頼できないダウンロード URL")
        }
        self.hash = hash.lowercased()
        self.createdAt = (try? container.decodeIfPresent(Date.self, forKey: .createdAt)) ?? .distantPast
        self.downloadURL = downloadURL
        self.coverURL = BeatsaverValidation.trustedURL(try? container.decodeIfPresent(String.self, forKey: .coverURL))
        self.previewURL = BeatsaverValidation.trustedURL(try? container.decodeIfPresent(String.self, forKey: .previewURL))
        let difficulties = (try? container.decodeIfPresent(LossyDecodableArray<BeatsaverDifficulty>.self, forKey: .diffs))?.elements ?? []
        // 1 バージョンの難易度は characteristic × 5 段階なので、数十を超えるものは打ち切る
        self.difficulties = Array(difficulties.prefix(64))
    }
}

extension BeatsaverDifficulty: Decodable {
    private enum CodingKeys: String, CodingKey {
        case characteristic, difficulty, notes, nps, seconds
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.characteristic = BeatsaverValidation.clamp(try container.decode(String.self, forKey: .characteristic), maxLength: 64)
        self.difficulty = BeatsaverValidation.clamp(try container.decode(String.self, forKey: .difficulty), maxLength: 32)
        self.notes = BeatsaverValidation.clamp(try? container.decodeIfPresent(Int.self, forKey: .notes), to: 0...1_000_000)
        self.notesPerSecond = BeatsaverValidation.clamp(try? container.decodeIfPresent(Double.self, forKey: .nps), to: 0...1_000)
        self.seconds = BeatsaverValidation.clamp(try? container.decodeIfPresent(Double.self, forKey: .seconds), to: 0...3_600)
    }
}

private extension String {
    nonisolated var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
