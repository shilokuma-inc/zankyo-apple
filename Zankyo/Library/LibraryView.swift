import SwiftUI

/// 取り込み済みの曲の一覧。曲の取り込みは後続のタスクで足す
struct LibraryView: View {
    let onSearch: () -> Void

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("取り込んだ曲はまだありません", systemImage: "music.note.list")
            } description: {
                Text("beatsaver で曲を検索して取り込むと、ここに並びます。")
            } actions: {
                Button("曲を検索する", action: onSearch)
                    .buttonStyle(.borderedProminent)
            }
            .navigationTitle("ライブラリ")
        }
    }
}

#Preview {
    LibraryView(onSearch: {})
}
