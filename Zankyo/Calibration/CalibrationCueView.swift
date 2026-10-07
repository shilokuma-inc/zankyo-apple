import SwiftUI

/// 測っている間の手がかり。プレイ画面と同じく、上から降りてくる印が線に重なる瞬間（クリックが聞こえる時刻）に振る
///
/// 前打ち（高い音・聞くだけ）の印は耳、振る拍（低い音）の印はプレイ画面の方向不問のノーツと同じ丸。
/// 下の点の並びは全拍の進み具合と、振りを数えた拍。早い・遅いは出さない（`CalibrationCue.caughtBeats(cutTimes:)`）
struct CalibrationCueView: View {
    let cue: CalibrationCue
    let cutTimes: [TimeInterval]
    /// クリックと同じ物差し（起動からの秒）の今の時刻
    let now: () -> TimeInterval

    /// 印が上端から線に届くまでの秒。プレイ画面にそろえる
    private static let approachTime = PlayView.approachTime
    /// クリックが聞こえた後、線と印を光らせる秒
    private static let flashDuration: TimeInterval = 0.25
    /// 印が上端から出てくるときに、浮かび上がらせる秒（上端で途切れて見えないように）
    private static let fadeInDuration: TimeInterval = 0.3

    var body: some View {
        TimelineView(.animation) { _ in
            let time = now()
            let passed = cue.passedCount(at: time)
            let flash = flashAmount(at: time)
            VStack(spacing: 16) {
                prompt(passed: passed, flash: flash)
                lane(at: time, flash: flash)
                    .frame(maxHeight: .infinity)
                beatDots(passed: passed)
            }
        }
    }

    /// 今が前打ちか振る拍か。前打ちは何回目かを数える
    private func prompt(passed: Int, flash: Double) -> some View {
        let countIn = cue.configuration.countIn
        let isSwinging = passed > countIn
        return VStack(spacing: 4) {
            Text(isSwinging ? "振る" : passed == 0 ? "聞く" : "\(passed)")
                .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(isSwinging ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .scaleEffect(1 + 0.2 * flash)
            Text(isSwinging ? "低い音に合わせて振ってください" : passed < countIn ? "高い音は聞くだけ" : "次の低い音から振ります")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func lane(at time: TimeInterval, flash: Double) -> some View {
        GeometryReader { proxy in
            let hitY = proxy.size.height * 0.8
            let centerX = proxy.size.width / 2
            let clicks = cue.approachingClicks(at: time, lookahead: Self.approachTime, lookbehind: Self.flashDuration)
            ZStack {
                Rectangle()
                    .fill(.tint.opacity(0.3 + 0.7 * flash))
                    .frame(height: 3 + 3 * flash)
                    .position(x: centerX, y: hitY)
                ForEach(clicks, id: \.index) { click in
                    // 線に届いた印はそこに留め、広がりながら消える
                    let fade = click.remaining < 0 ? -click.remaining / Self.flashDuration : 0
                    let fadeIn = min((Self.approachTime - click.remaining) / Self.fadeInDuration, 1)
                    CueMark(isCountIn: cue.isCountIn(click.index))
                        .scaleEffect(1 + 0.6 * fade)
                        .opacity((1 - fade) * fadeIn)
                        .position(x: centerX, y: hitY - max(click.remaining, 0) / Self.approachTime * hitY)
                }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private func beatDots(passed: Int) -> some View {
        let caught = cue.caughtBeats(cutTimes: cutTimes)
        return VStack(spacing: 8) {
            HStack(spacing: 5) {
                ForEach(cue.clickTimes.indices, id: \.self) { index in
                    BeatDot(isCountIn: cue.isCountIn(index), isPassed: index < passed, isCaught: caught.contains(index))
                }
            }
            Text("振りを数えた拍に色が付きます")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("振りを数えた拍")
        .accessibilityValue("\(caught.count) / \(cue.swingCount)")
    }

    /// クリックが聞こえた瞬間に 1、`flashDuration` で 0 に戻る
    private func flashAmount(at time: TimeInterval) -> Double {
        guard let since = cue.timeSinceLastClick(at: time) else { return 0 }
        return max(1 - since / Self.flashDuration, 0)
    }
}

/// 降りてくる 1 つの印
private struct CueMark: View {
    let isCountIn: Bool

    var body: some View {
        if isCountIn {
            Image(systemName: "ear")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.secondary)
        } else {
            Image(systemName: "circle.circle.fill")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(.tint)
                .background(Circle().fill(.background).padding(4))
        }
    }
}

/// 進み具合の 1 拍。前打ちは小さく、振る拍は数えたら色を付ける
private struct BeatDot: View {
    let isCountIn: Bool
    let isPassed: Bool
    let isCaught: Bool

    var body: some View {
        let size: CGFloat = isCountIn ? 6 : 10
        Circle()
            .fill(fill)
            .overlay {
                if !isPassed, !isCaught {
                    Circle().strokeBorder(.secondary, lineWidth: 1)
                }
            }
            .frame(width: size, height: size)
    }

    private var fill: AnyShapeStyle {
        if isCaught { return AnyShapeStyle(.tint) }
        if isPassed { return AnyShapeStyle(.secondary) }
        return AnyShapeStyle(.clear)
    }
}

#Preview {
    let start = ProcessInfo.processInfo.systemUptime + 1
    let clicks = (0..<CalibrationModel.beats).map { start + Double($0) * 60 / CalibrationModel.bpm }
    CalibrationCueView(
        cue: CalibrationCue(clickTimes: clicks),
        cutTimes: clicks.dropFirst(4).enumerated().filter { !$0.offset.isMultiple(of: 3) }.map { $0.element + 0.08 },
        now: { ProcessInfo.processInfo.systemUptime }
    )
    .padding()
}
