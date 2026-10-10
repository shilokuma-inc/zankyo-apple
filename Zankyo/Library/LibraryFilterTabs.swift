import SwiftUI

/// ライブラリの絞り込みのタブ。開いているタブの下に下線を引き、押すかバーを横にスワイプして切り替える
///
/// 一覧の行には左右の swipe actions（お気に入り・消す）があるので、スワイプはこのバーの上だけで受ける。
/// タブを `Button` にするとボタンが横の動きも受け取ってしまいスワイプが届かないので、タップのジェスチャーとボタンの trait で作る
struct LibraryFilterTabs: View {
    @Binding var selection: LibraryView.Filter

    @Namespace private var indicator
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// これより長く横に動かしたら、隣のタブへ切り替える
    static let swipeThreshold: CGFloat = 40

    var body: some View {
        HStack(spacing: 0) {
            ForEach(LibraryView.Filter.allCases) { filter in
                tab(filter)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.quaternary)
                .frame(height: 1)
        }
        .contentShape(.rect)
        .highPriorityGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    guard let next = Self.filter(after: selection, swipe: value.translation) else { return }
                    select(next)
                }
        )
        .opacity(isEnabled ? 1 : 0.5)
    }

    private func tab(_ filter: LibraryView.Filter) -> some View {
        let isSelected = selection == filter
        return VStack(spacing: 8) {
            Text(filter.title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            ZStack {
                if isSelected {
                    Rectangle()
                        .fill(.tint)
                        .matchedGeometryEffect(id: "indicator", in: indicator)
                }
            }
            .frame(height: 2)
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(.rect)
        .onTapGesture { select(filter) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { select(filter) }
    }

    private func select(_ filter: LibraryView.Filter) {
        // 選んでいる間（`.disabled`）はタップ・スワイプ・VoiceOver の操作のどれでも切り替えない
        guard isEnabled, filter != selection else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            selection = filter
        }
    }

    /// 横のスワイプで切り替える先のタブ。左へ払えば右のタブ、右へ払えば左のタブ。縦に動かしたときや端のタブでは nil
    static func filter(after current: LibraryView.Filter, swipe translation: CGSize) -> LibraryView.Filter? {
        guard abs(translation.width) >= swipeThreshold, abs(translation.width) > abs(translation.height) else { return nil }
        let all = LibraryView.Filter.allCases
        guard let index = all.firstIndex(of: current) else { return nil }
        let next = translation.width < 0 ? all.index(after: index) : index - 1
        return all.indices.contains(next) ? all[next] : nil
    }
}

#Preview {
    @Previewable @State var filter = LibraryView.Filter.all
    LibraryFilterTabs(selection: $filter)
        .padding()
}
