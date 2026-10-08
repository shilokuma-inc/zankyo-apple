import Foundation

/// 「切る」検出の閾値の保存先。利用者が変えられるのは上下（うなずき）の閾値だけで、左右は既定のまま
nonisolated struct SwingSensitivityStore: Sendable {
    /// 選べる上下の閾値の範囲（ラジアン毎秒）。範囲外の値は読み込み時に既定値として扱う
    static let pitchThresholdRange: ClosedRange<Double> = 0.8...2.5
    static let pitchThresholdKey = "motion.pitchThreshold"

    private let suiteName: String?

    /// - Parameter suiteName: テストでは専用の suite を渡す。nil なら標準の UserDefaults
    init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    /// 保存済みの上下の閾値。保存していなければ既定値
    var pitchThreshold: Double {
        guard let value = defaults.object(forKey: Self.pitchThresholdKey) as? Double,
              value.isFinite, Self.pitchThresholdRange.contains(value) else {
            return CutDetector.Configuration().pitchThreshold
        }
        return value
    }

    /// 保存済みの閾値を反映した検出の設定
    var configuration: CutDetector.Configuration {
        var configuration = CutDetector.Configuration()
        configuration.pitchThreshold = pitchThreshold
        return configuration
    }

    func save(pitchThreshold: Double) {
        guard pitchThreshold.isFinite else { return }
        let clamped = min(max(pitchThreshold, Self.pitchThresholdRange.lowerBound), Self.pitchThresholdRange.upperBound)
        defaults.set(clamped, forKey: Self.pitchThresholdKey)
    }

    func reset() {
        defaults.removeObject(forKey: Self.pitchThresholdKey)
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }
}
