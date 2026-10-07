import Foundation

/// キャリブレーションの結果
nonisolated struct CalibrationResult: Sendable, Hashable {
    /// 動きが音より遅れる秒（負なら早い）。判定では振りの時刻から引く
    let offset: TimeInterval
    /// クリックと組にできた振りの数
    let matchedCount: Int
    /// ずれのばらつき（標準偏差・秒）
    let spread: TimeInterval
}

/// クリックの聞こえた時刻と振りの時刻から、音と動きの平均のずれを求める
nonisolated enum CalibrationAnalyzer {
    nonisolated struct Configuration: Sendable, Hashable {
        /// 最初のこの数のクリックは数えない（拍に慣れてもらうための前打ち）
        var countIn = 4
        /// クリックからこの秒より離れた振りは、そのクリックへの振りとみなさない
        var matchWindow: TimeInterval = 0.3
        /// 結果を出すのに要る、組にできた振りの数
        var minimumMatches = 6
        /// 中央値からこの秒より離れたずれは、はずれ値として捨てる
        var outlierThreshold: TimeInterval = 0.1
    }

    /// クリックと組にできた振り
    nonisolated struct Match: Sendable, Hashable {
        /// `clickTimes` の中のクリックの位置
        let clickIndex: Int
        /// 振りの時刻 − クリックの時刻（秒）
        let delta: TimeInterval
    }

    /// 振りが足りないときは nil
    static func analyze(
        clickTimes: [TimeInterval],
        cutTimes: [TimeInterval],
        configuration: Configuration = Configuration()
    ) -> CalibrationResult? {
        let deltas = match(clickTimes: clickTimes, cutTimes: cutTimes, configuration: configuration).map(\.delta)
        guard let median = median(deltas) else { return nil }
        let kept = deltas.filter { abs($0 - median) <= configuration.outlierThreshold }
        guard kept.count >= configuration.minimumMatches else { return nil }
        let mean = kept.reduce(0, +) / Double(kept.count)
        let variance = kept.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(kept.count)
        return CalibrationResult(offset: mean, matchedCount: kept.count, spread: variance.squareRoot())
    }

    /// 前打ちの後の各クリックに、`matchWindow` の中で最も近い振りを 1 つずつ組にする。はずれ値はまだ捨てない
    static func match(
        clickTimes: [TimeInterval],
        cutTimes: [TimeInterval],
        configuration: Configuration = Configuration()
    ) -> [Match] {
        var remaining = cutTimes.filter(\.isFinite).sorted()
        var matches: [Match] = []
        for clickIndex in clickTimes.indices.dropFirst(configuration.countIn) where clickTimes[clickIndex].isFinite {
            let click = clickTimes[clickIndex]
            // 各クリックに最も近い振りを 1 つだけ使う（同じ振りを 2 つのクリックに数えない）
            guard let index = remaining.indices.min(by: { abs(remaining[$0] - click) < abs(remaining[$1] - click) }),
                  abs(remaining[index] - click) <= configuration.matchWindow else { continue }
            matches.append(Match(clickIndex: clickIndex, delta: remaining[index] - click))
            remaining.remove(at: index)
        }
        return matches
    }

    private static func median(_ values: [TimeInterval]) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

/// 測ったオフセットの保存先。判定（`Judge` の `offset`）にはここから渡す
nonisolated struct CalibrationStore: Sendable {
    /// 保存できるオフセットの範囲（秒）。範囲外の値は読み込み時に 0 として扱う
    static let range: ClosedRange<TimeInterval> = -0.3...0.3
    static let offsetKey = "calibration.motionOffset"

    private let suiteName: String?

    /// - Parameter suiteName: テストでは専用の suite を渡す。nil なら標準の UserDefaults
    init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    /// 保存済みのオフセット。測っていなければ 0
    var offset: TimeInterval {
        guard let value = defaults.object(forKey: Self.offsetKey) as? Double,
              value.isFinite, Self.range.contains(value) else { return 0 }
        return value
    }

    var hasOffset: Bool {
        defaults.object(forKey: Self.offsetKey) != nil
    }

    func save(_ offset: TimeInterval) {
        guard offset.isFinite else { return }
        defaults.set(min(max(offset, Self.range.lowerBound), Self.range.upperBound), forKey: Self.offsetKey)
    }

    func reset() {
        defaults.removeObject(forKey: Self.offsetKey)
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }
}
