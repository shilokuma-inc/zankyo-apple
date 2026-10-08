import Foundation
import os

/// アプリに付属のサンプル楽曲の 1 曲。曲・譜面・ジャケットは `scripts/sample-songs` で生成した、取り込んだ譜面と同じ形の ZIP
nonisolated struct SampleSong: Sendable, Hashable {
    let id: String
    /// 譜面ハッシュ（beatsaver と同じ方式）。ライブラリの ID と、置き場所のファイル名（`Downloads/<hash>.zip`）に使う
    let hash: String
    let songName: String
    let songAuthorName: String
    let mapperName: String
    /// 同梱した譜面 ZIP
    let archive: URL
    /// この曲を足した一覧の版。入れたことのある版より新しい曲だけを入れる
    var since = 1
}

/// 同梱したサンプル楽曲の一覧（`SampleSongs.json`）。曲を足したら版を上げる
nonisolated struct SampleSongCatalog: Sendable {
    let version: Int
    let songs: [SampleSong]

    init(version: Int, songs: [SampleSong]) {
        self.version = version
        self.songs = songs
    }

    /// 一覧を読む。無い・読めないときは空（サンプル楽曲が無くても、アプリは動く）。ZIP が見つからない曲は除く
    init(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "SampleSongs", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(CatalogFile.self, from: data) else {
            Logger(subsystem: "jp.shilokuma.Zankyo", category: "SampleSongs").error("サンプル楽曲の一覧を読めない")
            self.init(version: 0, songs: [])
            return
        }
        let songs = file.songs.compactMap { song -> SampleSong? in
            guard BeatsaverValidation.isValidHash(song.hash),
                  let archive = bundle.url(forResource: song.resource, withExtension: "zip") else { return nil }
            return SampleSong(
                id: song.id,
                hash: song.hash.lowercased(),
                songName: song.songName,
                songAuthorName: song.songAuthorName,
                mapperName: song.mapperName,
                archive: archive,
                since: song.since ?? 1
            )
        }
        self.init(version: file.version, songs: songs)
    }
}

nonisolated private struct CatalogFile: Decodable {
    nonisolated struct Song: Decodable {
        let id: String
        let resource: String
        let hash: String
        let songName: String
        let songAuthorName: String
        let mapperName: String
        /// 最初の版の一覧には無い
        let since: Int?
    }

    let version: Int
    let songs: [Song]
}

/// サンプル楽曲をライブラリに入れる。一覧の版が上がったとき（初回を含む）に、その版で足した曲を入れる。消した曲は「戻す」まで入れ直さない
///
/// 入れ方は取り込んだ曲と同じ: 譜面 ZIP を `Downloads/<hash>.zip` に置き、一覧に足す（展開は遊ぶときに行う）
struct SampleSongInstaller {
    static let installedVersionKey = "library.sampleSongsVersion"

    let catalog: SampleSongCatalog
    let downloadsDirectory: URL
    private let suiteName: String?

    /// - Parameter suiteName: テストでは専用の suite を渡す。nil なら標準の UserDefaults
    init(
        catalog: SampleSongCatalog = SampleSongCatalog(),
        downloadsDirectory: URL = AppDirectories.downloads,
        suiteName: String? = nil
    ) {
        self.catalog = catalog
        self.downloadsDirectory = downloadsDirectory
        self.suiteName = suiteName
    }

    /// まだ入れていない版の一覧なら、入れたことのある版より後に足した曲を入れる（初めてなら全曲）。
    /// 前の版の曲は、利用者が消していても入れ直さない。置けない・一覧に保存できない曲があったときは版を覚えず、次の起動で入れ直す
    func installIfNeeded(into library: LibraryStore) {
        let installedVersion = defaults.integer(forKey: Self.installedVersionKey)
        guard !library.isReadOnly, installedVersion < catalog.version else { return }
        if install(catalog.songs.filter { $0.since > installedVersion }, into: library) {
            defaults.set(catalog.version, forKey: Self.installedVersionKey)
        }
    }

    /// ライブラリに無い（消した）サンプル楽曲
    func missingSongs(in library: LibraryStore) -> [SampleSong] {
        catalog.songs.filter { !library.contains(hash: $0.hash) }
    }

    /// 消したサンプル楽曲を入れ直す
    func restore(into library: LibraryStore) {
        install(missingSongs(in: library), into: library)
    }

    /// すべての曲を一覧に足し、一覧のファイルに保存できたら true
    @discardableResult
    private func install(_ songs: [SampleSong], into library: LibraryStore) -> Bool {
        guard !library.isReadOnly else { return false }
        var installedAll = true
        for song in songs where !library.contains(hash: song.hash) {
            let destination = downloadsDirectory.appending(path: "\(song.hash).zip", directoryHint: .notDirectory)
            do {
                try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                    try FileManager.default.copyItem(at: song.archive, to: destination)
                }
            } catch {
                Logger(subsystem: "jp.shilokuma.Zankyo", category: "SampleSongs")
                    .error("サンプル楽曲を置けなかった: \(error.localizedDescription, privacy: .public)")
                installedAll = false
                continue
            }
            if !library.add(LibraryEntry(sample: song, importedAt: importedAt(of: song))) {
                installedAll = false
            }
        }
        return installedAll
    }

    /// 一覧の順に並び、取り込んだ曲より下に来るよう、古い日時を一覧の順に割り当てる
    ///
    /// 起点は初版の曲数（8）に固定する。一覧の曲数を起点にすると、曲を足したときに前の版で入れた曲と日時が重なって並びが崩れるため、
    /// 初版で入れた曲の日時（1970 年の 8〜1 秒）はそのままにし、後から足した曲はその後ろ（0 秒、-1 秒…）に続ける
    private func importedAt(of song: SampleSong) -> Date {
        let position = catalog.songs.firstIndex(of: song) ?? catalog.songs.count
        return Date(timeIntervalSince1970: TimeInterval(Self.firstCatalogCount - position))
    }

    /// 初版の一覧の曲数。並び順の日時の起点
    private static let firstCatalogCount = 8

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }
}
