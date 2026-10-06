import Foundation

/// beatsaver の API。画面やテストからはこのプロトコル越しに使う
nonisolated protocol BeatsaverClient: Sendable {
    /// テキストで検索する。`page` は 0 起点
    func search(query: String, page: Int) async throws(BeatsaverClientError) -> BeatsaverSearchPage
    /// キー（例: `1f33`）でマップを取得する
    func map(id: String) async throws(BeatsaverClientError) -> BeatsaverMap
    /// 譜面 ZIP のハッシュでマップを取得する
    func map(hash: String) async throws(BeatsaverClientError) -> BeatsaverMap
}

nonisolated enum BeatsaverClientError: Error, Equatable, Sendable {
    /// 検索語・キー・ハッシュの形式が不正（リクエストを送っていない）
    case invalidRequest
    /// 指定したマップが見つからない（404）
    case notFound
    /// 2xx 以外の応答
    case httpStatus(Int)
    /// レスポンスが上限より大きい
    case responseTooLarge
    /// レスポンスの形式が不正
    case invalidResponse
    /// 除外対象（NSFW・自動生成）のマップ
    case excluded
    /// 通信エラー（オフラインなど）
    case transport(URLError.Code)
}

/// 画面に出さないマップの条件
nonisolated struct BeatsaverContentFilter: Sendable, Hashable {
    var excludesNSFW: Bool
    var excludesGenerated: Bool

    /// Discussion #3 Q9: NSFW と自動生成（automapper・AI）の譜面は既定で除外する
    static let `default` = Self(excludesNSFW: true, excludesGenerated: true)

    func allows(_ map: BeatsaverMap) -> Bool {
        if excludesNSFW, map.isNSFW { return false }
        if excludesGenerated, map.isGenerated { return false }
        return true
    }
}

/// `api.beatsaver.com` を叩く実装
nonisolated struct BeatsaverAPIClient: BeatsaverClient {
    /// API の JSON の上限。検索 1 ページ（20 件）は 100KB 程度なので、十分な余裕を持たせる
    static let maxResponseBytes = 2 * 1_024 * 1_024
    /// 検索語の上限（文字数）
    static let maxQueryLength = 100
    /// ページ番号の上限。これより先は人が手で辿る範囲を超える
    static let maxPage = 999

    private let session: URLSession
    private let baseURL: URL
    private let filter: BeatsaverContentFilter
    private let userAgent: String

    init(
        session: URLSession = .shared,
        baseURL: URL = BeatsaverHost.api,
        filter: BeatsaverContentFilter = .default,
        userAgent: String = Self.defaultUserAgent
    ) {
        self.session = session
        self.baseURL = baseURL
        self.filter = filter
        self.userAgent = userAgent
    }

    /// beatsaver 側から識別できる User-Agent（アプリ名・バージョン・連絡先）
    static var defaultUserAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "Zankyo/\(version) (+https://github.com/shilokuma-inc/zankyo-apple)"
    }

    func search(query: String, page: Int) async throws(BeatsaverClientError) -> BeatsaverSearchPage {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= Self.maxQueryLength, (0...Self.maxPage).contains(page) else {
            throw .invalidRequest
        }
        var components = URLComponents(url: baseURL.appending(path: "search/text/\(page)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "order", value: "Relevance")
        ]
        guard let url = components?.url else { throw .invalidRequest }
        let response: SearchResponse = try await get(url)
        return BeatsaverSearchPage(
            maps: response.docs.elements.filter(filter.allows),
            page: page,
            totalPages: response.info?.pages.map { min(max($0, 0), Self.maxPage + 1) }
        )
    }

    func map(id: String) async throws(BeatsaverClientError) -> BeatsaverMap {
        guard BeatsaverValidation.isValidKey(id) else { throw .invalidRequest }
        return try await fetchMap(baseURL.appending(path: "maps/id/\(id.lowercased())"))
    }

    func map(hash: String) async throws(BeatsaverClientError) -> BeatsaverMap {
        guard BeatsaverValidation.isValidHash(hash) else { throw .invalidRequest }
        return try await fetchMap(baseURL.appending(path: "maps/hash/\(hash.lowercased())"))
    }

    private func fetchMap(_ url: URL) async throws(BeatsaverClientError) -> BeatsaverMap {
        let map: BeatsaverMap = try await get(url)
        guard filter.allows(map) else { throw .excluded }
        return map
    }

    private func get<Response: Decodable>(_ url: URL) async throws(BeatsaverClientError) -> Response {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw .transport(error.code)
        } catch {
            throw .transport(.unknown)
        }

        guard let http = response as? HTTPURLResponse else { throw .invalidResponse }
        if http.statusCode == 404 { throw .notFound }
        guard (200..<300).contains(http.statusCode) else { throw .httpStatus(http.statusCode) }
        guard data.count <= Self.maxResponseBytes else { throw .responseTooLarge }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            // beatsaver の日時は小数秒の有無が混在する
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text) { return date }
            return try Date.ISO8601FormatStyle().parse(text)
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw .invalidResponse
        }
    }
}

nonisolated private struct SearchResponse: Decodable {
    let docs: LossyDecodableArray<BeatsaverMap>
    let info: Info?

    struct Info: Decodable {
        let pages: Int?
    }
}
