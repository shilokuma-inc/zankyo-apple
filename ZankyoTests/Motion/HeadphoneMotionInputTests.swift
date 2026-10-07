#if !os(visionOS)
import CoreMotion
import Foundation
import Testing
@testable import Zankyo

struct HeadphoneMotionInputTests {
    @Test
    func unsupportedDeviceWins() {
        #expect(HeadphoneMotionInput.status(isAvailable: false, authorization: .authorized, isConnected: true) == .unsupported)
    }

    @Test(arguments: [
        (CMAuthorizationStatus.notDetermined, MotionInputStatus.notDetermined),
        (.denied, .notAuthorized),
        (.restricted, .notAuthorized)
    ])
    func reflectsAuthorization(authorization: CMAuthorizationStatus, expected: MotionInputStatus) {
        #expect(HeadphoneMotionInput.status(isAvailable: true, authorization: authorization, isConnected: true) == expected)
    }

    @Test
    func authorizedNeedsConnection() {
        #expect(HeadphoneMotionInput.status(isAvailable: true, authorization: .authorized, isConnected: false) == .disconnected)
        #expect(HeadphoneMotionInput.status(isAvailable: true, authorization: .authorized, isConnected: true) == .ready)
    }

    @Test
    func mapsRotationRateToYawAndPitch() {
        // z 軸まわりの正（左を向く）は yaw の負、x 軸まわりの正（上を向く）は pitch の正
        let sample = MotionSample(headphoneTimestamp: 12.5, rotationRate: CMRotationRate(x: 1.5, y: 9, z: 2))

        #expect(sample == MotionSample(timestamp: 12.5, yawRate: -2, pitchRate: 1.5))
    }

    @Test
    func unavailableOnSimulatorDoesNotStream() async {
        // Simulator にはイヤホンのモーションセンサーが無いので、列はすぐ終わる。実機ではこのテストの前提が変わるので飛ばす
        let input = HeadphoneMotionInput()
        guard input.status == .unsupported else { return }
        var count = 0
        for await _ in input.start() {
            count += 1
        }

        #expect(count == 0)
        #expect(input.status == .unsupported)
    }
}
#endif
