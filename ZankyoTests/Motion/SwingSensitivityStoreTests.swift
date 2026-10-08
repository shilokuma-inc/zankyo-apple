import Foundation
import Testing
@testable import Zankyo

struct SwingSensitivityStoreTests {
    @Test
    func savesAndClampsPitchThreshold() {
        let suite = "ZankyoTests.SwingSensitivity.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let store = SwingSensitivityStore(suiteName: suite)
        let defaultThreshold = CutDetector.Configuration().pitchThreshold

        #expect(store.pitchThreshold == defaultThreshold)

        store.save(pitchThreshold: 1.2)
        #expect(store.pitchThreshold == 1.2)
        #expect(store.configuration.pitchThreshold == 1.2)
        // 左右は変えない
        #expect(store.configuration.yawThreshold == CutDetector.Configuration().yawThreshold)

        store.save(pitchThreshold: 10)
        #expect(store.pitchThreshold == SwingSensitivityStore.pitchThresholdRange.upperBound)

        store.save(pitchThreshold: .nan)
        #expect(store.pitchThreshold == SwingSensitivityStore.pitchThresholdRange.upperBound)

        store.reset()
        #expect(store.pitchThreshold == defaultThreshold)
    }

    @Test
    func ignoresBrokenStoredValue() {
        let suite = "ZankyoTests.SwingSensitivity.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let defaults = UserDefaults(suiteName: suite)

        defaults?.set("soft", forKey: SwingSensitivityStore.pitchThresholdKey)
        #expect(SwingSensitivityStore(suiteName: suite).pitchThreshold == CutDetector.Configuration().pitchThreshold)

        // 範囲外の値（手で書き換えたなど）も既定に戻す
        defaults?.set(0.1, forKey: SwingSensitivityStore.pitchThresholdKey)
        #expect(SwingSensitivityStore(suiteName: suite).pitchThreshold == CutDetector.Configuration().pitchThreshold)
    }
}
