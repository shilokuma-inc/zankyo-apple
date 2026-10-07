import SwiftUI

/// 直近の判定の表示。切ったときはノーツの色の斬撃と光の輪を走らせ、判定の線の下に点数を出す。
/// 判定ごとに作り直す（`.id(judgement)`）前提で、現れたときに 1 度だけ動く
struct JudgementEffect: View {
    let judgement: Judgement
    /// 判定の線の上でのノーツの大きさ
    let noteSize: CGFloat

    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            if case .hit(let note, _, _) = judgement {
                slash(for: note)
            }
            label
                .scaleEffect(1.3 - 0.3 * progress)
                .offset(y: noteSize * 0.95)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                progress = 1
            }
        }
    }

    private func slash(for note: FaceNote) -> some View {
        let color = NeonTheme.noteColor(for: note.direction).color
        let ring = noteSize * (0.8 + 1.4 * progress)
        return ZStack {
            // 広がって消える光の輪
            Circle()
                .stroke(color, lineWidth: 1 + 3 * (1 - progress))
                .frame(width: ring, height: ring)
                .shadow(color: color, radius: 8)
            // 振った向きに走る斬撃
            Capsule()
                .fill(.white)
                .frame(width: noteSize * 2.4 * (0.3 + 0.7 * progress), height: 1 + 4 * (1 - progress))
                .shadow(color: color, radius: 6)
                .shadow(color: color, radius: 14)
                .rotationEffect(Self.slashAngle(for: note.direction))
        }
        .opacity(Double(1 - progress))
    }

    private var label: some View {
        Text(text)
            .font(.system(.title2, design: .rounded, weight: .heavy).monospacedDigit())
            .foregroundStyle(textColor)
            .shadow(color: glowColor, radius: 8)
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
        case .hit: .white
        case .badCut, .miss: NeonTheme.red.color
        }
    }

    private var glowColor: Color {
        switch judgement {
        case .hit(let note, _, _): NeonTheme.noteColor(for: note.direction).color
        case .badCut, .miss: NeonTheme.red.color
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
