import AVFoundation
import Foundation
import Testing
@testable import Zankyo

struct SongPreviewTests {
    @Test
    func usesInfoPreviewRange() {
        #expect(SongPreview.range(startTime: 42, duration: 12, songDuration: 180) == 42..<54)
    }

    @Test
    func fallsBackToEditorDefaults() {
        #expect(SongPreview.range(startTime: nil, duration: nil, songDuration: 180) == 12..<22)
    }

    @Test
    func shiftsRangeToFitSongEnd() {
        // 170 秒から 20 秒は曲の終わりを越えるので、終わりに合わせて前へずらす
        #expect(SongPreview.range(startTime: 170, duration: 20, songDuration: 180) == 160..<180)
        // 区間より短い曲は頭から全体
        #expect(SongPreview.range(startTime: 12, duration: 10, songDuration: 5) == 0..<5)
    }

    @Test
    func clampsDuration() {
        #expect(SongPreview.range(startTime: 30, duration: 1, songDuration: 180) == 30..<(30 + SongPreview.minimumDuration))
        #expect(SongPreview.range(startTime: 30, duration: 120, songDuration: 180) == 30..<(30 + SongPreview.maximumDuration))
    }

    @Test
    func emptyForInvalidSong() {
        #expect(SongPreview.range(startTime: 12, duration: 10, songDuration: 0).isEmpty)
        #expect(SongPreview.range(startTime: 12, duration: 10, songDuration: .nan).isEmpty)
    }
}

struct SongPreviewPlayerTests {
    /// 1 秒 1,000 フレーム・ステレオで、1 秒ごとに値が 1・2・3 の曲（塊の境目が 1 秒ごと）
    private static func makeSong() throws -> DecodedSong {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 1_000, channels: 2))
        let chunks = try (1...3).map { value in
            let chunk = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_000))
            chunk.frameLength = 1_000
            let channels = try #require(chunk.floatChannelData)
            for channel in 0..<2 {
                channels[channel].update(repeating: Float(value), count: 1_000)
            }
            return chunk
        }
        return DecodedSong(format: format, chunks: chunks)
    }

    @Test
    func copiesRangeAcrossChunksWithFades() throws {
        let loop = try #require(SongPreviewPlayer.loopBuffer(of: try Self.makeSong(), range: 0.5..<2.5, fade: 0.1))
        let channels = try #require(loop.floatChannelData)

        #expect(loop.frameLength == 2_000)
        for channel in 0..<2 {
            let samples = Array(UnsafeBufferPointer(start: channels[channel], count: 2_000))
            // 始めと終わりは無音から・無音へ
            #expect(samples[0] == 0)
            #expect(samples[1_999] == 0)
            #expect(abs(samples[50] - 0.5) < 0.0001)
            // フェードの外は元の値のまま（0.5 秒から写すので、1 秒の境目は 500 フレーム目）
            #expect(samples[100] == 1)
            #expect(samples[499] == 1)
            #expect(samples[500] == 2)
            #expect(samples[1_500] == 3)
            #expect(samples[1_899] == 3)
        }
    }

    @Test
    func clampsRangeToSongEnd() throws {
        let loop = try #require(SongPreviewPlayer.loopBuffer(of: try Self.makeSong(), range: 2.5..<10, fade: 0))

        #expect(loop.frameLength == 500)
    }

    @Test
    func emptyRangeHasNoBuffer() throws {
        #expect(SongPreviewPlayer.loopBuffer(of: try Self.makeSong(), range: 3..<10, fade: 0.1) == nil)
        #expect(SongPreviewPlayer.loopBuffer(of: try Self.makeSong(), range: 1..<1, fade: 0.1) == nil)
    }
}
