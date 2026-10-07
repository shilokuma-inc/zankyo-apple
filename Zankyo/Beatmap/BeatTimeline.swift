import Foundation

/// 拍の位置を曲の先頭からの秒に変換する。BPM 変化ごとに区間を分け、区間ごとの秒を積み上げる
nonisolated struct BeatTimeline: Sendable, Hashable {
    /// BPM が一定の区間。`beat` から次の区間の手前まで `bpm` で進む
    nonisolated struct Segment: Sendable, Hashable {
        let beat: Double
        let seconds: Double
        let bpm: Double
    }

    /// BPM 変化の上限（これを超える分は捨てる）
    static let maxChanges = 10_000

    /// 拍 0 から始まり、拍の順に並ぶ。必ず 1 つ以上ある
    let segments: [Segment]

    /// - Parameters:
    ///   - bpm: 拍 0 の BPM（Info.dat の値。検証済みであること）
    ///   - changes: 譜面の BPM 変化。範囲外の BPM・負の拍・同じ拍の重複（後のものを使う）は除く
    ///   - offset: 拍 0 の秒（曲の先頭からのずれ）
    init(bpm: Double, changes: [(beat: Double, bpm: Double)] = [], offset: Double = 0) {
        // 不正な変化で上限を使い切らないよう、検証してから上限を当てる
        let valid = changes
            .filter { $0.beat.isFinite && $0.beat >= 0 && $0.bpm.isFinite && SongInfoParser.bpmRange.contains($0.bpm) }
            .prefix(Self.maxChanges)
            .enumerated()
            // 同じ拍の変化は後に書かれたものを使うので、元の順を保って並べ替える
            .sorted { $0.element.beat == $1.element.beat ? $0.offset < $1.offset : $0.element.beat < $1.element.beat }
            .map(\.element)
        var segments = [Segment(beat: 0, seconds: offset, bpm: bpm)]
        for change in valid {
            let last = segments[segments.count - 1]
            if change.beat == last.beat {
                segments[segments.count - 1] = Segment(beat: last.beat, seconds: last.seconds, bpm: change.bpm)
            } else {
                let seconds = last.seconds + (change.beat - last.beat) * 60 / last.bpm
                segments.append(Segment(beat: change.beat, seconds: seconds, bpm: change.bpm))
            }
        }
        self.segments = segments
    }

    /// 区間の始まりの拍と秒を直接与えて作る（v4 の `AudioData.dat` のように、区間ごとに秒が決まっている形式用）
    ///
    /// - Parameter segments: 拍の順に並び、拍も秒も増えていくこと。BPM は正で有限であること。空なら nil
    init?(segments: [Segment]) {
        guard let first = segments.first, first.beat >= 0, segments.count <= Self.maxChanges + 1 else { return nil }
        guard segments.allSatisfy({ $0.beat.isFinite && $0.seconds.isFinite && $0.bpm.isFinite && $0.bpm > 0 }),
              zip(segments, segments.dropFirst()).allSatisfy({ $0.beat < $1.beat && $0.seconds <= $1.seconds }) else { return nil }
        // 最初の区間より前の拍は、最初の区間の BPM で延ばす
        let lead = Segment(beat: 0, seconds: first.seconds - first.beat * 60 / first.bpm, bpm: first.bpm)
        self.segments = first.beat > 0 ? [lead] + segments : segments
    }

    /// 拍の位置の秒。拍 0 より前は最初の BPM で延ばす
    func seconds(atBeat beat: Double) -> Double {
        let segment = segment(containing: beat)
        return segment.seconds + (beat - segment.beat) * 60 / segment.bpm
    }

    /// 拍の位置の BPM
    func bpm(atBeat beat: Double) -> Double {
        segment(containing: beat).bpm
    }

    /// `beat` 以前で最後に始まった区間（二分探索）
    private func segment(containing beat: Double) -> Segment {
        var low = 0
        var high = segments.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if segments[middle].beat <= beat {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return segments[low]
    }
}
