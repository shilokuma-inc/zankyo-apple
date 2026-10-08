import Foundation
import Testing
@testable import Zankyo

struct HitSoundSynthesizerTests {
    private static let sampleRate = 48_000.0

    @Test(arguments: HitSound.allCases)
    func makesShortSoundAtPeakVolume(sound: HitSound) {
        let samples = HitSoundSynthesizer.samples(for: sound, sampleRate: Self.sampleRate)

        #expect(samples.count == Int(HitSoundSynthesizer.duration(of: sound) * Self.sampleRate))
        // 続けて切っても重なりすぎないよう、どれも 0.6 秒以内
        #expect(HitSoundSynthesizer.duration(of: sound) <= 0.6)
        let maximum = samples.map(abs).max() ?? 0
        #expect(abs(maximum - HitSoundSynthesizer.peak) < 1e-5)
    }

    @Test(arguments: HitSound.allCases)
    func startsLoudRightAway(sound: HitSound) {
        // 切った瞬間が分かるよう、鳴り始めて 10ms のうちに大きくなる
        let samples = HitSoundSynthesizer.samples(for: sound, sampleRate: Self.sampleRate)
        let onset = samples.prefix(Int(Self.sampleRate * 0.01)).map(abs).max() ?? 0

        #expect(onset >= 0.3)
    }

    @Test(arguments: HitSound.allCases)
    func fadesAtBothEnds(sound: HitSound) throws {
        // 波形の端でプツッと鳴らないよう、最初と最後は 0 にする
        let samples = HitSoundSynthesizer.samples(for: sound, sampleRate: Self.sampleRate)

        #expect(try #require(samples.first) == 0)
        #expect(try #require(samples.last) == 0)
    }

    @Test
    func makesSameSoundEveryTimeAndDistinctSounds() {
        let first = HitSound.allCases.map { HitSoundSynthesizer.samples(for: $0, sampleRate: Self.sampleRate) }
        let second = HitSound.allCases.map { HitSoundSynthesizer.samples(for: $0, sampleRate: Self.sampleRate) }

        #expect(first == second)
        #expect(Set(first.map { $0.prefix(2_000).map { ($0 * 1_000).rounded() } }).count == HitSound.allCases.count)
    }

    @Test
    func handlesOtherSampleRatesAndInvalidOnes() {
        #expect(HitSoundSynthesizer.samples(for: .slash, sampleRate: 44_100).count == Int(0.35 * 44_100))
        #expect(HitSoundSynthesizer.samples(for: .slash, sampleRate: 0).isEmpty)
        #expect(HitSoundSynthesizer.samples(for: .slash, sampleRate: .nan).isEmpty)
    }
}

struct HitSoundStoreTests {
    @Test
    func savesAndLoadsSettings() {
        let suite = "ZankyoTests.HitSound.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let store = HitSoundStore(suiteName: suite)

        #expect(store.settings == HitSoundSettings())
        #expect(store.settings.sound == .slash)

        store.save(HitSoundSettings(sound: .taiko, volume: 0.35))
        #expect(store.settings == HitSoundSettings(sound: .taiko, volume: 0.35))

        // 範囲の外は 0〜1 に収める。0 は鳴らさない
        store.save(HitSoundSettings(sound: .bell, volume: 3))
        #expect(store.settings.volume == 1)
        store.save(HitSoundSettings(sound: .bell, volume: -1))
        #expect(store.settings.volume == 0)
        #expect(!store.settings.isAudible)
    }

    @Test
    func ignoresBrokenStoredValues() {
        let suite = "ZankyoTests.HitSound.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let defaults = UserDefaults(suiteName: suite)
        defaults?.set("unknown", forKey: HitSoundStore.soundKey)
        defaults?.set(7.0, forKey: HitSoundStore.volumeKey)

        #expect(HitSoundStore(suiteName: suite).settings == HitSoundSettings())
    }

    @Test
    func keepsStoredNames() {
        // 選んだ音は rawValue で保存するので、名前が変わると既定の音に戻ってしまう
        #expect(HitSound.allCases.map(\.rawValue) == ["slash", "taiko", "clap", "bell", "pop"])
    }
}
