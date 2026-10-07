import Foundation

/// 譜面 ZIP の `Info.dat` から読み取った曲情報。形式（v2 / v4）の差はパーサが吸収する
nonisolated struct SongInfo: Sendable, Hashable {
    nonisolated enum Format: Sendable, Hashable {
        /// `_version: 2.x`（`_songName` などアンダースコア付きのキー）
        case v2
        /// `version: 4.x`（`song` / `audio` / `difficultyBeatmaps`）
        case v4
    }

    let format: Format
    let title: String
    let subTitle: String
    let artist: String
    /// 譜面の作者（v2 は `_levelAuthorName`、v4 は難易度ごとの `mappers` をまとめたもの）
    let mapper: String
    /// 曲の BPM（拍→秒の変換の基準）
    let bpm: Double
    /// 音源の先頭から拍 0 までのずれ（秒）。v2 の `_songTimeOffset`。v4 には無いので 0
    let songTimeOffset: Double
    /// 音源（Ogg Vorbis。拡張子は `.egg` が多い）のファイル名
    let songFilename: String
    /// ジャケット画像のファイル名。無ければ nil
    let coverImageFilename: String?
    /// v4 の BPM 変化などを記したファイル名（`audioDataFilename`）。v2 は nil
    let audioDataFilename: String?
    /// 試聴する区間の始まり（秒）。無い・不正なら nil
    let previewStartTime: Double?
    /// 試聴する区間の長さ（秒）。無い・不正なら nil
    let previewDuration: Double?
    /// 遊べる難易度。characteristic ごとに易しい順
    let difficulties: [DifficultyInfo]
}

/// 1 つの難易度の譜面
nonisolated struct DifficultyInfo: Sendable, Hashable {
    let characteristic: BeatmapCharacteristic
    let difficulty: BeatmapDifficulty
    /// 難易度譜面（`.dat`）のファイル名
    let beatmapFilename: String
    /// ノーツの飛んでくる速さ（Note Jump Speed）。0 のときは既定値を使う
    let noteJumpSpeed: Double
    let noteJumpStartBeatOffset: Double
}

/// ノーツのある characteristic。Lightshow（ノーツが無い）や未知のものは読み込まない
nonisolated enum BeatmapCharacteristic: String, Sendable, Hashable, CaseIterable {
    case standard = "Standard"
    case oneSaber = "OneSaber"
    case noArrows = "NoArrows"
    case degree90 = "90Degree"
    case degree360 = "360Degree"
}

nonisolated enum BeatmapDifficulty: String, Sendable, Hashable, CaseIterable, Comparable {
    case easy = "Easy"
    case normal = "Normal"
    case hard = "Hard"
    case expert = "Expert"
    case expertPlus = "ExpertPlus"

    /// 画面に出す名前
    var displayName: String {
        self == .expertPlus ? "Expert+" : rawValue
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (allCases.firstIndex(of: lhs) ?? 0) < (allCases.firstIndex(of: rhs) ?? 0)
    }
}
