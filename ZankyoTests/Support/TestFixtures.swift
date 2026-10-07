import Foundation

/// テストバンドルに入れた素材
nonisolated enum TestFixtures {
    /// 0.5 秒・ステレオ・44.1kHz の Ogg Vorbis（左 440Hz・右 660Hz のサイン波。libvorbis で自作したもの）
    static var sineSong: URL {
        get throws {
            guard let url = Bundle(for: BundleToken.self).url(forResource: "sine", withExtension: "egg") else {
                throw CocoaError(.fileNoSuchFile)
            }
            return url
        }
    }

    static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ZankyoTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

nonisolated private final class BundleToken {}
