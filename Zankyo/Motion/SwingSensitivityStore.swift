import Foundation

/// 遊び方と「切る」検出の閾値の保存先。利用者が変えられる閾値は、遊び方ごとに 1 つ
/// （ヘドバンは振りの速さ、向きを合わせて切る遊び方は上下（うなずき）の閾値。左右は既定のまま）
nonisolated struct SwingSensitivityStore: Sendable {
    /// 選べる閾値の範囲（ラジアン毎秒）。範囲外の値は読み込み時に既定値として扱う
    static let thresholdRange: ClosedRange<Double> = 0.8...2.5
    static let playStyleKey = "motion.playStyle"

    private let suiteName: String?

    /// - Parameter suiteName: テストでは専用の suite を渡す。nil なら標準の UserDefaults
    init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    /// 閾値の保存先のキー。向きを合わせて切る遊び方は、遊び方を選べるようになる前と同じキー
    static func thresholdKey(for style: PlayStyle) -> String {
        switch style {
        case .headbang: "motion.headbangThreshold"
        case .directional: "motion.pitchThreshold"
        }
    }

    /// 保存済みの遊び方。保存していない・知らない値ならヘドバン
    var playStyle: PlayStyle {
        defaults.string(forKey: Self.playStyleKey).flatMap(PlayStyle.init(rawValue:)) ?? SwingDetection().style
    }

    /// 保存済みの閾値。保存していなければ既定値
    func threshold(for style: PlayStyle) -> Double {
        guard let value = defaults.object(forKey: Self.thresholdKey(for: style)) as? Double,
              value.isFinite, Self.thresholdRange.contains(value) else {
            return Self.defaultThreshold(for: style)
        }
        return value
    }

    /// 保存済みの遊び方と閾値を反映した検出の設定
    var detection: SwingDetection {
        var detection = SwingDetection()
        detection.style = playStyle
        for style in PlayStyle.allCases {
            detection.setAdjustableThreshold(threshold(for: style), for: style)
        }
        return detection
    }

    static func defaultThreshold(for style: PlayStyle) -> Double {
        SwingDetection().adjustableThreshold(for: style)
    }

    func save(playStyle: PlayStyle) {
        defaults.set(playStyle.rawValue, forKey: Self.playStyleKey)
    }

    func save(threshold: Double, for style: PlayStyle) {
        guard threshold.isFinite else { return }
        let clamped = min(max(threshold, Self.thresholdRange.lowerBound), Self.thresholdRange.upperBound)
        defaults.set(clamped, forKey: Self.thresholdKey(for: style))
    }

    func resetThreshold(for style: PlayStyle) {
        defaults.removeObject(forKey: Self.thresholdKey(for: style))
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }
}
