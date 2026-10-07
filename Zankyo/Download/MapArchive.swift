import Foundation
import ZIPFoundation

nonisolated enum MapArchiveError: Error, Equatable, Sendable {
    /// ZIP として読めない・`Info.dat` や譜面ファイルが無い・名前が不正
    case invalidMap
    /// 展開した量やファイル数が上限を超えた
    case tooLarge
    /// 展開したファイルを書けなかった（空き容量不足など）
    case storage
}

/// 譜面 ZIP の読み取り。ZIP の中身は信用しない入力として扱い、直下のファイルだけを、検証した名前で引けるようにする
///
/// Beat Saber はファイル名の大文字・小文字を区別しないので、名前は小文字にして引く
nonisolated struct MapArchive {
    /// ZIP の中のファイル数の上限（中央ディレクトリが巨大なものは読まない）
    static let maxEntries = 4_096

    /// 直下のファイル（小文字にした名前 → エントリ）。フォルダ・リンク・パスを含む名前は除く
    let entries: [String: Entry]
    private let archive: Archive

    init(url: URL) throws(MapArchiveError) {
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw .invalidMap
        }
        var entries: [String: Entry] = [:]
        for (index, entry) in archive.enumerated() {
            guard index < Self.maxEntries else { throw .tooLarge }
            guard entry.type == .file, let name = SongInfoParser.validFilename(entry.path) else { continue }
            entries[name.lowercased()] = entries[name.lowercased()] ?? entry
        }
        self.entries = entries
    }

    func entry(named name: String) -> Entry? {
        entries[name.lowercased()]
    }

    func read(_ entry: Entry, limit: UInt64) throws(MapArchiveError) -> Data {
        var data = Data()
        _ = try stream(entry, limit: limit) { data.append($0) }
        return data
    }

    /// 展開しながら塊ごとに渡し、展開した量を返す。宣言された大きさと、実際に展開した量の両方で上限を確かめる
    func stream(
        _ entry: Entry,
        limit: UInt64,
        consume: (Data) throws -> Void
    ) throws(MapArchiveError) -> UInt64 {
        guard entry.uncompressedSize <= limit else { throw .tooLarge }
        var received: UInt64 = 0
        var failure: MapArchiveError?
        do {
            // CRC32 も確かめる（壊れた ZIP はここで失敗する）
            _ = try archive.extract(entry, skipCRC32: false) { chunk in
                received += UInt64(chunk.count)
                guard received <= limit else {
                    failure = .tooLarge
                    throw CocoaError(.fileReadTooLarge)
                }
                do {
                    try consume(chunk)
                } catch {
                    failure = .storage
                    throw error
                }
            }
        } catch {
            throw failure ?? .invalidMap
        }
        return received
    }
}
