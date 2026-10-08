import Foundation

/// 頭の動きのサンプルから「切る」動きを検出するもの。遊び方ごとに検出の仕方が違う（`SwingDetection.makeDetector()`）
nonisolated protocol SwingDetector: Sendable {
    /// サンプルを 1 つ受け取り、振りが終わったときだけ `CutEvent` を返す
    mutating func process(_ sample: MotionSample) -> CutEvent?
}

// MainActor 既定のため、extension に書くと MainActor に隔離される。検出器と同じく nonisolated にする
nonisolated extension SwingDetector {
    /// サンプル列をまとめて処理する（録画した列の再生やテスト用）
    mutating func process(_ samples: some Sequence<MotionSample>) -> [CutEvent] {
        samples.compactMap { process($0) }
    }
}

/// 遊び方と、遊び方ごとの検出の設定。プレイ・キャリブレーション・頭の動きの表示で同じものを使い、
/// 画面で光った振りがそのままプレイでも「切った」振りになるようにする
nonisolated struct SwingDetection: Sendable, Hashable {
    var style: PlayStyle = .headbang
    /// 向きを合わせて切る遊び方の検出
    var directional = CutDetector.Configuration()
    /// ヘドバンの検出
    var headbang = HeadbangDetector.Configuration()

    func makeDetector() -> any SwingDetector {
        switch style {
        case .headbang: HeadbangDetector(configuration: headbang)
        case .directional: CutDetector(configuration: directional)
        }
    }

    /// 振りの強さ。閾値に対する割合で、1 以上で振りになる。頭の動きの表示に使う
    func strength(of sample: MotionSample) -> Double {
        switch style {
        case .headbang:
            hypot(sample.yawRate, sample.pitchRate) / headbang.threshold
        case .directional:
            max(abs(sample.yawRate) / directional.yawThreshold, abs(sample.pitchRate) / directional.pitchThreshold)
        }
    }

    /// 利用者が変えられる閾値（ラジアン毎秒）。ヘドバンは振りの速さ、向きを合わせて切る遊び方は上下（うなずき）の閾値
    func adjustableThreshold(for style: PlayStyle) -> Double {
        switch style {
        case .headbang: headbang.threshold
        case .directional: directional.pitchThreshold
        }
    }

    mutating func setAdjustableThreshold(_ threshold: Double, for style: PlayStyle) {
        switch style {
        case .headbang: headbang.threshold = threshold
        case .directional: directional.pitchThreshold = threshold
        }
    }
}
