import AVFoundation
import Foundation
import Testing
@testable import Zankyo

@MainActor
struct AudioSongClockTests {
    @Test
    func startsStoppedAtSongStart() throws {
        let song = try VorbisDecoder.decode(fileAt: try TestFixtures.sineSong)
        let clock = AudioSongClock(song: song, now: { 100 })

        #expect(!clock.isPlaying)
        #expect(clock.currentTime == 0)
        #expect(abs(clock.duration - 0.5) < 0.001)
        // 再生していなければ、モーションの時刻を曲の時刻に直さない
        #expect(clock.songTime(atUptime: 100) == nil)
    }

    @Test
    func pauseWithoutPlayingKeepsPosition() throws {
        let song = try VorbisDecoder.decode(fileAt: try TestFixtures.sineSong)
        let clock = AudioSongClock(song: song, now: { 100 })

        clock.pause()
        clock.stop()

        #expect(!clock.isPlaying)
        #expect(clock.currentTime == 0)
    }
}
