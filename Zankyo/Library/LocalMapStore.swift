import Foundation

nonisolated enum MapLoadError: Error, Equatable, Sendable {
    /// 取り込んだ ZIP が無い（消された・壊れた）
    case notDownloaded
    /// ZIP や展開したファイルが譜面として読めない
    case invalidMap
    /// 展開した量・ファイルが上限を超えた
    case tooLarge
    /// 展開したファイルを書けなかった（空き容量不足など）
    case storage
    /// 曲情報（Info.dat）が読めない
    case invalidInfo
    /// 遊べる種類（Standard など）の難易度が無い
    case noPlayableDifficulty
    /// 難易度譜面の形式に対応していない（v4 など）
    case unsupportedBeatmap(String)
    /// 難易度譜面が読めない・切るノーツが無い
    case invalidBeatmap
    /// 音源が読めない・再生できない形式
    case audio(VorbisDecodeError)

    /// 画面に出す説明
    var message: String {
        switch self {
        case .notDownloaded:
            "曲のファイルが見つかりません。取り込み直してください"
        case .invalidMap, .invalidInfo:
            "譜面のファイルが読めません。取り込み直してください"
        case .noPlayableDifficulty:
            "遊べる難易度がありません（Lightshow など、対応していない種類の譜面だけが入っています）"
        case .tooLarge:
            "譜面のファイルが大きすぎるため遊べません"
        case .storage:
            "譜面を展開できませんでした。端末の空き容量を確かめてください"
        case .unsupportedBeatmap(let version):
            "この難易度の譜面の形式（\(version.isEmpty ? "不明" : "v\(version)")）にはまだ対応していません"
        case .invalidBeatmap:
            "この難易度の譜面が読めないか、切るノーツがありません"
        case .audio(.tooLong):
            "曲が長すぎるため遊べません（上限 \(Int(VorbisDecoder.maxDuration / 60)) 分）"
        case .audio:
            "曲の音源を再生できません"
        }
    }
}

/// 取り込んだ曲を、遊べる形（曲情報・ノーツ・デコードした音源）に読み込む
///
/// 取り込んだ ZIP（`Downloads/<hash>.zip`）は、初めて読むときに `Maps/<hash>/` へ展開する。展開の済んだフォルダはそのまま使う。
/// 展開・パース・デコードは重いので、メインスレッドの外で行う
nonisolated struct LocalMapStore: Sendable {
    let downloadsDirectory: URL
    let mapsDirectory: URL

    init(downloadsDirectory: URL = AppDirectories.downloads, mapsDirectory: URL = AppDirectories.maps) {
        self.downloadsDirectory = downloadsDirectory
        self.mapsDirectory = mapsDirectory
    }

    /// 展開して曲情報を読む
    @concurrent
    func loadInfo(hash: String) async throws(MapLoadError) -> SongInfo {
        let folder = try extractedFolder(hash: hash)
        let data = try read("Info.dat", in: folder, limit: SongInfoParser.maxBytes)
        do {
            return try SongInfoParser.parse(data)
        } catch .noPlayableDifficulty {
            throw .noPlayableDifficulty
        } catch {
            throw .invalidInfo
        }
    }

    /// 難易度譜面を読み、頭で切るノーツに変換する
    @concurrent
    func loadNotes(hash: String, info: SongInfo, difficulty: DifficultyInfo) async throws(MapLoadError) -> [FaceNote] {
        let folder = try extractedFolder(hash: hash)
        let data = try read(difficulty.beatmapFilename, in: folder, limit: BeatmapParser.maxBytes)
        let beatmap: Beatmap
        do {
            beatmap = try BeatmapParser.parse(
                data,
                bpm: info.bpm,
                songTimeOffset: info.songTimeOffset,
                audioTimeline: audioTimeline(info: info, folder: folder)
            )
        } catch .unsupportedVersion(let version) {
            throw .unsupportedBeatmap(version)
        } catch {
            throw .invalidBeatmap
        }
        let notes = FaceNoteConverter.convert(beatmap)
        guard !notes.isEmpty else { throw .invalidBeatmap }
        return notes
    }

    /// 音源をデコードする
    @concurrent
    func loadSong(hash: String, info: SongInfo) async throws(MapLoadError) -> sending DecodedSong {
        let folder = try extractedFolder(hash: hash)
        let file = try existingFile(info.songFilename, in: folder)
        do {
            return try VorbisDecoder.decode(fileAt: file)
        } catch {
            throw .audio(error)
        }
    }

    /// v4 の音声データにある拍と秒の対応。無い・読めないときは nil（Info.dat の BPM で一定とする）
    private func audioTimeline(info: SongInfo, folder: URL) -> BeatTimeline? {
        guard let name = info.audioDataFilename,
              let data = try? read(name, in: folder, limit: AudioDataParser.maxBytes) else { return nil }
        return AudioDataParser.timeline(from: data)
    }

    /// 展開済みのフォルダ。まだなら取り込んだ ZIP を展開する
    private func extractedFolder(hash: String) throws(MapLoadError) -> URL {
        // hash を検証してからパスを作る（パスの区切りや `..` を入れない）
        guard BeatsaverValidation.isValidHash(hash) else { throw .notDownloaded }
        let key = hash.lowercased()
        let folder = mapsDirectory.appending(path: key, directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) {
            return folder
        }
        let zip = downloadsDirectory.appending(path: "\(key).zip", directoryHint: .notDirectory)
        guard FileManager.default.fileExists(atPath: zip.path(percentEncoded: false)) else { throw .notDownloaded }
        do {
            try FileManager.default.createDirectory(at: mapsDirectory, withIntermediateDirectories: true)
            try MapExtractor.extract(zipAt: zip, to: folder)
        } catch let error as MapArchiveError {
            switch error {
            case .invalidMap: throw .invalidMap
            case .tooLarge: throw .tooLarge
            case .storage: throw .storage
            }
        } catch {
            throw .storage
        }
        return folder
    }

    /// 展開したフォルダのファイル。名前は展開時に小文字にそろえてある
    private func existingFile(_ name: String, in folder: URL) throws(MapLoadError) -> URL {
        guard let valid = SongInfoParser.validFilename(name) else { throw .invalidMap }
        let file = folder.appending(path: valid.lowercased(), directoryHint: .notDirectory)
        guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { throw .invalidMap }
        return file
    }

    private func read(_ name: String, in folder: URL, limit: Int) throws(MapLoadError) -> Data {
        let file = try existingFile(name, in: folder)
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
        guard size <= limit else { throw .tooLarge }
        do {
            return try Data(contentsOf: file, options: .mappedIfSafe)
        } catch {
            throw .invalidMap
        }
    }
}
