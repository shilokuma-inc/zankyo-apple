import Foundation
import Observation

/// 譜面 ZIP の取得の状態。取得はユーザー操作で 1 曲ずつ行う（同時に 2 曲以上は取得しない）
@Observable
final class DownloadModel {
    enum State: Equatable {
        /// 未取得
        case notDownloaded
        /// 取得中。0〜1 の進み具合（不明なら nil）
        case downloading(Double?)
        /// 取得済み（展開は後続のタスク）
        case downloaded
        /// 取得に失敗した
        case failed(MapDownloadError)
    }

    /// 取得中のマップのキー
    private(set) var activeMapID: String?
    private var progress: Double?
    private var failures: [String: MapDownloadError] = [:]
    /// この起動中に取得したもの。起動前に取得したものはファイルの有無で判断する
    private var downloadedHashes: Set<String> = []
    private var task: Task<Void, Never>?

    private let downloader: any MapDownloading
    /// 取得し終えた曲を足す一覧
    private let library: LibraryStore?

    init(downloader: any MapDownloading, library: LibraryStore? = nil) {
        self.downloader = downloader
        self.library = library
    }

    var isDownloading: Bool {
        activeMapID != nil
    }

    func state(for map: BeatsaverMap) -> State {
        if map.id == activeMapID { return .downloading(progress) }
        if let error = failures[map.id] { return .failed(error) }
        guard let hash = map.latestVersion?.hash else { return .notDownloaded }
        if downloadedHashes.contains(hash) || downloader.downloadedFile(hash: hash) != nil {
            return .downloaded
        }
        return .notDownloaded
    }

    /// `map` の最新版を取得する。別の曲を取得中なら何もしない
    func start(_ map: BeatsaverMap) {
        guard activeMapID == nil, let version = map.latestVersion else { return }
        activeMapID = map.id
        progress = nil
        failures[map.id] = nil
        task = Task {
            await run(map: map, version: version)
        }
    }

    /// 取得中のものを中止する
    func cancel() {
        task?.cancel()
    }

    /// ライブラリから消した曲を、取得していない状態に戻す
    func forget(hash: String) {
        downloadedHashes.remove(hash)
        downloadedHashes.remove(hash.lowercased())
    }

    /// テストから完了を待つ
    func waitUntilFinished() async {
        await task?.value
    }

    private func run(map: BeatsaverMap, version: BeatsaverMapVersion) async {
        defer {
            activeMapID = nil
            progress = nil
            task = nil
        }
        do {
            _ = try await downloader.download(version) { [weak self] value in
                Task { @MainActor in
                    guard let self, self.activeMapID == map.id else { return }
                    // 通知が前後しても進み具合を戻さない
                    self.progress = max(self.progress ?? 0, value)
                }
            }
            downloadedHashes.insert(version.hash)
            library?.add(map: map, version: version)
        } catch .cancelled {
            // 中止は失敗として残さない
        } catch {
            failures[map.id] = error
        }
    }
}

extension MapDownloadError {
    /// 画面に出す説明
    var message: String {
        switch self {
        case .untrustedURL:
            "この曲は取り込めません（beatsaver 以外の場所を指しています）"
        case .tooLarge:
            "ファイルが大きすぎるため取り込めません（上限 \(MapDownloader.maxBytes / 1_024 / 1_024)MB）"
        case .httpStatus(let status):
            "beatsaver が応答しませんでした（\(status)）。時間をおいて試してください"
        case .hashMismatch:
            "ダウンロードしたファイルが壊れています。もう一度試してください"
        case .notZip:
            "譜面の ZIP ではないため取り込めません"
        case .cancelled:
            "中止しました"
        case .transport(.notConnectedToInternet), .transport(.networkConnectionLost), .transport(.dataNotAllowed):
            "インターネットに接続できません。電波の良い場所で試してください"
        case .transport(.timedOut):
            "接続がタイムアウトしました。電波の良い場所で試してください"
        case .transport:
            "ダウンロードできませんでした"
        case .storage:
            "保存できませんでした。端末の空き容量を確かめてください"
        }
    }
}
