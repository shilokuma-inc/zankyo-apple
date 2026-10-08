import SwiftUI

/// ライブラリと検索を行き来するルート。タブは画面下（片手の親指が届く位置）に出る。選んだテーマはここからアプリ全体に効かせる
struct RootView: View {
    enum Tab: Hashable {
        case library
        case search
        case calibration
        case settings
    }

    @State private var selection: Tab = .library
    /// 保存していない・知らない値なら既定のサイバーパンクにする
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .cyberpunk
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
        _calibration = State(initialValue: CalibrationModel(input: motion, metronome: metronome, detection: { motion.detection }))
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
            SettingsView(theme: $theme, motion: motion)
                .tabItem { Label("設定", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .appTheme(theme)
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
