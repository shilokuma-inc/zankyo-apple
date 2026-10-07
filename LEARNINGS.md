# LEARNINGS — zankyo-apple 固有の知見

このリポジトリだけに当てはまる知見を溜める。全リポジトリ共通の知見は `~/.agents/LEARNINGS.md` に書く。

- 1 項目 = 1 つの箇条書き。見出しの下に追記する。日付（YYYY-MM-DD）を添える
- PC 固有の値（ローカルパス・Simulator の UDID）は書かない

## ビルド・テスト

- iOS / macOS / visionOS の 1 ターゲット構成。pbxproj は `SDKROOT = auto`・`SUPPORTED_PLATFORMS = iphoneos iphonesimulator macosx xros xrsimulator`・`TARGETED_DEVICE_FAMILY = 1,2,7` にしてある（2026-10-07）
- MainActor 既定のため、`nonisolated struct` でも **extension に書いた `static let` は MainActor に隔離される**。nonisolated な `init(from:)` から参照するなら `nonisolated static let` にする（2026-10-07）
- `swiftlint` も `DEVELOPER_DIR` が Xcode を指していないと sourcekitd を読めずに落ちる（2026-10-07）
- テストの `URLProtocol` スタブは、セッションごとの ID をリクエストヘッダに載せ、`OSAllocatedUnfairLock` の辞書でハンドラを引き分けると、Swift Testing の並行実行でも混線しない（`ZankyoTests/Support/StubURLProtocol.swift`）（2026-10-07）
- CI は Xcode 26.3（Swift 6.2）でローカルより古いことがある。Swift 6.2 では **extension で付けたプロトコル準拠（`extension X: Decodable`）が MainActor に隔離され**、nonisolated な文脈で使うとエラーになる（新しい Xcode では通ってしまう）。準拠を書く extension は `nonisolated extension` にする（2026-10-07）
- `scrollDismissesKeyboard` は visionOS で使えない（コンパイルエラー）。iOS / macOS だけ通っても visionOS で落ちる SwiftUI の修飾子があるので、共通の View では visionOS のビルドまで確かめる（2026-10-07）

## beatsaver / 譜面

- 検索 API の `automapper` クエリは「true = 両方 / false = AI のみ / 省略 = AI を除く」。NSFW は `nsfw` フィールドで、false のときは省略されることがある。除外はクライアント側でも `nsfw`・`automapper`・`declaredAi` を見て行う（2026-10-07）
- 日時は小数秒の有無が混在しうるので、`.iso8601` 固定ではなく両方を受けるデコードにする（2026-10-07）
- OS 標準の Ogg Vorbis デコードは iOS 18.4 / macOS 15.4 から。Deployment Target（iOS 17 / macOS 14 / visionOS 2）では OS 標準に頼れない（2026-10-07）

## モーション入力（AirPods）
