import SwiftUI

/// ライブラリと検索を行き来するルート。タブは画面下（片手の親指が届く位置）に出る
struct RootView: View {
    enum Tab: Hashable {
        case library
        case search
        case calibration
    }

    @State private var selection: Tab = .library
    @State private var searchModel: SearchModel
    @State private var downloads: DownloadModel
    @State private var calibration: CalibrationModel
    @State private var library: LibraryStore
    @State private var highScores = HighScoreStore()
    private let motion: MotionMonitor

    init(
        client: any BeatsaverClient,
        downloader: any MapDownloading,
        motion: MotionMonitor,
        metronome: any Metronome,
        library: LibraryStore = LibraryStore()
    ) {
        _searchModel = State(initialValue: SearchModel(client: client))
        _library = State(initialValue: library)
        _downloads = State(initialValue: DownloadModel(downloader: downloader, library: library))
        _calibration = State(initialValue: CalibrationModel(input: motion, metronome: metronome))
        self.motion = motion
    }

    var body: some View {
        TabView(selection: $selection) {
            LibraryView(
                library: library,
                downloads: downloads,
                motion: motion,
                highScores: highScores,
                onSearch: { selection = .search }
            )
                .tabItem { Label("ライブラリ", systemImage: "music.note.list") }
                .tag(Tab.library)
            SearchView(model: searchModel, downloads: downloads)
                .tabItem { Label("検索", systemImage: "magnifyingglass") }
                .tag(Tab.search)
            CalibrationView(model: calibration, motion: motion)
                .tabItem { Label("キャリブレーション", systemImage: "metronome") }
                .tag(Tab.calibration)
        }
    }
}

#Preview {
    RootView(
        client: BeatsaverAPIClient(),
        downloader: MapDownloader(),
        motion: MotionMonitor(base: RecordedMotionInput(samples: [])),
        metronome: ClickMetronome()
    )
}
