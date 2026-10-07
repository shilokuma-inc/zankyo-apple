import Foundation
import ZIPFoundation

/// 譜面 ZIP を展開する。展開するのは ZIP 直下のファイルだけで、名前は小文字にそろえる（`MapArchive` と同じ引き方にする）
///
/// 一時フォルダに書き終えてから展開先へ移すので、途中で失敗・中断しても半端なフォルダは残らない
nonisolated enum MapExtractor {
    /// 展開する量の合計の上限（ZIP 爆弾よけ）。ZIP の上限（50MB）の音源はほぼ圧縮されないので、譜面ファイルの伸びを見込んで取る
    static let maxTotalBytes: UInt64 = 512 * 1_024 * 1_024
    /// 展開するファイル数の上限
    static let maxFiles = 512

    static func extract(
        zipAt url: URL,
        to destination: URL,
        maxTotalBytes: UInt64 = maxTotalBytes
    ) throws(MapArchiveError) {
        let archive = try MapArchive(url: url)
        guard archive.entry(named: "Info.dat") != nil else { throw .invalidMap }
        guard archive.entries.count <= maxFiles else { throw .tooLarge }

        let parent = destination.deletingLastPathComponent()
        let temporary = parent.appending(path: ".extracting-\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        } catch {
            throw .storage
        }
        do throws(MapArchiveError) {
            var remaining = maxTotalBytes
            // 名前は `MapArchive` で検証済み（パスの区切りや `..` は入らない）
            for (name, entry) in archive.entries {
                let file = temporary.appending(path: name, directoryHint: .notDirectory)
                remaining -= try write(entry, of: archive, to: file, limit: remaining)
            }
            try replace(destination, with: temporary)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private static func write(_ entry: Entry, of archive: MapArchive, to file: URL, limit: UInt64) throws(MapArchiveError) -> UInt64 {
        guard FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil),
              let handle = try? FileHandle(forWritingTo: file) else {
            throw .storage
        }
        defer { try? handle.close() }
        return try archive.stream(entry, limit: limit) { try handle.write(contentsOf: $0) }
    }

    private static func replace(_ destination: URL, with temporary: URL) throws(MapArchiveError) {
        do {
            if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: temporary, to: destination)
        } catch {
            throw .storage
        }
    }
}
