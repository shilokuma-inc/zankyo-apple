import Foundation

/// ノーツを切ったときの効果音。設定で選ぶ。選んだ音は `rawValue` で保存するので、case の名前を変えない
///
/// 音はすべてアプリの中で合成する（`HitSoundSynthesizer`。著作権のある素材を同梱しない）
nonisolated enum HitSound: String, CaseIterable, Identifiable, Sendable {
    /// 刀で切るような、短い風切り音と金属の響き。既定
    case slash
    /// 太鼓の低い「ドン」
    case taiko
    /// 手拍子の「パン」
    case clap
    /// 鈴の「チリン」
    case bell
    /// 軽い「ポン」
    case pop

    var id: Self { self }

    var title: String {
        switch self {
        case .slash: "斬撃"
        case .taiko: "太鼓"
        case .clap: "手拍子"
        case .bell: "鈴"
        case .pop: "ポン"
        }
    }

    var summary: String {
        switch self {
        case .slash: "風を切る音と、刀の響き"
        case .taiko: "低くお腹に響く「ドン」"
        case .clap: "乾いた手拍子の「パン」"
        case .bell: "高く澄んだ「チリン」"
        case .pop: "軽くはじける「ポン」"
        }
    }
}

/// 効果音の設定。音量が 0 なら鳴らさない
nonisolated struct HitSoundSettings: Sendable, Hashable {
    var sound: HitSound = .slash
    /// 音量（0〜1）
    var volume: Double = 0.7

    var isAudible: Bool { volume > 0 }
}

/// 効果音の波形を合成する。どれも鳴り始めてすぐ大きくなり（切った瞬間が分かるように）、短く消える
///
/// ノイズは決まった種から作るので、何度作っても同じ音になる
nonisolated enum HitSoundSynthesizer {
    /// 波形の最大の振幅
    static let peak: Float = 0.9
    /// 鳴り始めと終わりに付けるフェードの秒（波形の端でプツッと鳴らさない）
    static let attack: TimeInterval = 0.001
    static let release: TimeInterval = 0.01

    /// モノラルの波形（-1〜1）
    static func samples(for sound: HitSound, sampleRate: Double) -> [Float] {
        guard sampleRate.isFinite, sampleRate > 0 else { return [] }
        let duration = duration(of: sound)
        let count = Int(duration * sampleRate)
        var noise = Noise(seed: seed(of: sound))
        var highPass = HighPass(cutoff: 2_000, sampleRate: sampleRate)
        var values = [Double](repeating: 0, count: count)
        for index in 0..<count {
            let time = Double(index) / sampleRate
            let white = noise.next()
            values[index] = sample(of: sound, at: time, noise: white, highPassed: highPass.process(white))
        }
        return finish(values, sampleRate: sampleRate)
    }

    static func duration(of sound: HitSound) -> TimeInterval {
        switch sound {
        case .slash: 0.35
        case .taiko: 0.4
        case .clap: 0.25
        case .bell: 0.6
        case .pop: 0.18
        }
    }

    /// 時刻 `time` の 1 サンプル（正規化する前）
    private static func sample(of sound: HitSound, at time: TimeInterval, noise: Double, highPassed: Double) -> Double {
        switch sound {
        case .slash:
            // 高い成分だけのノイズの短い風切り音に、倍音の揃わない金属の響きを重ねる
            let swish = highPassed * exp(-time / 0.02)
            let ring = partials([(2_350, 0.5), (3_710, 0.35), (5_230, 0.25)], at: time) * exp(-time / 0.09)
            return swish + ring
        case .taiko:
            // 打った瞬間は高く、すぐ低く落ちる音程の正弦波。最初の一瞬に、ばちの当たるノイズを足す
            let phase = 2 * Double.pi * (70 * time + 80 * 0.03 * (1 - exp(-time / 0.03)))
            let body = sin(phase) * exp(-time / 0.12)
            let stick = noise * 0.3 * exp(-time / 0.004)
            return body + stick
        case .clap:
            // 少しずつずれた 3 回の破裂と、短い余韻
            let bursts = [0, 0.008, 0.016].map { start -> Double in
                guard time >= start else { return 0 }
                return exp(-(time - start) / 0.006)
            }
            .reduce(0, +)
            let tail = 0.4 * exp(-time / 0.05)
            return highPassed * (bursts + tail)
        case .bell:
            // 高い倍音を長めに響かせ、少しゆらす
            let shimmer = 1 + 0.15 * sin(2 * Double.pi * 18 * time)
            return partials([(3_150, 0.6), (4_720, 0.3), (6_390, 0.2)], at: time) * exp(-time / 0.18) * shimmer
        case .pop:
            // 高いところからすぐ下がる短い正弦波
            let phase = 2 * Double.pi * (420 * time + 500 * 0.02 * (1 - exp(-time / 0.02)))
            return sin(phase) * exp(-time / 0.04)
        }
    }

    private static func partials(_ partials: [(frequency: Double, amplitude: Double)], at time: TimeInterval) -> Double {
        partials.reduce(0) { $0 + $1.amplitude * sin(2 * Double.pi * $1.frequency * time) }
    }

    /// 鳴り始めと終わりをフェードし、最大の振幅を `peak` にそろえる
    private static func finish(_ values: [Double], sampleRate: Double) -> [Float] {
        let attackCount = max(Int(attack * sampleRate), 1)
        let releaseCount = max(Int(release * sampleRate), 1)
        let faded = values.enumerated().map { index, value in
            let fadeIn = min(Double(index) / Double(attackCount), 1)
            let fadeOut = min(Double(values.count - 1 - index) / Double(releaseCount), 1)
            return value * fadeIn * fadeOut
        }
        let maximum = faded.map(abs).max() ?? 0
        guard maximum > 0 else { return faded.map { Float($0) } }
        return faded.map { Float($0 / maximum) * peak }
    }

    private static func seed(of sound: HitSound) -> UInt32 {
        switch sound {
        case .slash: 0x5A17
        case .taiko: 0x7A1C
        case .clap: 0xC1A9
        case .bell: 0xBE11
        case .pop: 0x9099
        }
    }

    /// 決まった種から作るノイズ（xorshift）。-1〜1
    private struct Noise {
        private var state: UInt32

        init(seed: UInt32) {
            state = seed == 0 ? 1 : seed
        }

        mutating func next() -> Double {
            state ^= state << 13
            state ^= state >> 17
            state ^= state << 5
            return Double(state) / Double(UInt32.max) * 2 - 1
        }
    }

    /// 1 次のハイパスフィルタ。ノイズから低い成分を除き、風切り音や手拍子の乾いた音にする
    private struct HighPass {
        private let alpha: Double
        private var previousInput = 0.0
        private var previousOutput = 0.0

        init(cutoff: Double, sampleRate: Double) {
            let rc = 1 / (2 * Double.pi * cutoff)
            alpha = rc / (rc + 1 / sampleRate)
        }

        mutating func process(_ input: Double) -> Double {
            let output = alpha * (previousOutput + input - previousInput)
            previousInput = input
            previousOutput = output
            return output
        }
    }
}
