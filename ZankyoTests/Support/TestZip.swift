import Foundation

/// テスト用の小さな ZIP（無圧縮）を作る。テストターゲットは ZIPFoundation をリンクしていないので、形式を直接書く
nonisolated enum TestZip {
    static func make(_ files: [(name: String, data: Data)]) -> Data {
        var archive = Data()
        var centralDirectory = Data()
        for file in files {
            let name = Data(file.name.utf8)
            let crc = crc32(file.data)
            let offset = UInt32(archive.count)

            // ローカルファイルヘッダ
            archive.append(le32(0x0403_4B50))
            archive.append(le16(20))  // 展開に要るバージョン
            archive.append(le16(0))  // フラグ
            archive.append(le16(0))  // 無圧縮
            archive.append(le16(0))  // 時刻
            archive.append(le16(0x21))  // 日付（1980-01-01）
            archive.append(le32(crc))
            archive.append(le32(UInt32(file.data.count)))
            archive.append(le32(UInt32(file.data.count)))
            archive.append(le16(UInt16(name.count)))
            archive.append(le16(0))
            archive.append(name)
            archive.append(file.data)

            // 中央ディレクトリ
            centralDirectory.append(le32(0x0201_4B50))
            centralDirectory.append(le16(20))  // 作成したバージョン（MS-DOS）
            centralDirectory.append(le16(20))
            centralDirectory.append(le16(0))
            centralDirectory.append(le16(0))
            centralDirectory.append(le16(0))
            centralDirectory.append(le16(0x21))
            centralDirectory.append(le32(crc))
            centralDirectory.append(le32(UInt32(file.data.count)))
            centralDirectory.append(le32(UInt32(file.data.count)))
            centralDirectory.append(le16(UInt16(name.count)))
            centralDirectory.append(le16(0))  // 拡張フィールド
            centralDirectory.append(le16(0))  // コメント
            centralDirectory.append(le16(0))  // ディスク番号
            centralDirectory.append(le16(0))  // 内部属性
            centralDirectory.append(le32(0))  // 外部属性
            centralDirectory.append(le32(offset))
            centralDirectory.append(name)
        }
        let centralDirectoryOffset = UInt32(archive.count)
        archive.append(centralDirectory)

        // 終端レコード
        archive.append(le32(0x0605_4B50))
        archive.append(le16(0))
        archive.append(le16(0))
        archive.append(le16(UInt16(files.count)))
        archive.append(le16(UInt16(files.count)))
        archive.append(le32(UInt32(centralDirectory.count)))
        archive.append(le32(centralDirectoryOffset))
        archive.append(le16(0))
        return archive
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (0xEDB8_8320 & (0 &- (crc & 1)))
            }
        }
        return ~crc
    }

    private static func le16(_ value: UInt16) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private static func le32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}
