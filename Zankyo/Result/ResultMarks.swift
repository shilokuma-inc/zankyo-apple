import SwiftUI

/// 結果画面の印。SF Symbols の定番のアイコンの代わりに、筆で描いたような形を `Shape` で描く。
/// どれも塗りつぶして使う形にしてあり、`.fill`（または `foregroundStyle`）で色を付ける

/// フルコンボの印。筆で一周を描き、終わりを少しだけ閉じない円（円相）。描き始めを太く、終わりへ向けて細く払う
struct EnsoMark: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let widest = side * 0.2
        let radius = side / 2 - widest / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // 右上から描き始め、時計回りに 1 周の 9 割ほどを描く
        let start = -Double.pi * 0.2
        let span = Double.pi * 2 * 0.88
        let steps = 48
        var outer: [CGPoint] = []
        var inner: [CGPoint] = []
        for step in 0...steps {
            let progress = Double(step) / Double(steps)
            let angle = start + span * progress
            let width = widest * (1 - 0.7 * progress)
            outer.append(CGPoint(x: center.x + (radius + width / 2) * cos(angle), y: center.y + (radius + width / 2) * sin(angle)))
            inner.append(CGPoint(x: center.x + (radius - width / 2) * cos(angle), y: center.y + (radius - width / 2) * sin(angle)))
        }
        var path = Path()
        path.addLines(outer + inner.reversed())
        path.closeSubpath()
        return path
    }
}

/// ハイスコア更新の印。角印の枠の中に「一」（一番）の線を 1 本引く
struct SealMark: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let frame = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        let border = side * 0.12
        let corner = CGSize(width: side * 0.05, height: side * 0.05)
        let outline = Path(roundedRect: frame.insetBy(dx: border / 2, dy: border / 2), cornerSize: corner)
        var path = outline.strokedPath(StrokeStyle(lineWidth: border))
        // 「一」は左を太く、右へ細く払う
        let left = CGPoint(x: frame.minX + side * 0.26, y: frame.midY)
        let right = CGPoint(x: frame.maxX - side * 0.24, y: frame.midY - side * 0.02)
        let thickness = side * 0.14
        var stroke = Path()
        stroke.move(to: CGPoint(x: left.x, y: left.y - thickness / 2))
        stroke.addLine(to: right)
        stroke.addLine(to: CGPoint(x: left.x, y: left.y + thickness / 2))
        stroke.closeSubpath()
        path.addPath(stroke)
        return path
    }
}

/// アドバイスの印。筆を置いて払った墨の点（読点のようなしずくの形）。丸い頭から右下へ細く払う
struct InkDropMark: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        let center = CGPoint(x: origin.x + side * 0.4, y: origin.y + side * 0.38)
        let radius = side * 0.3
        let tail = CGPoint(x: origin.x + side * 0.82, y: origin.y + side)
        // 払いの先から頭の円に引いた 2 本の接線と、頭の向こう側の弧でしずくの輪郭を作る
        let toTail = atan2(tail.y - center.y, tail.x - center.x)
        let distance = hypot(tail.x - center.x, tail.y - center.y)
        let spread = acos(radius / distance)
        let steps = 32
        var points = [tail]
        for step in 0...steps {
            let angle = toTail + spread + (2 * .pi - 2 * spread) * Double(step) / Double(steps)
            points.append(CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle)))
        }
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}

#Preview {
    HStack(spacing: 24) {
        EnsoMark().frame(width: 48, height: 48)
        SealMark().frame(width: 48, height: 48)
        InkDropMark().frame(width: 48, height: 48)
    }
    .padding()
}
