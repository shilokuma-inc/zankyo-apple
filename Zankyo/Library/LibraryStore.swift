import Foundation
import Observation
import os

/// 取り込んだ 1 曲。画面に出す情報は取り込んだ時点の beatsaver の値（オフラインでも出せるように保存する）
nonisolated struct LibraryEntry: Sendable, Hashable, Codable, Identifiable {
    /// beatsaver の譜面ハッシュ（`hash`。ZIP 全体の SHA-1 ではない）。保存先のファイル名にも使う
    let hash: String
    /// beatsaver のキー
    let mapID: String
    let name: String
    let songName: String
    let songSubName: String
    let songAuthorName: String
    let mapperName: String
    let coverURL: URL?
    let importedAt: Date
    /// アプリに付属のサンプル楽曲（beatsaver の譜面ではないので、キーと譜面ページが無い）
    let isSample: Bool

    var id: String { hash }

    /// 画面に出す曲名。譜面に曲名が無ければマップ名
    var title: String {
        let song = [songName, songSubName].filter { !$0.isEmpty }.joined(separator: " ")
        return song.isEmpty ? name : song
    }

    /// beatsaver の譜面ページ。マッパーへの帰属表示として画面に出す（Discussion #3 Q9）。サンプル楽曲には無い
    var pageURL: URL? {
        guard !isSample else { return nil }
        return URL(string: "https://beatsaver.com/maps/\(mapID)") ?? BeatsaverHost.site
    }

    init(map: BeatsaverMap, version: BeatsaverMapVersion, importedAt: Date = Date()) {
        hash = version.hash.lowercased()
        mapID = map.id
        name = map.name
        songName = map.metadata.songName
        songSubName = map.metadata.songSubName
        songAuthorName = map.metadata.songAuthorName
        mapperName = map.mapperName
        coverURL = version.coverURL
        self.importedAt = importedAt
        isSample = false
    }

    init(sample: SampleSong, importedAt: Date) {
        hash = sample.hash.lowercased()
        mapID = ""
        name = sample.songName
        songName = sample.songName
        songSubName = ""
        songAuthorName = sample.songAuthorName
        mapperName = sample.mapperName
        coverURL = nil
        self.importedAt = importedAt
        isSample = true
    }

    enum CodingKeys: String, CodingKey {
        case hash, mapID, name, songName, songSubName, songAuthorName, mapperName, coverURL, importedAt, isSample
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hash = try container.decode(String.self, forKey: .hash)
        mapID = try container.decode(String.self, forKey: .mapID)
        name = try container.decode(String.self, forKey: .name)
        songName = try container.decode(String.self, forKey: .songName)
        songSubName = try container.decode(String.self, forKey: .songSubName)
        songAuthorName = try container.decode(String.self, forKey: .songAuthorName)
        mapperName = try container.decode(String.self, forKey: .mapperName)
        coverURL = try container.decodeIfPresent(URL.self, forKey: .coverURL)
        importedAt = try container.decode(Date.self, forKey: .importedAt)
        // サンプル楽曲より前に書いた一覧には無い
        isSample = try container.decodeIfPresent(Bool.self, forKey: .isSample) ?? false
    }

    /// 保存ファイルから読んだ値が使えるか（壊れた・書き換えられた値で、パスや URL を作らない）
    var isValid: Bool {
        BeatsaverValidation.isValidHash(hash) && (isSample || BeatsaverValidation.isValidKey(mapID))
            && coverURL.map(BeatsaverHost.isTrusted) ?? true
    }
}

nonisolated extension AppDirectories {
    /// 取り込んだ曲の一覧（`Library.json`）の置き場所
    static var library: URL {
        URL.applicationSupportDirectory.appending(path: "Zankyo/Library", directoryHint: .isDirectory)
    }

    /// 展開した譜面の置き場所（`<hash>/`）。展開は ZIP 展開のタスクで行う
    static var maps: URL {
        URL.applicationSupportDirectory.appending(path: "Zankyo/Maps", directoryHint: .isDirectory)
    }
}

