import Foundation
import Testing
@testable import Zankyo

struct LightShowTests {
    /// 120 BPM（1 拍 0.5 秒）
    private let timeline = BeatTimeline(bpm: 120)

    /// 譜面の照明として扱われるだけの数の、左のレーザーの点灯（照明が少ないと拍から作った光になるため）
    private func lighting(_ events: [LightEvent], ringSpins: [TimeInterval] = [], laserSpeeds: [LaserSpeed] = []) -> Lighting {
        let filler = (0..<LightShow.minimumEvents).map { index in
            LightEvent(time: 100 + Double(index), group: .center, action: .on, color: .white, brightness: 1)
        }
        return Lighting(events: events + filler, ringSpins: ringSpins, laserSpeeds: laserSpeeds)
    }

    @Test
    func intensityFollowsAction() {
        func event(_ action: LightAction) -> LightEvent {
            LightEvent(time: 0, group: .back, action: action, color: .left, brightness: 1)
        }

        #expect(LightShow.intensity(of: event(.off), elapsed: 0) == 0)
        #expect(LightShow.intensity(of: event(.on), elapsed: 5) == 1)
        // flash は強く光ってから、点いた明るさに落ち着く
        #expect(LightShow.intensity(of: event(.flash), elapsed: 0) > 1.5)
        #expect(LightShow.intensity(of: event(.flash), elapsed: LightShow.flashDuration) == 1)
        // fade は消えていく
        #expect(LightShow.intensity(of: event(.fade), elapsed: 0) > 1)
        #expect(LightShow.intensity(of: event(.fade), elapsed: LightShow.fadeDuration) == 0)
    }

    @Test
    func stateUsesLastEventOfEachGroup() {
        let show = LightShow(
            lighting: lighting([
                LightEvent(time: 1, group: .back, action: .on, color: .left, brightness: 0.8),
                LightEvent(time: 2, group: .back, action: .off, color: .right, brightness: 1),
                LightEvent(time: 1.5, group: .rings, action: .on, color: .white, brightness: 1)
            ]),
            timeline: timeline,
            duration: 60
        )

        #expect(show.isFromBeatmap)
        #expect(show.state(at: 0.5).back.intensity == 0)
        #expect(show.state(at: 1.2).back == LightState.Light(color: .left, intensity: 0.8))
        #expect(show.state(at: 2.5).back.intensity == 0)
        #expect(show.state(at: 2.5).rings == LightState.Light(color: .white, intensity: 1))
    }

    @Test
    func throttlesRapidFlashes() {
        // 0.1 秒ごとの点滅は、0.3 秒より詰めない
        let flashes = (0..<10).map { index in
            LightEvent(time: Double(index) * 0.1, group: .leftLasers, action: .flash, color: .left, brightness: 1)
        }
        let show = LightShow(lighting: lighting(flashes), timeline: timeline, duration: 60)

        // 0.35 秒は 0.3 秒の点滅の直後（0.05 秒）、0.25 秒は 0 秒の点滅から 0.25 秒たった後
        #expect(show.state(at: 0.35).leftLasers.intensity > show.state(at: 0.25).leftLasers.intensity)
    }

    @Test
    func ringsTurnWithEachSpin() {
        let show = LightShow(lighting: lighting([], ringSpins: [1, 2]), timeline: timeline, duration: 60)

        #expect(show.state(at: 0.5).ringRotation == 0)
        #expect(abs(show.state(at: 1 + LightShow.ringSpinDuration).ringRotation - LightShow.ringSpinAngle) < 0.0001)
        #expect(abs(show.state(at: 5).ringRotation - LightShow.ringSpinAngle * 2) < 0.0001)
    }

    @Test
    func laserPhaseIsContinuousAcrossSpeedChanges() {
        let show = LightShow(
            lighting: lighting([], laserSpeeds: [LaserSpeed(time: 2, side: .left, speed: 10)]),
            timeline: timeline,
            duration: 60
        )

        let before = show.state(at: 2 - 0.0001).leftLaserPhase
        let after = show.state(at: 2 + 0.0001).leftLaserPhase
        #expect(abs(after - before) < 0.01)
        // 速さが上がった後は、位相が速く進む
        let rate = (show.state(at: 3).leftLaserPhase - show.state(at: 2).leftLaserPhase)
        #expect(abs(rate - 10 * LightShow.laserPhaseRate) < 0.0001)
        // 右は速さのイベントが無いので、既定の速さ
        #expect(abs(show.state(at: 1).rightLaserPhase - LightShow.defaultLaserSpeed * LightShow.laserPhaseRate) < 0.0001)
    }

    @Test
    func fewEventsFallBackToBeats() {
        let few = Lighting(
            events: [LightEvent(time: 0, group: .back, action: .on, color: .left, brightness: 1)],
            ringSpins: [],
            laserSpeeds: []
        )
        let show = LightShow(lighting: few, timeline: timeline, duration: 10)

        #expect(!show.isFromBeatmap)
        // 拍ごとに左右のレーザーを交互に光らせる（拍 0 は左、拍 1 は右）
        #expect(show.state(at: 0.05).leftLasers.intensity > 1)
        #expect(show.state(at: 0.55).rightLasers.intensity > 1)
        #expect(show.state(at: 0.55).rightLasers.color == .right)
    }

    @Test
    func beatLightingSkipsBeatsThatAreTooClose() {
        // 1,000 BPM（1 拍 0.06 秒）でも、0.3 秒より詰めて光らせない
        let lighting = LightShow.beatLighting(timeline: BeatTimeline(bpm: 1_000), duration: 3)
        let laserTimes = lighting.events.filter { $0.group == .leftLasers || $0.group == .rightLasers }.map(\.time)

        #expect(!laserTimes.isEmpty)
        for (previous, next) in zip(laserTimes, laserTimes.dropFirst()) {
            #expect(next - previous >= LightShow.minimumFlashInterval - 0.0001)
        }
    }
}
