import AVFoundation
import Foundation
import Testing
@testable import Zankyo

nonisolated struct VorbisDecoderTests {
    @Test
    func decodesStereoSong() throws {
        let song = try VorbisDecoder.decode(fileAt: try TestFixtures.sineSong)

        #expect(song.format.channelCount == 2)
        #expect(song.format.sampleRate == 44_100)
        #expect(song.frameCount == 22_050)
        #expect(abs(song.duration - 0.5) < 0.001)
        // 左右のチャンネルが入れ替わらず、音が入っている
        let chunk = try #require(song.chunks.first)
        let channels = try #require(chunk.floatChannelData)
        let left = (0..<Int(chunk.frameLength)).map { abs(channels[0][$0]) }.max() ?? 0
        let right = (0..<Int(chunk.frameLength)).map { abs(channels[1][$0]) }.max() ?? 0
        #expect(left > 0.1)
        #expect(right > 0.1)
    }

    @Test
    func rejectsNonVorbisFile() throws {
        let directory = try TestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "song.egg")
        try Data("not ogg".utf8).write(to: file)

        #expect(throws: VorbisDecodeError.unreadable) {
            try VorbisDecoder.decode(fileAt: file)
        }
    }

    @Test
    func rejectsMissingFile() throws {
        let directory = try TestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(throws: VorbisDecodeError.unreadable) {
            try VorbisDecoder.decode(fileAt: directory.appending(path: "missing.egg"))
        }
    }
}
