import SwiftUI

/// beatsaver の曲をテキストで検索する画面。入力欄は片手で届くように画面下に置く
struct SearchView: View {
    @Bindable var model: SearchModel
    let downloads: DownloadModel
    @FocusState private var isQueryFocused: Bool

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("検索")
                .safeAreaInset(edge: .bottom) {
                    queryField
                }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle:
            ContentUnavailableView(
                "beatsaver の曲を探す",
                systemImage: "magnifyingglass",
                description: Text("曲名・アーティスト・マッパー名で検索できます。")
            )
        case .searching:
            ProgressView("検索中…")
        case .failed(let error):
            ContentUnavailableView {
                Label("検索できませんでした", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.message)
            } actions: {
                Button("もう一度検索する") { submit() }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded where model.maps.isEmpty:
            ContentUnavailableView.search(text: model.submittedQuery)
        case .loaded:
            results
        }
    }

    private var results: some View {
        List {
            ForEach(model.maps) { map in
                SearchResultRow(map: map, downloads: downloads)
            }
            if model.hasNextPage || model.nextPageError != nil {
                nextPageRow
            }
        }
    }

    @ViewBuilder private var nextPageRow: some View {
        VStack(spacing: 8) {
            if let error = model.nextPageError {
                Text(error.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if model.isLoadingNextPage {
                ProgressView()
            } else if model.hasNextPage {
                Button(model.nextPageError == nil ? "次のページを読み込む" : "もう一度読み込む") {
                    Task { await model.loadNextPage() }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var queryField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("曲名・アーティスト・マッパー名", text: $model.query)
                .textFieldStyle(.plain)
                .focused($isQueryFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit(submit)
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("検索語を消す")
            }
            Button("検索", action: submit)
                .buttonStyle(.borderedProminent)
                .disabled(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func submit() {
        isQueryFocused = false
        Task { await model.submit() }
    }
}

#Preview {
    SearchView(model: SearchModel(client: BeatsaverAPIClient()), downloads: DownloadModel(downloader: MapDownloader()))
}
