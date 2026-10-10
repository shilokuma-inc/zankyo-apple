import SwiftUI

/// 測っている間の手がかり。プレイ画面と同じネオンのレーンで、上から降りてくる印が判定の線に重なる瞬間（クリックが聞こえる時刻）に振る
///
/// 前打ち（高い音・聞くだけ）の印は点線の枠に耳と何回目か、振る拍（低い音）の印はプレイ画面の方向不問のノーツ（`NoteBlock`）。
/// 下の点の並びは全拍の進み具合と、振りを数えた拍。早い・遅いは出さない（`CalibrationCue.caughtBeats(cutTimes:)`）。
/// プレイ画面と同じ空間（`PlayfieldBackdrop`）の上に置く前提
struct CalibrationCueView: View {
    let cue: CalibrationCue
    let cutTimes: [TimeInterval]
    /// クリックと同じ物差し（起動からの秒）の今の時刻
    let now: () -> TimeInterval
    /// 頭の動きの見える化に使う。nil なら出さない
    var motion: MotionMonitor?

    /// 印が上端から線に届くまでの秒と、線の上での印の大きさ。プレイ画面にそろえる
    private static let approachTime = PlayView.approachTime
    private static let noteSize = PlayView.noteSize
    /// クリックが聞こえた後、線と印を光らせる秒
    private static let flashDuration: TimeInterval = 0.25

    @Environment(\.palette) private var palette

    /// 振る拍の色。プレイ画面の方向不問のノーツと同じ
    private var swingColor: Color { palette.noteColor(for: nil).color }

    var body: some View {
        TimelineView(.animation) { _ in
            let time = now()
            let passed = cue.passedCount(at: time)
            let flash = flashAmount(at: time)
            // レーンはプレイ画面と同じく画面の端まで広げ、文字と点の並びにだけ余白を付ける
            VStack(spacing: 16) {
                prompt(passed: passed, flash: flash)
                    .padding(.horizontal)
                lane(at: time, flash: flash)
                    .frame(maxHeight: .infinity)
                beatDots(passed: passed)
                    .padding(.horizontal)
            }
        }
    }