/// 取り込んだ曲の一覧と、曲ごとに使っている容量。Application Support 配下に保存する
///
/// 保存形式（`Library/Library.json`。形式を変えるときは `fileVersion` を上げ、古い形式を読めるようにする）:
/// ```json
/// { "version": 1, "entries": [ { "hash": "…", "mapID": "1f33", "name": "…", "songName": "…", "songSubName": "",
///   "songAuthorName": "…", "mapperName": "…", "coverURL": "https://…", "importedAt": "2026-10-07T12:00:00Z" } ],
///   "favorites": ["…"] }
/// ```
/// - `favorites` はお気に入り（ハートを付けた曲）の譜面ハッシュ。後から足したキーなので、無いファイルはお気に入りなしとして読む
/// - 曲の容量は、取得した ZIP（`Downloads/<hash>.zip`）と展開したフォルダ（`Maps/<hash>/`）の合計
/// - 読めないファイルは `.broken-<時刻>` を付けて退避し、空から始める。新しいアプリが書いた未知の版は読むだけで上書きしない
@Observable
final class LibraryStore {
    static let fileVersion = 1

    /// 新しく取り込んだものが先
    private(set) var entries: [LibraryEntry] = []
    /// 曲ごとの容量（バイト）
    private(set) var sizes: [String: Int64] = [:]
    /// お気に入り（ハートを付けた曲）の譜面ハッシュ
    private(set) var favorites: Set<String> = []
    private(set) var isReadOnly = false

    @ObservationIgnored private let indexURL: URL
    @ObservationIgnored private let downloadsDirectory: URL
    @ObservationIgnored private let mapsDirectory: URL
    @ObservationIgnored private let logger = Logger(subsystem: "jp.shilokuma.Zankyo", category: "LibraryStore")

    init(
        directory: URL = AppDirectories.library,
        downloadsDirectory: URL = AppDirectories.downloads,
        mapsDirectory: URL = AppDirectories.maps
    ) {
        indexURL = directory.appending(path: "Library.json", directoryHint: .notDirectory)
        self.downloadsDirectory = downloadsDirectory
        self.mapsDirectory = mapsDirectory
        load()
    }

    var totalSize: Int64 {
        sizes.values.reduce(0, +)
    }

    func contains(hash: String) -> Bool {
        entries.contains { $0.hash == hash.lowercased() }
    }

    /// お気に入りの曲（一覧と同じ並び）
    var favoriteEntries: [LibraryEntry] {
        entries.filter { favorites.contains($0.hash) }
    }

    func isFavorite(_ entry: LibraryEntry) -> Bool {
        favorites.contains(entry.hash)
    }

    /// ハートを付け外しする。一覧に無い曲・読み取り専用のときは何もしない
    func setFavorite(_ isFavorite: Bool, for entry: LibraryEntry) {
        guard !isReadOnly, contains(hash: entry.hash), isFavorite != self.isFavorite(entry) else { return }
        if isFavorite {
            favorites.insert(entry.hash)
        } else {
            favorites.remove(entry.hash)
        }
        save()
    }

    func toggleFavorite(_ entry: LibraryEntry) {
        setFavorite(!isFavorite(entry), for: entry)
    }

    /// 取得し終えた曲を一覧に足す。同じ譜面がすでにあれば、新しい情報で置き換えて先頭に出す
    func add(map: BeatsaverMap, version: BeatsaverMapVersion, importedAt: Date = Date()) {
        add(LibraryEntry(map: map, version: version, importedAt: importedAt))
    }

    /// 譜面 ZIP（`Downloads/<hash>.zip`）を置き終えた曲を一覧に足す。同じ譜面がすでにあれば置き換え、取り込んだ日時の順に並べる
    func add(_ entry: LibraryEntry) {
        guard entry.isValid else { return }
        entries.removeAll { $0.hash == entry.hash }
        let position = entries.firstIndex { $0.importedAt < entry.importedAt } ?? entries.endIndex
        entries.insert(entry, at: position)
        sizes[entry.hash] = size(ofHash: entry.hash)
        save()
    }

