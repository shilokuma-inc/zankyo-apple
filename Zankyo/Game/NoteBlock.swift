import SwiftUI

/// Beat Saber のブロックにならった 1 つのノーツ。角丸の箱に振る向きの白い矢印（方向不問は白い点）を描き、ネオンの光をまとわせる
struct NoteBlock: View {
    /// 振る向き。nil は方向不問
    let direction: SwingDirection?
    /// 箱の一辺
    let size: CGFloat

    var body: some View {
        let neon = NeonTheme.noteColor(for: direction)
        let corner = size * 0.2
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(colors: [neon.color, neon.deep], startPoint: .top, endPoint: .bottom))
            // 面の内側を一段暗くして、箱の縁が光って見えるようにする
            RoundedRectangle(cornerRadius: corner * 0.6, style: .continuous)
                .fill(neon.deep.opacity(0.6))
                .padding(size * 0.1)
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(.white.opacity(0.5), lineWidth: max(size * 0.03, 1))
            marker
                .foregroundStyle(.white)
                .shadow(color: .white, radius: size * 0.05)
        }
        .frame(width: size, height: size)
        .shadow(color: neon.color.opacity(0.9), radius: size * 0.15)
        .shadow(color: neon.color.opacity(0.5), radius: size * 0.4)
    }

    @ViewBuilder private var marker: some View {
        if let direction {
            ArrowMark()
                .frame(width: size * 0.64, height: size * 0.64)
                .rotationEffect(Self.rotation(for: direction))
        } else {
            Circle()
                .frame(width: size * 0.28, height: size * 0.28)
        }
    }

    /// 矢印は下向きに描くので、振る向きに合わせて回す
    private static func rotation(for direction: SwingDirection) -> Angle {
        switch direction {
        case .down: .zero
        case .left: .degrees(90)
        case .up: .degrees(180)
        case .right: .degrees(-90)
        }
    }
}

/// Beat Saber の矢印（下向きの平たい三角）。枠の下半分に置く
private struct ArrowMark: Shape {
    func path(in rect: CGRect) -> Path {
        let top = rect.midY + rect.height * 0.1
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: top))
        path.addLine(to: CGPoint(x: rect.maxX, y: top))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    HStack(spacing: 24) {
        ForEach([SwingDirection.left, .right, .up, .down], id: \.self) { direction in
            NoteBlock(direction: direction, size: 64)
        }
        NoteBlock(direction: nil, size: 64)
    }
    .padding(40)
    .background(NeonTheme.spaceBottom)
}
