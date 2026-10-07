import Testing
@testable import Zankyo

struct MotionGuidanceTests {
    @Test
    func readyHasNoGuidance() {
        #expect(MotionInputStatus.ready.guidance == nil)
    }

    @Test(arguments: [MotionInputStatus.unsupported, .notDetermined, .notAuthorized, .disconnected])
    func otherStatusesExplainWhatIsNeeded(status: MotionInputStatus) throws {
        let guidance = try #require(status.guidance)
        #expect(!guidance.title.isEmpty)
        #expect(!guidance.message.isEmpty)
    }
}
