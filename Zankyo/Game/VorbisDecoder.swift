import AVFoundation
import LibVorbis

nonisolated enum VorbisDecodeError: Error, Equatable, Sendable {
    /// Ogg Vorbis として読めない・途中で壊れている
    case unreadable
    /// 再生できない形式（3 チャンネル以上・極端なサンプルレートなど）
    case unsupportedFormat
    /// 曲が長すぎる
    case tooLong
}

/// デコードした曲。再開した位置から鳴らし直せるよう、短い塊に分けて持つ
nonisolated final class DecodedSong {
    let format: AVAudioFormat
    /// 先頭から順の塊。最後の塊以外は同じ長さ
    let chunks: [AVAudioPCMBuffer]
    let frameCount: AVAudioFramePosition

    init(format: AVAudioFormat, chunks: [AVAudioPCMBuffer]) {
        self.format = format
        self.chunks = chunks
        frameCount = chunks.reduce(0) { $0 + AVAudioFramePosition($1.frameLength) }
    }

    var duration: TimeInterval {
        Double(frameCount) / format.sampleRate
    }
}

/// beatsaver の音源（Ogg Vorbis。拡張子は `.egg` が多い）を PCM にデコードする。
/// OS 標準の Ogg Vorbis 対応は iOS 18.4 / macOS 15.4 からなので、libvorbis（vorbis-swift）を使う
nonisolated enum VorbisDecoder {
    /// 曲の長さの上限（ステレオ 44.1kHz で約 300MB）。メモリに載せるので、長すぎる曲は遊べないことにする
    static let maxDuration: TimeInterval = 15 * 60
    /// 塊の長さ（44.1kHz で約 1.5 秒）
    static let chunkFrames: AVAudioFrameCount = 65_536
    static let sampleRateRange: ClosedRange<Double> = 8_000...192_000

    static func decode(fileAt url: URL) throws(VorbisDecodeError) -> DecodedSong {
        var file = OggVorbis_File()
        guard ov_fopen(url.path(percentEncoded: false), &file) == 0 else { throw .unreadable }
        defer { ov_clear(&file) }

        let format = try format(of: &file)
        let maxFrames = AVAudioFramePosition(maxDuration * format.sampleRate)
        // 長さが分かるファイルは、デコードする前に断る
        guard ov_pcm_total(&file, -1) <= maxFrames else { throw .tooLong }

        var writer = ChunkWriter(format: format, maxFrames: maxFrames)
        var section: Int32 = 0
        while true {
            var pcm: UnsafeMutablePointer<UnsafeMutablePointer<Float>?>?
            let read = ov_read_float(&file, &pcm, Int32(writer.space), &section)
            // 途中の欠け（ページの抜け）は飛ばして続ける
            if read == Int(OV_HOLE) { continue }
            guard read >= 0 else { throw .unreadable }
            // 連結された別のストリームで形式が変わったら、そこまでにする
            guard read > 0, ov_info(&file, -1)?.pointee.channels == Int32(format.channelCount), let pcm else { break }
            try writer.append(pcm, frames: read)
        }
        return try writer.finish()
    }

    /// 再生できる形式か確かめ、PCM の形式を返す
    private static func format(of file: inout OggVorbis_File) throws(VorbisDecodeError) -> AVAudioFormat {
        guard let info = ov_info(&file, -1)?.pointee else { throw .unreadable }
        let sampleRate = Double(info.rate)
        guard (1...2).contains(info.channels), sampleRateRange.contains(sampleRate),
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(info.channels)) else {
            throw .unsupportedFormat
        }
        return format
    }
}

/// デコードした PCM を、決まった長さの塊に詰めていく
nonisolated private struct ChunkWriter {
    let format: AVAudioFormat
    let maxFrames: AVAudioFramePosition
    private var chunks: [AVAudioPCMBuffer] = []
    private var current: AVAudioPCMBuffer?
    private var total: AVAudioFramePosition = 0

    init(format: AVAudioFormat, maxFrames: AVAudioFramePosition) {
        self.format = format
        self.maxFrames = maxFrames
    }

    /// 今の塊に入る残りのフレーム数
    var space: AVAudioFrameCount {
        current.map { $0.frameCapacity - $0.frameLength } ?? VorbisDecoder.chunkFrames
    }

    mutating func append(_ pcm: UnsafeMutablePointer<UnsafeMutablePointer<Float>?>, frames: Int) throws(VorbisDecodeError) {
        total += AVAudioFramePosition(frames)
        guard total <= maxFrames else { throw .tooLong }
        if current == nil {
            current = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: VorbisDecoder.chunkFrames)
        }
        guard let buffer = current, let destination = buffer.floatChannelData,
              frames <= Int(buffer.frameCapacity - buffer.frameLength) else { throw .unreadable }
        let start = Int(buffer.frameLength)
        for channel in 0..<Int(format.channelCount) {
            guard let source = pcm[channel] else { throw .unreadable }
            (destination[channel] + start).update(from: source, count: frames)
        }
        buffer.frameLength += AVAudioFrameCount(frames)
        if buffer.frameLength == buffer.frameCapacity {
            chunks.append(buffer)
            current = nil
        }
    }

    consuming func finish() throws(VorbisDecodeError) -> DecodedSong {
        if let current, current.frameLength > 0 {
            chunks.append(current)
        }
        guard total > 0 else { throw .unreadable }
        return DecodedSong(format: format, chunks: chunks)
    }
}
