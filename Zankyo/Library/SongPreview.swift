import Foundation

/// 曲の詳細で試聴する区間。Beat Saber の曲選びと同じく、Info.dat の試聴区間をくり返し鳴らす
nonisolated enum SongPreview {
    /// Info.dat に試聴区間が無いときの既定値（Beat Saber の譜面エディタの既定値）
    static let defaultStartTime: TimeInterval = 12
    static let defaultDuration: TimeInterval = 10
    /// 試聴にならないほど短い区間は、ここまで広げる
    static let minimumDuration: TimeInterval = 3
    /// 長すぎる区間は、ここまでにする（区間をメモリに写してくり返すため）
    static let maximumDuration: TimeInterval = 30
    /// 区間の始めと終わりのフェード
    static let fadeDuration: TimeInterval = 0.5

    /// 長さ `songDuration` の曲で試聴する区間。曲の終わりを越えるなら、収まるよう前へずらす（短い曲は頭から全体）
    static func range(startTime: Double?, duration: Double?, songDuration: TimeInterval) -> Range<TimeInterval> {
        guard songDuration.isFinite, songDuration > 0 else { return 0..<0 }
        let length = min(max(duration ?? defaultDuration, minimumDuration), maximumDuration)
        let start = min(startTime ?? defaultStartTime, max(songDuration - length, 0))
        return start..<min(start + length, songDuration)
    }
}
