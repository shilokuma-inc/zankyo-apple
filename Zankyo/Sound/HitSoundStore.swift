import Foundation

/// 効果音の設定（音と音量）の保存先
nonisolated struct HitSoundStore: Sendable {
    static let soundKey = "sound.hitSound"
    static let volumeKey = "sound.hitVolume"

    private let suiteName: String?

    /// - Parameter suiteName: テストでは専用の suite を渡す。nil なら標準の UserDefaults
    init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    /// 保存済みの設定。保存していない・読めない値は既定にする
    var settings: HitSoundSettings {
        var settings = HitSoundSettings()
        if let sound = defaults.string(forKey: Self.soundKey).flatMap(HitSound.init(rawValue:)) {
            settings.sound = sound
        }
        if let volume = defaults.object(forKey: Self.volumeKey) as? Double, volume.isFinite, (0...1).contains(volume) {
            settings.volume = volume
        }
        return settings
    }

    func save(_ settings: HitSoundSettings) {
        defaults.set(settings.sound.rawValue, forKey: Self.soundKey)
        if settings.volume.isFinite {
            defaults.set(min(max(settings.volume, 0), 1), forKey: Self.volumeKey)
        }
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }
}
