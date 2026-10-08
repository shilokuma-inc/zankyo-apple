import Foundation
import Testing
@testable import Zankyo

struct SwingSensitivityStoreTests {
    @Test(arguments: PlayStyle.allCases)
    func savesAndClampsThreshold(style: PlayStyle) {
        let suite = "ZankyoTests.SwingSensitivity.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let store = SwingSensitivityStore(suiteName: suite)
        let defaultThreshold = SwingSensitivityStore.defaultThreshold(for: style)
        let other = PlayStyle.allCases.first { $0 != style } ?? style

        #expect(store.threshold(for: style) == defaultThreshold)

        store.save(threshold: 1.2, for: style)
        #expect(store.threshold(for: style) == 1.2)
        #expect(store.detection.adjustableThreshold(for: style) == 1.2)
        // ほかの遊び方の閾値と、左右の閾値は変えない
        #expect(store.threshold(for: other) == SwingSensitivityStore.defaultThreshold(for: other))
        #expect(store.detection.directional.yawThreshold == CutDetector.Configuration().yawThreshold)

        store.save(threshold: 10, for: style)
        #expect(store.threshold(for: style) == SwingSensitivityStore.thresholdRange.upperBound)

        store.save(threshold: .nan, for: style)
        #expect(store.threshold(for: style) == SwingSensitivityStore.thresholdRange.upperBound)

        store.resetThreshold(for: style)
        #expect(store.threshold(for: style) == defaultThreshold)
    }

    @Test
    func keepsPitchThresholdSavedBeforePlayStyles() {
        // 遊び方を選べるようになる前に保存した上下の閾値は、向きを合わせて切る遊び方の閾値として読む
        let suite = "ZankyoTests.SwingSensitivity.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        UserDefaults(suiteName: suite)?.set(1.1, forKey: "motion.pitchThreshold")

        let detection = SwingSensitivityStore(suiteName: suite).detection
        #expect(detection.directional.pitchThreshold == 1.1)
        #expect(detection.headbang.threshold == HeadbangDetector.Configuration().threshold)
    }

    @Test
    func savesPlayStyleAndDefaultsToHeadbang() {
        let suite = "ZankyoTests.SwingSensitivity.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let store = SwingSensitivityStore(suiteName: suite)

        #expect(store.playStyle == .headbang)
        #expect(store.detection.style == .headbang)

        store.save(playStyle: .directional)
        #expect(store.playStyle == .directional)
        #expect(store.detection.style == .directional)

        // 知らない値（新しい版が書いたなど）はヘドバンにする
        UserDefaults(suiteName: suite)?.set("unknown", forKey: SwingSensitivityStore.playStyleKey)
        #expect(store.playStyle == .headbang)
    }

    @Test
    func ignoresBrokenStoredValue() {
        let suite = "ZankyoTests.SwingSensitivity.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let defaults = UserDefaults(suiteName: suite)
        let key = SwingSensitivityStore.thresholdKey(for: .headbang)

        defaults?.set("soft", forKey: key)
        #expect(SwingSensitivityStore(suiteName: suite).threshold(for: .headbang) == HeadbangDetector.Configuration().threshold)

        // 範囲外の値（手で書き換えたなど）も既定に戻す
        defaults?.set(0.1, forKey: key)
        #expect(SwingSensitivityStore(suiteName: suite).threshold(for: .headbang) == HeadbangDetector.Configuration().threshold)
    }
}
