import Foundation
import Observation

/// 検索画面の状態。検索は送信したときだけ行う（入力のたびに API を叩かない）
@Observable
final class SearchModel {
    enum Phase: Equatable {
        /// まだ検索していない
        case idle
        /// 1 ページ目を読み込み中
        case searching
        /// 結果を表示中（0 件を含む）
        case loaded
        /// 1 ページ目の読み込みに失敗した
        case failed(BeatsaverClientError)
    }

    var query = ""
    private(set) var phase: Phase = .idle
    private(set) var maps: [BeatsaverMap] = []
    /// 結果を出している検索語（入力欄を書き換えても、表示中の結果の検索語は変わらない）
    private(set) var submittedQuery = ""
    private(set) var hasNextPage = false
    private(set) var isLoadingNextPage = false
    /// 次のページの読み込みに失敗した（表示中の結果は残す）
    private(set) var nextPageError: BeatsaverClientError?

    private let client: any BeatsaverClient
    private var nextPage = 0
    /// 古い検索の結果で新しい検索の結果を上書きしないための世代番号
    private var generation = 0

    init(client: any BeatsaverClient) {
        self.client = client
    }

    /// 入力欄の検索語で 1 ページ目から検索し直す
    func submit() async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        generation += 1
        let generation = generation
        submittedQuery = query
        phase = .searching
        maps = []
        hasNextPage = false
        isLoadingNextPage = false
        nextPageError = nil
        nextPage = 0

        do {
            let page = try await client.search(query: query, page: 0)
            guard generation == self.generation else { return }
            apply(page)
            phase = .loaded
        } catch {
            guard generation == self.generation else { return }
            phase = .failed(error)
        }
    }

    /// 表示中の結果に次のページを足す
    func loadNextPage() async {
        guard phase == .loaded, hasNextPage, !isLoadingNextPage else { return }
        let generation = generation
        isLoadingNextPage = true
        nextPageError = nil
        defer {
            if generation == self.generation {
                isLoadingNextPage = false
            }
        }

        do {
            let page = try await client.search(query: submittedQuery, page: nextPage)
            guard generation == self.generation else { return }
            apply(page)
        } catch {
            guard generation == self.generation else { return }
            nextPageError = error
        }
    }

    private func apply(_ page: BeatsaverSearchPage) {
        // ページの境目で同じマップが重なることがあるので、表示済みのものは足さない
        let shownIDs = Set(maps.map(\.id))
        maps.append(contentsOf: page.maps.filter { !shownIDs.contains($0.id) })
        hasNextPage = page.hasNextPage && page.page < BeatsaverAPIClient.maxPage
        nextPage = page.page + 1
    }
}

extension BeatsaverClientError {
    /// 画面に出す説明
    var message: String {
        switch self {
        case .invalidRequest:
            "検索語を \(BeatsaverAPIClient.maxQueryLength) 文字以内で入力してください"
        case .notFound:
            "曲が見つかりませんでした"
        case .httpStatus(let status):
            "beatsaver が応答しませんでした（\(status)）。時間をおいて試してください"
        case .responseTooLarge, .invalidResponse:
            "beatsaver の応答を読み取れませんでした"
        case .excluded:
            "この曲は表示できません"
        case .transport(.notConnectedToInternet), .transport(.networkConnectionLost), .transport(.dataNotAllowed):
            "インターネットに接続できません。電波の良い場所で試してください"
        case .transport(.timedOut):
            "接続がタイムアウトしました。電波の良い場所で試してください"
        case .transport:
            "beatsaver に接続できませんでした"
        }
    }
}
