import SwiftUI

/// ライブラリと検索を行き来するルート。タブは画面下（片手の親指が届く位置）に出る
struct RootView: View {
    enum Tab: Hashable {
        case library
        case search
    }

    @State private var selection: Tab = .library
    @State private var searchModel: SearchModel
    @State private var downloads: DownloadModel

    init(client: any BeatsaverClient, downloader: any MapDownloading) {
        _searchModel = State(initialValue: SearchModel(client: client))
        _downloads = State(initialValue: DownloadModel(downloader: downloader))
    }

    var body: some View {
        TabView(selection: $selection) {
            LibraryView(onSearch: { selection = .search })
                .tabItem { Label("ライブラリ", systemImage: "music.note.list") }
                .tag(Tab.library)
            SearchView(model: searchModel, downloads: downloads)
                .tabItem { Label("検索", systemImage: "magnifyingglass") }
                .tag(Tab.search)
        }
    }
}

#Preview {
    RootView(client: BeatsaverAPIClient(), downloader: MapDownloader())
}
