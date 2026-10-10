import SwiftUI

/// 測っている間の手がかり。プレイ画面と同じレーンで、上から降りてくる印が判定の線に重なる瞬間（クリックが聞こえる時刻）に振る
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
    /// クリックが聞こえた後、判定の線を濃くし、線に届いた印を薄れさせる秒
    private static let flashDuration: TimeInterval = 0.25

    @Environment(\.palette) private var palette

    var body: some View {
        TimelineView(.animation) { _ in
            let time = now()
            let passed = cue.passedCount(at: time)
            let flash = flashAmount(at: time)
            // レーンはプレイ画面と同じく画面の端まで広げ、文字と点の並びにだけ余白を付ける
            VStack(spacing: 16) {
                prompt(passed: passed)
                    .padding(.horizontal)
                lane(at: time, flash: flash)
                    .frame(maxHeight: .infinity)
                beatDots(passed: passed)
                    .padding(.horizontal)
            }
        }
    }

    /// 今が前打ちか振る拍か。前打ちは何回目かを数える
    private func prompt(passed: Int) -> some View {
        let countIn = cue.configuration.countIn
        let isSwinging = passed > countIn
        // 拍の番号だけを同梱の欧文フォントにし、「聞く」「振る」はテーマの書体にする
        let font: Font = !isSwinging && passed > 0
            ? .display(size: 56, weight: .bold).monospacedDigit()
            : .system(size: 56, weight: .bold, design: palette.fontDesign)
        return VStack(spacing: 4) {
            Text(isSwinging ? "振る" : passed == 0 ? "聞く" : "\(passed)")
                .displayFont(font)
                .foregroundStyle(isSwinging ? palette.textColor(for: palette.noteColor(for: nil)) : palette.ink)
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

    /// クリックが聞こえた瞬間に、判定の線を太く濃くする（光らせない）
    private func hitLineFlash(geometry: PlayfieldGeometry, flash: Double) -> some View {
        let edges = geometry.laneEdges(atY: geometry.hitY)
        return Rectangle()
            .fill(palette.core)
            .frame(width: edges.right - edges.left, height: 2 + 3 * flash)
            .opacity(flash)
            .position(x: geometry.centerX, y: geometry.hitY)
    }

    /// 降りてくる 1 つの印。線に届いた印はそこに留め、薄れて消える
    private func mark(for click: CalibrationCue.ApproachingClick, geometry: PlayfieldGeometry) -> some View {
        let isCountIn = cue.isCountIn(click.index)
        let y = geometry.y(remaining: max(click.remaining, 0))
        let size = Self.noteSize * geometry.scale(atY: y)
        let fade = click.remaining < 0 ? -click.remaining / Self.flashDuration : 0
        return Group {
            if isCountIn {
                CountInMark(number: click.index + 1, size: size)
            } else {
                NoteBlock(direction: nil, size: size)
            }
        }
        .opacity((1 - fade) * geometry.noteOpacity(remaining: max(click.remaining, 0)))
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
        RoundedRectangle(cornerRadius: size * NoteBlock.cornerRatio)
            .strokeBorder(palette.laser, style: StrokeStyle(lineWidth: max(size * 0.04, 1), dash: [size * 0.12, size * 0.08]))
            .overlay {
                VStack(spacing: 0) {
                    Image(systemName: "ear")
                        .font(.system(size: size * 0.36, weight: .semibold))
                    Text("\(number)")
                        .displayFont(.display(size: size * 0.26, weight: .bold).monospacedDigit())
                }
                .foregroundStyle(palette.ink)
            }
            .frame(width: size, height: size)
    }
}

/// 進み具合の 1 拍。前打ちは小さく、振る拍は数えたら方向不問のノーツの色で塗る
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
    .appTheme(.zankyo)
}
