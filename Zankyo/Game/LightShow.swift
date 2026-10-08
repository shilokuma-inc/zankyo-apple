import Foundation

/// プレイ中の背景の光の演出。譜面に照明があればそれを、無ければ拍に合わせて作った光を使い、曲の時刻ごとの光の状態を返す
///
/// 光の点滅による負担を避けるため、同じ光の点滅（flash / fade）は `minimumFlashInterval` より詰めて出さない
nonisolated struct LightShow: Sendable {
    /// 照明のイベントがこれより少ない譜面は、照明が無いものとみなして拍から光を作る
    static let minimumEvents = 16
    /// 同じ光の点滅の最短の間隔（秒）。1 秒に約 3 回まで
    static let minimumFlashInterval: TimeInterval = 0.3
    /// flash で強く光ってから、点いた明るさに落ち着くまでの秒
    static let flashDuration: TimeInterval = 0.3
    /// fade で強く光ってから消えるまでの秒
    static let fadeDuration: TimeInterval = 1.0
    /// リングを 1 回回すときの角度と、回り終えるまでの秒
    static let ringSpinAngle: Double = .pi / 8
    static let ringSpinDuration: TimeInterval = 0.8
    /// レーザーの速さの 1 あたりの、振る位相の進み（ラジアン毎秒）。速さのイベントが無いときの速さ
    static let laserPhaseRate: Double = 0.5
    static let defaultLaserSpeed: Double = 2
    /// 拍から光を作るときの拍の上限
    static let maxBeats = 20_000

    /// 譜面の照明を使っている（false なら拍から作った光）
    let isFromBeatmap: Bool
    private let tracks: [LightGroup: [LightEvent]]
    private let ringSpins: [TimeInterval]
    private let leftLasers: LaserTrack
    private let rightLasers: LaserTrack

    /// - Parameters:
    ///   - lighting: 譜面の照明
    ///   - timeline: 拍と秒の対応（譜面に照明が無いときに、拍に合わせて光らせるのに使う）
    ///   - duration: 曲の長さ（拍から光を作る範囲）
    init(lighting: Lighting, timeline: BeatTimeline, duration: TimeInterval) {
        isFromBeatmap = lighting.events.count >= Self.minimumEvents
        let source = isFromBeatmap ? lighting : Self.beatLighting(timeline: timeline, duration: duration)
        var tracks: [LightGroup: [LightEvent]] = [:]
        for group in LightGroup.allCases {
            tracks[group] = Self.throttled(source.events.filter { $0.group == group })
        }
        self.tracks = tracks
        ringSpins = Self.throttled(source.ringSpins, interval: Self.ringSpinDuration / 2)
        leftLasers = LaserTrack(source.laserSpeeds.filter { $0.side == .left })
        rightLasers = LaserTrack(source.laserSpeeds.filter { $0.side == .right })
    }

    /// 曲の時刻 `time` の光の状態
    func state(at time: TimeInterval) -> LightState {
        func light(_ group: LightGroup) -> LightState.Light {
            guard let events = tracks[group], let index = Self.lastIndex(in: events, atOrBefore: time, time: \.time) else {
                return LightState.Light(color: .white, intensity: 0)
            }
            let event = events[index]
            return LightState.Light(color: event.color, intensity: Self.intensity(of: event, elapsed: time - event.time))
        }
        return LightState(
            back: light(.back),
            rings: light(.rings),
            leftLasers: light(.leftLasers),
            rightLasers: light(.rightLasers),
            center: light(.center),
            ringRotation: ringRotation(at: time),
            leftLaserPhase: leftLasers.phase(at: time),
            rightLaserPhase: rightLasers.phase(at: time)
        )
    }

    /// イベントからの経過 `elapsed` 秒での明るさ（0〜1.5 くらい）
    static func intensity(of event: LightEvent, elapsed: TimeInterval) -> Double {
        let elapsed = max(elapsed, 0)
        switch event.action {
        case .off:
            return 0
        case .on:
            return event.brightness
        case .flash:
            return event.brightness * (1 + 0.6 * max(1 - elapsed / flashDuration, 0))
        case .fade:
            return event.brightness * 1.4 * max(1 - elapsed / fadeDuration, 0)
        }
    }

    /// 回したリングの角度。回すたびに `ringSpinAngle` ずつ、`ringSpinDuration` かけて回す
    private func ringRotation(at time: TimeInterval) -> Double {
        guard let index = Self.lastIndex(in: ringSpins, atOrBefore: time, time: \.self) else { return 0 }
        let progress = min((time - ringSpins[index]) / Self.ringSpinDuration, 1)
        let eased = 1 - pow(1 - progress, 3)
        return Self.ringSpinAngle * (Double(index) + eased)
    }

    /// 譜面に照明が無いときの光。拍ごとに左右のレーザーを交互に、4 拍ごとに奥の光と中央の光を光らせ、リングを回す。
    /// 拍が詰まりすぎる（BPM が極端に高い）ところは、`minimumFlashInterval` より詰めない
    static func beatLighting(timeline: BeatTimeline, duration: TimeInterval) -> Lighting {
        var events: [LightEvent] = []
        var spins: [TimeInterval] = []
        var lastTime = -TimeInterval.infinity
        for beat in 0..<maxBeats {
            let time = timeline.seconds(atBeat: Double(beat))
            guard time.isFinite, time <= duration else { break }
            guard time >= 0, time - lastTime >= minimumFlashInterval else { continue }
            lastTime = time
            let isLeft = beat.isMultiple(of: 2)
            func fade(_ group: LightGroup, _ color: LightColor, _ brightness: Double) {
                events.append(LightEvent(time: time, group: group, action: .fade, color: color, brightness: brightness))
            }
            fade(isLeft ? .leftLasers : .rightLasers, isLeft ? .left : .right, 1)
            fade(.rings, isLeft ? .right : .left, 0.7)
            if beat.isMultiple(of: 4) {
                fade(.back, .white, 1)
                fade(.center, beat.isMultiple(of: 8) ? .left : .right, 0.8)
                spins.append(time)
            }
        }
        return Lighting(events: events.sorted { $0.time < $1.time }, ringSpins: spins, laserSpeeds: [])
    }

    /// 前に残した点滅から `minimumFlashInterval` より近い点滅を除く（点灯・消灯は残す）
    private static func throttled(_ events: [LightEvent]) -> [LightEvent] {
        var result: [LightEvent] = []
        var lastFlash = -TimeInterval.infinity
        for event in events {
            if event.action == .flash || event.action == .fade {
                guard event.time - lastFlash >= minimumFlashInterval else { continue }
                lastFlash = event.time
            }
            result.append(event)
        }
        return result
    }

    private static func throttled(_ times: [TimeInterval], interval: TimeInterval) -> [TimeInterval] {
        var result: [TimeInterval] = []
        for time in times where time - (result.last ?? -.infinity) >= interval {
            result.append(time)
        }
        return result
    }

    /// 時刻の順に並んだ `items` のうち、`time` 以前で最後のものの位置（二分探索）
    static func lastIndex<Item>(in items: [Item], atOrBefore time: TimeInterval, time key: (Item) -> TimeInterval) -> Int? {
        var low = 0
        var high = items.count
        while low < high {
            let mid = (low + high) / 2
            if key(items[mid]) <= time {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low == 0 ? nil : low - 1
    }
}

/// 左右どちらかのレーザーの振れ方。速さが変わったところまでの位相を先に積んでおき、どの時刻の位相もすぐ求められるようにする
nonisolated private struct LaserTrack: Sendable {
    /// 速さが変わったところと、そこまでに進んだ位相
    private struct Change: Sendable {
        let time: TimeInterval
        let speed: Double
        let phase: Double
    }

    private let changes: [Change]

    init(_ speeds: [LaserSpeed]) {
        var changes: [Change] = []
        var time: TimeInterval = 0
        var speed = LightShow.defaultLaserSpeed
        var phase: Double = 0
        for change in speeds {
            phase += speed * LightShow.laserPhaseRate * max(change.time - time, 0)
            time = max(change.time, time)
            speed = change.speed
            changes.append(Change(time: time, speed: speed, phase: phase))
        }
        self.changes = changes
    }

    func phase(at time: TimeInterval) -> Double {
        let time = max(time, 0)
        guard let index = LightShow.lastIndex(in: changes, atOrBefore: time, time: \.time) else {
            return LightShow.defaultLaserSpeed * LightShow.laserPhaseRate * time
        }
        let change = changes[index]
        return change.phase + change.speed * LightShow.laserPhaseRate * (time - change.time)
    }
}

/// ある時刻の背景の光
nonisolated struct LightState: Sendable, Hashable {
    nonisolated struct Light: Sendable, Hashable {
        var color: LightColor
        /// 明るさ（0 で消えている。1 がふつう、点滅の瞬間は 1 を超える）
        var intensity: Double
    }

    var back: Light
    var rings: Light
    var leftLasers: Light
    var rightLasers: Light
    var center: Light
    /// リングの角度（ラジアン）
    var ringRotation: Double
    /// 左右のレーザーを振る位相（ラジアン）
    var leftLaserPhase: Double
    var rightLaserPhase: Double

    /// 点滅させない、落ち着いた光（「視差効果を減らす」がオンのとき）
    static let calm = LightState(
        back: Light(color: .white, intensity: 0.4),
        rings: Light(color: .right, intensity: 0.35),
        leftLasers: Light(color: .left, intensity: 0.45),
        rightLasers: Light(color: .right, intensity: 0.45),
        center: Light(color: .left, intensity: 0.3),
        ringRotation: 0,
        leftLaserPhase: 0,
        rightLaserPhase: 0
    )
}
