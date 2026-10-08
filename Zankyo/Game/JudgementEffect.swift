import SwiftUI

/// 直近の判定の表示。切ったときはノーツの色の斬撃と光の輪を走らせ、判定の線の近くに点数と「早い / ぴったり / 遅い」を出す。
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

    private func slash(for note: FaceNote) -> some View {
        let color = palette.noteColor(for: note.direction).color
        let ring = noteSize * (0.8 + 1.4 * progress)
        return ZStack {
            // 広がって消える光の輪
            Circle()
                .stroke(color, lineWidth: 1 + 3 * (1 - progress))
                .frame(width: ring, height: ring)
                .shadow(color: palette.glow(color), radius: 8)
            // 振った向きに走る斬撃
            Capsule()
                .fill(palette.core)
                .frame(width: noteSize * 2.4 * (0.3 + 0.7 * progress), height: 1 + 4 * (1 - progress))
                .shadow(color: palette.glow(color), radius: 6)
                .shadow(color: palette.glow(color), radius: 14)
                .rotationEffect(Self.slashAngle(for: note.direction))
        }
        .opacity(Double(1 - progress))
    }

    private var label: some View {
        // 文字の高さを増やすと判定の線の下に収まらず、ノーツの降りてくる線の上に出てしまうので、横に並べる
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(text)
                .font(.system(.title2, design: .rounded, weight: .heavy).monospacedDigit())
                .foregroundStyle(textColor)
                .shadow(color: glowColor, radius: 8)
            // ぴったりのタイミングからどちらにずれたかを出し、次の振りで直せるようにする
            if let timing {
                Text(timing.label)
                    .font(.system(.headline, design: .rounded, weight: .heavy))
                    .foregroundStyle(timing == .perfect ? palette.laser : palette.ink.opacity(0.8))
                    .shadow(color: timing == .perfect ? palette.glow(palette.laser) : .clear, radius: 6)
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

    private var glowColor: Color {
        switch judgement {
        case .hit(let note, _, _): palette.glow(palette.noteColor(for: note.direction).color)
        case .badCut, .miss: palette.glow(palette.warning)
        }
    }

    /// 左右に振るノーツは横、上下は縦に斬る。方向不問は斜めにする
    private static func slashAngle(for direction: SwingDirection?) -> Angle {
        switch direction {
        case .left, .right: .zero
        case .up, .down: .degrees(90)
        case nil: .degrees(-35)
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