    /// 今が前打ちか振る拍か。前打ちは何回目かを数える
    private func prompt(passed: Int, flash: Double) -> some View {
        let countIn = cue.configuration.countIn
        let isSwinging = passed > countIn
        let glow = isSwinging ? swingColor : palette.laser
        return VStack(spacing: 4) {
            Text(isSwinging ? "振る" : passed == 0 ? "聞く" : "\(passed)")
                .font(.system(size: 56, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(isSwinging ? palette.textColor(for: palette.noteColor(for: nil)) : palette.ink)
                .shadow(color: palette.glow(glow, 0.8), radius: 6 + 14 * flash)
                .scaleEffect(1 + 0.2 * flash)
            Text(isSwinging ? "低い音に合わせて振ってください" : passed < countIn ? "高い音は聞くだけ" : "次の低い音から振ります")
                .font(.headline)
                .foregroundStyle(palette.laser)
        }
        .accessibilityElement(children: .combine)
    }

    private func lane(at time: TimeInterval, flash: Double) -> some View {
        GeometryReader { proxy in
            let geometry = PlayfieldGeometry(size: proxy.size, approachTime: Self.approachTime)
            let clicks = cue.approachingClicks(at: time, lookahead: Self.approachTime, lookbehind: Self.flashDuration)
            ZStack {
                PlayfieldLane(geometry: geometry)
                PlayfieldGrid(geometry: geometry, currentTime: time)
                hitLineFlash(geometry: geometry, flash: flash)
                ForEach(clicks, id: \.index) { click in
                    mark(for: click, geometry: geometry)
                }
            }
        }
        .clipped()
        .accessibilityHidden(true)
        .overlay(alignment: .topTrailing) {
            // プレイ中と同じく小さく出す。レーンは奥（上）ですぼまるので、上の端に置けば印と重ならない（取得はキャリブレーションが行う）
            if let motion {
                HeadIndicatorView(monitor: motion, style: .compact, previewsWhenIdle: false)
                    .padding(.trailing)
            }
        }
    }

    /// クリックが聞こえた瞬間に、判定の線をいっそう光らせる
    private func hitLineFlash(geometry: PlayfieldGeometry, flash: Double) -> some View {
        let edges = geometry.laneEdges(atY: geometry.hitY)
        return Capsule()
            .fill(palette.core)
            .frame(width: edges.right - edges.left, height: 2 + 4 * flash)
            .shadow(color: palette.glow(palette.laser), radius: 4 + 16 * flash)
            .shadow(color: palette.glow(palette.laser), radius: 12 * flash)
            .opacity(flash)
            .position(x: geometry.centerX, y: geometry.hitY)
    }

    /// 降りてくる 1 つの印。線に届いた印はそこに留め、光の輪を広げながら消える
    private func mark(for click: CalibrationCue.ApproachingClick, geometry: PlayfieldGeometry) -> some View {
        let isCountIn = cue.isCountIn(click.index)
        let y = geometry.y(remaining: max(click.remaining, 0))
        let size = Self.noteSize * geometry.scale(atY: y)
        let fade = click.remaining < 0 ? -click.remaining / Self.flashDuration : 0
        let color = isCountIn ? palette.laser : swingColor
        return ZStack {
            if fade > 0 {
                Circle()
                    .stroke(color, lineWidth: 1 + 3 * (1 - fade))
                    .frame(width: size * (0.8 + 1.4 * fade), height: size * (0.8 + 1.4 * fade))
                    .shadow(color: palette.glow(color), radius: 8)
                    .opacity(1 - fade)
            }
            Group {
                if isCountIn {
                    CountInMark(number: click.index + 1, size: size)
                } else {
                    NoteBlock(direction: nil, size: size)
                }
            }
            .scaleEffect(1 + 0.3 * fade)
            .opacity((1 - fade) * geometry.noteOpacity(remaining: max(click.remaining, 0)))
        }
        .position(x: geometry.centerX, y: y)
    }

    private func beatDots(passed: Int) -> some View {
        let caught = cue.caughtBeats(cutTimes: cutTimes)
        return VStack(spacing: 8) {
            HStack(spacing: 5) {
                ForEach(cue.clickTimes.indices, id: \.self) { index in
                    BeatDot(isCountIn: cue.isCountIn(index), isPassed: index < passed, isCaught: caught.contains(index))
                }
            }
            Text("振りを数えた拍が光ります")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("進み具合")
        .accessibilityValue("\(passed) / \(cue.clickTimes.count) 拍、振りを数えた拍 \(caught.count) / \(cue.swingCount)")
    }

    /// クリックが聞こえた瞬間に 1、`flashDuration` で 0 に戻る
    private func flashAmount(at time: TimeInterval) -> Double {
        guard let since = cue.timeSinceLastClick(at: time) else { return 0 }
        return max(1 - since / Self.flashDuration, 0)
    }
}

/// 前打ちの印。切るノーツと見分けられるよう、点線の枠だけにして、耳と何回目かを入れる
private struct CountInMark: View {
    let number: Int
    /// 枠の一辺
    let size: CGFloat

    @Environment(\.palette) private var palette

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
            .strokeBorder(palette.laser, style: StrokeStyle(lineWidth: max(size * 0.04, 1), dash: [size * 0.12, size * 0.08]))
            .overlay {
                VStack(spacing: 0) {
                    Image(systemName: "ear")
                        .font(.system(size: size * 0.36, weight: .semibold))
                    Text("\(number)")
                        .displayFont(.display(size: size * 0.26, weight: .black).monospacedDigit())
                }
                .foregroundStyle(palette.ink)
            }
            .frame(width: size, height: size)
            .shadow(color: palette.glow(palette.laser, 0.7), radius: size * 0.15)
    }
}

/// 進み具合の 1 拍。前打ちは小さく、振る拍は数えたら光らせる
private struct BeatDot: View {
    let isCountIn: Bool
    let isPassed: Bool
    let isCaught: Bool

    @Environment(\.palette) private var palette

    var body: some View {
        let size: CGFloat = isCountIn ? 6 : 10
        Circle()
            .fill(fill)
            .overlay {
                if !isPassed, !isCaught {
                    Circle().strokeBorder(palette.ink.opacity(0.4), lineWidth: 1)
                }
            }
            .frame(width: size, height: size)
            .shadow(color: isCaught ? palette.glow(palette.noteColor(for: nil).color) : .clear, radius: 4)
    }

    private var fill: Color {
        if isCaught { return palette.noteColor(for: nil).color }
        if isPassed { return isCountIn ? palette.laser : palette.ink.opacity(0.3) }
        return .clear
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
    .background { PlayfieldBackdrop() }
    .appTheme(.cyberpunk)
}
