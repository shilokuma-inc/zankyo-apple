import Foundation

/// 頭で切るノーツ。色は持たず、向きは上下左右か方向不問（Discussion #3 Q4）
nonisolated struct FaceNote: Sendable, Hashable {
    /// 拍の位置
    let beat: Double
    /// 曲の先頭からの秒
    let time: TimeInterval
    /// 振る向き。nil は方向を問わない（どの向きに振ってもよい）
    let direction: SwingDirection?
}

/// 難易度譜面のノーツを、頭で切るノーツに変換する
///
/// 1. 8 方向を上下左右に畳む（斜めは左右に丸める）。方向不問（any）はそのまま
/// 2. ほぼ同時のノーツ（赤青の同時押しなど）を 1 つにまとめる
/// 3. 最小間隔より近いノーツを間引く。間隔の中に拍の頭のノーツがあれば、そちらを残す
nonisolated enum FaceNoteConverter {
    nonisolated struct Configuration: Sendable, Hashable {
        /// この秒より近いノーツは同時とみなして 1 つにまとめる
        var simultaneousWindow: TimeInterval = 0.02
        /// 残すノーツの最小間隔（秒）。首を振って戻すのに要る時間
        var minimumInterval: TimeInterval = 0.35
        /// 拍の頭とみなす、整数の拍からのずれ
        var onBeatTolerance: Double = 0.001
    }

    static func convert(_ beatmap: Beatmap, configuration: Configuration = Configuration()) -> [FaceNote] {
        convert(beatmap.notes, configuration: configuration)
    }

    static func convert(_ notes: [BeatmapNote], configuration: Configuration = Configuration()) -> [FaceNote] {
        let sorted = notes.sorted { $0.time < $1.time }
        let merged = merge(sorted, window: configuration.simultaneousWindow)
        return thin(merged, configuration: configuration)
    }

    /// 切る方向を頭の向きに畳む。斜めは左右（首振り）に丸める。any は nil（方向不問）
    static func direction(for cutDirection: CutDirection) -> SwingDirection? {
        switch cutDirection {
        case .up: .up
        case .down: .down
        case .left, .upLeft, .downLeft: .left
        case .right, .upRight, .downRight: .right
        case .any: nil
        }
    }

    /// ほぼ同時のノーツを先頭の時刻で 1 つにまとめる。向きが揃わないときは方向不問にする（頭は一度に 1 方向しか振れないため）
    private static func merge(_ notes: [BeatmapNote], window: TimeInterval) -> [FaceNote] {
        var result: [FaceNote] = []
        var groupStart: BeatmapNote?
        var directions: [SwingDirection?] = []

        func flush() {
            guard let first = groupStart else { return }
            let specified = Set(directions.compactMap(\.self))
            let direction = specified.count == 1 ? specified.first : nil
            result.append(FaceNote(beat: first.beat, time: first.time, direction: direction))
        }

        for note in notes {
            if let first = groupStart, note.time - first.time < window {
                directions.append(direction(for: note.cutDirection))
                continue
            }
            flush()
            groupStart = note
            directions = [direction(for: note.cutDirection)]
        }
        flush()
        return result
    }

    /// 前に残したノーツから最小間隔に満たないノーツを捨てる。残す候補の後ろ、最小間隔の中に拍の頭のノーツがあれば、そちらを残す
    private static func thin(_ notes: [FaceNote], configuration: Configuration) -> [FaceNote] {
        var result: [FaceNote] = []
        var index = notes.startIndex
        while index < notes.endIndex {
            let candidate = notes[index]
            if let last = result.last, candidate.time - last.time < configuration.minimumInterval {
                index += 1
                continue
            }
            var chosen = index
            if !isOnBeat(candidate.beat, tolerance: configuration.onBeatTolerance) {
                var next = index + 1
                while next < notes.endIndex, notes[next].time - candidate.time < configuration.minimumInterval {
                    if isOnBeat(notes[next].beat, tolerance: configuration.onBeatTolerance) {
                        chosen = next
                        break
                    }
                    next += 1
                }
            }
            result.append(notes[chosen])
            index = chosen + 1
        }
        return result
    }

    private static func isOnBeat(_ beat: Double, tolerance: Double) -> Bool {
        abs(beat - beat.rounded()) <= tolerance
    }
}
