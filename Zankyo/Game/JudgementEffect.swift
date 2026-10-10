import SwiftUI

/// 直近の判定の表示。切ったときはノーツの色の刃の形の斬撃を走らせ、判定の線の近くに点数と「早い / ぴったり / 遅い」を出す。
/// 判定ごとに作り直す（`.id(judgement)`）前提で、現れたときに 1 度だけ動く
struct JudgementEffect: View {
    let judgement: Judgement
    /// 「早い / ぴったり / 遅い」を決める判定の係数
    let rules: ScoringRules
    /// 判定の線の上でのノーツの大きさ
    let noteSize: CGFloat
    /// 点数などの文字を判定の線からずらす量（`PlayfieldGeometry.judgementLabelOffset`）
    let labelOffset: CGFloat

    @State private var progress: CGFloat = 0
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            if case .hit(let note, _, _) = judgement {
                slash(for: note)
            }
            label
                .scaleEffect(1.3 - 0.3 * progress)
                .offset(y: labelOffset)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                progress = 1
            }
        }
    }

    /// 振った向きに走る斬撃。ノーツの色の刃の形の線を伸ばし、芯の色の細い線を重ねる。光らせず、伸びながら薄れて消える
    private func slash(for note: FaceNote) -> some View {
        let color = palette.noteColor(for: note.direction).color
        let length = noteSize * 2.8 * (0.3 + 0.7 * progress)
        return ZStack {
            BladeShape()
                .fill(color)
                .frame(width: length, height: 2 + 8 * (1 - progress))
            BladeShape()
                .fill(palette.core)
                .frame(width: length * 0.8, height: 1 + 2 * (1 - progress))
        }
        .rotationEffect(Self.slashAngle(for: note.direction))
        .opacity(Double(1 - progress))
    }

    private var label: some View {
        // 文字の高さを増やすと判定の線の下に収まらず、ノーツの降りてくる線の上に出てしまうので、横に並べる
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(text)
                .displayFont(.display(.title2, weight: .black).monospacedDigit())
                .foregroundStyle(textColor)
            // ぴったりのタイミングからどちらにずれたかを出し、次の振りで直せるようにする
            if let timing {
                Text(timing.label)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(timing == .perfect ? palette.laser : palette.ink.opacity(0.8))
            }
        }
    }

    private var timing: HitTiming? {
        guard case .hit(_, _, let timingError) = judgement else { return nil }
        return HitTiming(timingError: timingError, rules: rules)
    }

    private var text: String {
        switch judgement {
        case .hit(_, let score, _): "\(score.total)"
        case .badCut: "向き違い"
        case .miss: "ミス"
        }
    }

    private var textColor: Color {
        switch judgement {
        case .hit: palette.ink
        case .badCut, .miss: palette.warning
        }
    }

    /// 振った向きへ斬る（刃の線は太い側から細い側へ向かう）。方向不問は斜めにする
    private static func slashAngle(for direction: SwingDirection?) -> Angle {
        switch direction {
        case .right: .zero
        case .down: .degrees(90)
        case .left: .degrees(180)
        case .up: .degrees(-90)
        case nil: .degrees(-35)
        }
    }
}

/// 枠の左端から右端へ引く刃の形（`PlayfieldLights.blade`）。太さは枠の高さ
private struct BladeShape: Shape {
    func path(in rect: CGRect) -> Path {
        PlayfieldLights.blade(from: CGPoint(x: rect.minX, y: rect.midY), to: CGPoint(x: rect.maxX, y: rect.midY), width: rect.height)
    }
}

/// 空振り（ヘドバンでノーツの無いところで振った）でコンボが切れたことの表示。空振りごとに作り直す前提で、現れたときに 1 度だけ浮かんで消える。
/// 消えた後も残るので、VoiceOver ではこの文字を読まず、空振りのたびに読み上げで知らせる（`ScoreReadout`）
struct EmptySwingEffect: View {
    @State private var progress: CGFloat = 0
    @Environment(\.palette) private var palette

    var body: some View {
        Text("空振り")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(palette.warning)
            .offset(y: -12 * progress)
            .opacity(Double(1 - progress))
            .accessibilityHidden(true)
            .onAppear {
                withAnimation(.easeOut(duration: 0.8)) {
                    progress = 1
                }
            }
    }
}

private extension HitTiming {
    var label: String {
        switch self {
        case .early: "早い"
        case .perfect: "ぴったり"
        case .late: "遅い"
        }
    }
}
