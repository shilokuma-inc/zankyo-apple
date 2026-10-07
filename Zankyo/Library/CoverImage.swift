import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 譜面 ZIP のジャケット画像を読む。外から来た画像なので、大きさ・形式・ピクセル数を確かめ、縮小してから使う
nonisolated enum CoverImage {
    /// 読むファイルの上限
    static let maxBytes = 8 * 1024 * 1024
    /// 読む画像の縦横の上限（ピクセル）。展開すると巨大になる画像を読まない
    static let maxSourcePixels = 8192
    /// 縮小した後の長辺（ピクセル）。プレイ中のサムネイルと曲の詳細の画像に足りる大きさ
    static let maxPixelSize = 512
    /// 受け付ける形式。beatsaver のジャケットは JPEG か PNG
    static let allowedTypes: Set<String> = [UTType.jpeg.identifier, UTType.png.identifier]

    /// 画像を縮小して返す。読めない・上限を超える・対応しない形式なら nil
    static func decode(_ data: Data) -> CGImage? {
        guard !data.isEmpty, data.count <= maxBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String?, allowedTypes.contains(type),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...maxSourcePixels).contains(width), (1...maxSourcePixels).contains(height) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
