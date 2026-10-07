import Foundation

/// 難易度譜面（`.dat`）から読み取ったノーツ。形式（v2 / v3）の差はパーサが吸収する
nonisolated struct Beatmap: Sendable, Hashable {
    nonisolated enum Format: Sendable, Hashable {
        /// `_version: 2.x`（`_notes`・`_events`）
        case v2
        /// `version: 3.x`（`colorNotes`・`bpmEvents`）
        case v3
        /// `version: 4.x`（`colorNotes` と `colorNotesData`。BPM の変化は音声データの側）
        case v4
    }

    let format: Format
    /// 切るノーツ。曲の先頭からの秒の順に並ぶ。爆弾・壁・アーク・チェーンは含まない
    let notes: [BeatmapNote]
    /// 拍と秒の対応（BPM 変化・オフセットを反映したもの）
    let timeline: BeatTimeline
}

/// 1 つのノーツ
nonisolated struct BeatmapNote: Sendable, Hashable {
    /// 拍の位置
    let beat: Double
    /// 曲の先頭からの秒
    let time: Double
    /// 横の位置（0〜3。左から）
    let lineIndex: Int
    /// 縦の位置（0〜2。下から）
    let lineLayer: Int
    let color: NoteColor
    let cutDirection: CutDirection
}

nonisolated enum NoteColor: Int, Sendable, Hashable {
    case red = 0
    case blue = 1
}

/// 切る方向。Beat Saber の番号と同じ並び
nonisolated enum CutDirection: Int, Sendable, Hashable, CaseIterable {
    case up = 0
    case down = 1
    case left = 2
    case right = 3
    case upLeft = 4
    case upRight = 5
    case downLeft = 6
    case downRight = 7
    /// 方向を問わない（ドットノーツ）
    case any = 8
}
