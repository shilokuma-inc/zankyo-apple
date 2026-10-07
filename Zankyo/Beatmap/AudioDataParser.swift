import Foundation

/// v4 の Info.dat が指す音声データ（`audioDataFilename`。`AudioData.dat` や `BPMInfo.dat`）から、拍と秒の対応を読む。
/// v4 では BPM の変化は難易度譜面ではなく、このファイルの区間（サンプル位置と拍の対応）で表す
///
/// - v4: `{ "songFrequency": 44100, "bpmData": [{ "si": 0, "ei": 441000, "sb": 0, "eb": 20 }] }`
/// - 旧形式（BPMInfo.dat）: `{ "_songFrequency": 44100, "_regions": [{ "_startSampleIndex": 0, "_endSampleIndex": …, "_startBeat": 0, "_endBeat": … }] }`
nonisolated enum AudioDataParser {
    /// ファイルの上限。区間の数は多くても数千
    static let maxBytes = 10 * 1_024 * 1_024
    static let frequencyRange: ClosedRange<Double> = 1_000...1_000_000
    /// 区間の BPM の範囲。速度を変える演出で 1,000 を超える区間もあるので、Info.dat の BPM より広く取る
    static let bpmRange: ClosedRange<Double> = 0.1...100_000

    /// 拍と秒の対応。読めない・区間が無い・区間が不正なら nil（呼び出し側は Info.dat の BPM を使う）
    static func timeline(from data: Data) -> BeatTimeline? {
        guard data.count <= maxBytes, let file = try? JSONDecoder().decode(AudioDataFile.self, from: data),
              let frequency = file.frequency, frequencyRange.contains(frequency) else { return nil }
        let segments = file.regions
            .compactMap { region -> BeatTimeline.Segment? in
                guard let startSample = region.startSample, let endSample = region.endSample,
                      let startBeat = region.startBeat, let endBeat = region.endBeat,
                      startSample >= 0, startBeat >= 0, endSample > startSample, endBeat > startBeat else { return nil }
                let bpm = (endBeat - startBeat) * 60 * frequency / (endSample - startSample)
                guard bpm.isFinite, bpmRange.contains(bpm) else { return nil }
                return BeatTimeline.Segment(beat: startBeat, seconds: startSample / frequency, bpm: bpm)
            }
            .prefix(BeatTimeline.maxChanges + 1)
            .sorted { $0.beat < $1.beat }
        return BeatTimeline(segments: Array(segments))
    }
}

nonisolated private struct AudioDataFile: Decodable {
    let frequency: Double?
    let regions: [AudioDataRegion]

    private enum CodingKeys: String, CodingKey {
        case songFrequency, bpmData
        case legacyFrequency = "_songFrequency"
        case legacyRegions = "_regions"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frequency = container.lenient(Double.self, forKey: .songFrequency) ?? container.lenient(Double.self, forKey: .legacyFrequency)
        regions = container.lenient(LossyDecodableArray<AudioDataRegion>.self, forKey: .bpmData)?.elements
            ?? container.lenient(LossyDecodableArray<AudioDataRegion>.self, forKey: .legacyRegions)?.elements
            ?? []
    }
}

/// サンプル位置 `startSample`〜`endSample` が、拍 `startBeat`〜`endBeat` に対応する区間
nonisolated private struct AudioDataRegion: Decodable {
    let startSample: Double?
    let endSample: Double?
    let startBeat: Double?
    let endBeat: Double?

    private enum CodingKeys: String, CodingKey {
        case si, ei, sb, eb
        case legacyStartSample = "_startSampleIndex"
        case legacyEndSample = "_endSampleIndex"
        case legacyStartBeat = "_startBeat"
        case legacyEndBeat = "_endBeat"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startSample = container.lenient(Double.self, forKey: .si) ?? container.lenient(Double.self, forKey: .legacyStartSample)
        endSample = container.lenient(Double.self, forKey: .ei) ?? container.lenient(Double.self, forKey: .legacyEndSample)
        startBeat = container.lenient(Double.self, forKey: .sb) ?? container.lenient(Double.self, forKey: .legacyStartBeat)
        endBeat = container.lenient(Double.self, forKey: .eb) ?? container.lenient(Double.self, forKey: .legacyEndBeat)
    }
}