    /// 曲を消す。取得した ZIP・展開したフォルダ・一覧の行をまとめて消し、消せたら true を返す
    ///
    /// - ファイルを消せなかったときは一覧の行を残す（残ったファイルを、一覧からもう一度消せるように）。もう無いファイルは消せたものとして扱う
    /// - 新しいアプリが書いた一覧を読んでいるとき（読み取り専用）は、一覧と食い違わないようファイルも消さない
    @discardableResult
    func delete(_ entry: LibraryEntry) -> Bool {
        guard !isReadOnly else { return false }
        // hash は読み込み時と追加時に 16 進数 40 桁に検証済みなので、パスの区切りや `..` は入らない
        for url in files(ofHash: entry.hash) {
            // 先に有無を確かめると、親フォルダを読めないときに「無い」と見誤るので、消してみてから判断する
            do {
                try FileManager.default.removeItem(at: url)
            } catch let error as CocoaError where error.code == .fileNoSuchFile {
                continue
            } catch let error as POSIXError where error.code == .ENOENT {
                continue
            } catch {
                logger.error("曲のファイルを消せなかった: \(error.localizedDescription, privacy: .public)")
                sizes[entry.hash] = size(ofHash: entry.hash)
                return false
            }
        }
        entries.removeAll { $0.hash == entry.hash }
        sizes[entry.hash] = nil
        favorites.remove(entry.hash)
        save()
        return true
    }

    /// 容量を測り直す（画面を開いたときなど）
    func refreshSizes() {
        sizes = Dictionary(uniqueKeysWithValues: entries.map { ($0.hash, size(ofHash: $0.hash)) })
    }

    private func files(ofHash hash: String) -> [URL] {
        [
            downloadsDirectory.appending(path: "\(hash).zip", directoryHint: .notDirectory),
            mapsDirectory.appending(path: hash, directoryHint: .isDirectory)
        ]
    }

    private func size(ofHash hash: String) -> Int64 {
        files(ofHash: hash).reduce(0) { $0 + Self.allocatedSize(of: $1) }
    }

    /// ファイルなら大きさ、フォルダなら中のファイルの合計。無ければ 0
    private static func allocatedSize(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        guard values.isDirectory == true else {
            return Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let fileValues = try? file.resourceValues(forKeys: keys)
            if fileValues?.isDirectory != true {
                total += Int64(fileValues?.totalFileAllocatedSize ?? fileValues?.fileSize ?? 0)
            }
        }
        return total
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        // 版を先に読む。新しいアプリが書いた形式は中身の形が違うことがあるので、全体を読めなくても退避・上書きしない
        if let probe = try? Self.decoder.decode(LibraryFileVersion.self, from: data), probe.version > Self.fileVersion {
            isReadOnly = true
            let file = try? Self.decoder.decode(LibraryFile.self, from: data)
            apply(file?.entries ?? [], favorites: file?.favorites ?? [])
            return
        }
        do {
            let file = try Self.decoder.decode(LibraryFile.self, from: data)
            apply(file.entries, favorites: file.favorites ?? [])
        } catch {
            logger.error("ライブラリのファイルを読めないので退避する: \(error.localizedDescription, privacy: .public)")
            let broken = indexURL.appendingPathExtension("broken-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.moveItem(at: indexURL, to: broken)
        }
    }

    /// 読んだ行のうち、値が使えて、ファイルが残っているものだけを出す。お気に入りは一覧に残った曲のものだけを使う
    private func apply(_ loaded: [LibraryEntry], favorites loadedFavorites: [String]) {
        var seen: Set<String> = []
        entries = loaded
            .filter { $0.isValid && seen.insert($0.hash).inserted }
            .filter { entry in
                files(ofHash: entry.hash).contains { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
            }
            .sorted { $0.importedAt > $1.importedAt }
        let hashes = Set(entries.map(\.hash))
        favorites = Set(loadedFavorites.map { $0.lowercased() }).intersection(hashes)
        refreshSizes()
    }

    private func save() {
        guard !isReadOnly else { return }
        do {
            try FileManager.default.createDirectory(at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let file = LibraryFile(version: Self.fileVersion, entries: entries, favorites: favorites.sorted())
            let data = try Self.encoder.encode(file)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            logger.error("ライブラリを保存できなかった: \(error.localizedDescription, privacy: .public)")
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

nonisolated private struct LibraryFileVersion: Decodable {
    let version: Int
}

nonisolated private struct LibraryFile: Codable {
    let version: Int
    let entries: [LibraryEntry]
    /// お気に入りの譜面ハッシュ。このキーを足す前に書いたファイルには無い
    let favorites: [String]?
}
