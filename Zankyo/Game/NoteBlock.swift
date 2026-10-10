import SwiftUI

/// 1 つのノーツ。角の小さい平らな板に、振る向きの楔形の矢印（方向不問は点）を描く。光らせず、板と矢印の濃淡で形を立たせる
struct NoteBlock: View {
    /// 振る向き。nil は方向不問
    let direction: SwingDirection?
    /// 箱の一辺
    let size: CGFloat

    @Environment(\.palette) private var palette

    var body: some View {
        let neon = palette.noteColor(for: direction)
        let shape = RoundedRectangle(cornerRadius: size * Self.cornerRatio)
        ZStack {
            shape
                .fill(neon.color)
            shape
                .strokeBorder(palette.noteOutline, lineWidth: max(size * 0.03, 1))
            marker
                .foregroundStyle(palette.markColor(for: neon))
        }
        .frame(width: size, height: size)
    }

    /// 角の丸めの半径（一辺に対する割合）。ターゲット枠（`HitTarget`）も同じ値を使う
    static let cornerRatio: CGFloat = 0.08

    @ViewBuilder private var marker: some View {
        if let direction {
            ArrowMark()
                .frame(width: size * 0.56, height: size * 0.64)
                .rotationEffect(Self.rotation(for: direction))
        } else {
            Circle()
                .frame(width: size * 0.24, height: size * 0.24)
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

/// 下向きの楔形の矢印。先を尖らせ、根元を浅くえぐって刃先のように見せる
private struct ArrowMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.2))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.45))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.2))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    VStack(spacing: 0) {
        ForEach(AppTheme.allCases) { theme in
            HStack(spacing: 24) {
                ForEach([SwingDirection.left, .right, .up, .down], id: \.self) { direction in
                    NoteBlock(direction: direction, size: 64)
                }
                NoteBlock(direction: nil, size: 64)
            }
            .padding(24)
            .background(theme.palette.spaceBottom)
            .environment(\.palette, theme.palette)
        }
    }
}
