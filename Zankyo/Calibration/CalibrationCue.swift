import Foundation

/// 測っている間の画面の手がかり。クリックが聞こえる時刻と今の時刻から、何拍目か・次の拍まで何秒かを求める
///
/// 時刻はクリックと同じ「起動からの秒」で、出力の遅延（Bluetooth のイヤホンを含む）を含んだ聞こえる時刻
nonisolated struct CalibrationCue: Sendable, Hashable {
    /// 線へ降りてくる途中か、線を過ぎたばかりのクリック
    nonisolated struct ApproachingClick: Sendable, Hashable {
        /// `clickTimes` の中のクリックの位置
        let index: Int
        /// クリックが聞こえるまでの秒。過ぎたものは負
        let remaining: TimeInterval
    }

    let clickTimes: [TimeInterval]
    var configuration = CalibrationAnalyzer.Configuration()

    /// 前打ちの後の、振る拍の数
    var swingCount: Int {
        max(clickTimes.count - configuration.countIn, 0)
    }

    /// 前打ち（聞くだけ）のクリックか
    func isCountIn(_ index: Int) -> Bool {
        index < configuration.countIn
    }

    /// `time` までに鳴ったクリックの数
    func passedCount(at time: TimeInterval) -> Int {
        clickTimes.prefix { $0 <= time }.count
    }

    /// 直前に鳴ったクリックからの秒。まだ 1 回も鳴っていなければ nil
    func timeSinceLastClick(at time: TimeInterval) -> TimeInterval? {
        clickTimes.last { $0 <= time }.map { time - $0 }
    }

    /// `time` から `lookahead` 秒先までに鳴るクリックと、`lookbehind` 秒前までに鳴ったクリック
    func approachingClicks(at time: TimeInterval, lookahead: TimeInterval, lookbehind: TimeInterval) -> [ApproachingClick] {
        clickTimes.indices.compactMap { index in
            let remaining = clickTimes[index] - time
            guard remaining >= -lookbehind, remaining <= lookahead else { return nil }
            return ApproachingClick(index: index, remaining: remaining)
        }
    }

    /// 振りを検出できた拍（`clickTimes` の中の位置）。ずれの計算と同じ組み方で、はずれ値はまだ捨てない
    ///
    /// 早い・遅いは返さない。画面で見せると、振りがそちらに引っ張られて自然なずれが測れなくなる
    func caughtBeats(cutTimes: [TimeInterval]) -> Set<Int> {
        Set(CalibrationAnalyzer.match(clickTimes: clickTimes, cutTimes: cutTimes, configuration: configuration).map(\.clickIndex))
    }
}
