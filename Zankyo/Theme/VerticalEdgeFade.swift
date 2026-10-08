import SwiftUI

/// 上下の端で内容が背景に溶けるように消えるマスク。色を重ねないので、テーマごとの背景の光を邪魔しない。
/// マスクの外（SafeArea の外にはみ出してスクロールする内容など）は描かれない
struct VerticalEdgeFade: ViewModifier {
    /// 端から不透明になるまでの長さ
    var length: CGFloat

    func body(content: Content) -> some View {
        content.mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: length)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: length)
            }
        }
    }
}

extension View {
    /// 上下の端を `length` の長さのグラデーションで消す。スクロールしていない位置で内容の端が薄くならないよう、
    /// 内容の上下には同じ長さの余白を足しておく
    func verticalEdgeFade(length: CGFloat) -> some View {
        modifier(VerticalEdgeFade(length: length))
    }
}
