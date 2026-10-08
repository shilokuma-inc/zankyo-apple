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
- テストターゲットも MainActor が既定。`StubURLProtocol` のハンドラ（`@Sendable`）からテスト型の static を呼ぶなら、テストの型を `nonisolated struct` にする（2026-10-07）
- 同じ Simulator で 2 つの `xcodebuild test` を同時に走らせると、互いのテストホストを落とす（「Test crashed with signal term before establishing connection」と `simctl` が見つからないというログが出る）。テストは直列に流す（2026-10-07）
- Swift Testing の `#expect` / `#require` の中で `mutating` なメソッドを呼ぶと、マクロの展開先で「immutable value」のコンパイルエラーになる。結果をいったん `let` に受けてから検証する（2026-10-07）
- `SWIFT_APPROACHABLE_CONCURRENCY = YES` なので、`nonisolated` な async 関数も呼び出し元のアクター（MainActor）で動く。ZIP の展開・ハッシュ・パース・デコードのような重い処理は `@concurrent` を付けてメインスレッドから外す。戻り値が Sendable でない型（`AVAudioPCMBuffer` を持つクラスなど）は `sending` で返す（2026-10-08）
- テスト用の Ogg Vorbis は、libvorbis の `examples/encoder_example.c`（44.1kHz・ステレオの WAV を標準入力で受ける）を clang でビルドして作れる。afconvert は Vorbis でエンコードできない。テストバンドルの素材は `ZankyoTests/Fixtures/` に置けばフォルダ同期で入る（2026-10-08）
- `List` の行全体を `NavigationLink` にすると、行の中の `Link` は `.borderless` を付けていても行のタップと重なり、行の中央をタップしただけで Safari が開くことがある。行の中にはリンクを置かない（2026-10-08）
- Simulator ではモーション入力が使えずプレイを始められないので、PR 用のプレイ画面のスクリーンショットは、コミットしない一時的なユニットテストで撮る。テストからホストアプリのウィンドウの `rootViewController` に `PlayView` を載せ、`SilentSongClock` の `now` を差し替えて時刻を止め、`GameSession.handle` に `CutEvent` を渡せば判定の表示まで出せる。静止画は待っている間に `simctl io screenshot`、GIF は `drawHierarchy` で取ったフレームを ImageIO で書き出す（ffmpeg が無くてよい）（2026-10-08）
- `Zankyo/` の下に置いたリソースは、フォルダ同期グループでもサブフォルダを保たずにバンドルの直下へ平らに入る。同じ名前のファイルを別のフォルダに置くと衝突するので、`sample-<slug>.zip` のように名前で分ける（`Zankyo/SampleSongs/`）（2026-10-08）
- Swift Testing の `#expect` の中で `allSatisfy(\.isSample)` のようにキーパスを渡すと、マクロの展開先で「call can throw」のコンパイルエラーになる。クロージャ（`allSatisfy { $0.isSample }`）で書く（2026-10-08）
- サンプル楽曲の音源（Ogg Vorbis）は、SPM で取得済みの vorbis-swift の `examples/encoder_example.c` をビルドして作れる（`scripts/sample-songs/build-encoder.sh`）。libogg の `config_types.h` は configure で作られるので、固定幅の型で書いて足す（2026-10-08）
- 検索画面の PR 用スクリーンショットは、Simulator に日本語キーボードが入っていると、外から送った文字がかな変換されて検索語を打てない。コミットしない一時パッチで `RootView` に起動引数（`-ScreenshotQuery camellia` など）を読む `.task` を足し、検索タブを開いて `SearchModel.submit()` まで呼ぶと、Before / After を同じ条件で撮れる。取り込んだ曲はアプリを入れ直しても残るので、ライブラリ画面は一度取り込めば Before / After のビルドを入れ替えて撮れる（2026-10-08）
- `contentShape(.contextMenuPreview, …)` は macOS では使えない（コンパイルエラー。macOS のメニューにはプレビューが無い）。iOS / visionOS で通っても macOS で落ちるので、`#if !os(macOS)` で外す（2026-10-08）
- Debug ビルドを `-ZankyoDemoMotion` 付きで起動すれば、Simulator でもライブラリから曲を選んでプレイ画面を普通に動かせる。`simctl io <udid> recordVideo` で録画し、`AVAssetImageGenerator` で切り出したコマを ImageIO で GIF にすると、Before / After を同じ曲・同じ区間で比べられる。デモの首振りはノーツに合わせないのでほぼミスになり、ヒットの表示は出ない。ヒットの表示は、コミットしない一時テストで `ImageRenderer` に描かせて確かめる（2026-10-08）
- 判定の表示（点数など）は、iPhone 17 Pro では判定の線の下にちょうど 1 行分しか収まらない。`PlayView.judgementLabelHeight` を増やすと線の上（ノーツの通り道）に出てしまうので、表示を足すときは行を増やさず横に並べる（2026-10-08）
- 一時的なユニットテストでホストアプリに載せた画面は、テストが `Task.sleep` で待っている間（XCTest が run loop を独自のモードで回す）はタップが届かないことがある。ボタンを押して確かめるときは、テストで取り込みのファイル（`Downloads/<hash>.zip`）を置いたうえで `Library/Library.json` を Simulator のアプリのデータ領域（`simctl get_app_container … data`）に書き、アプリを普通に起動して操作する（2026-10-08）
- サンプル楽曲を足すときは、テンポによって Easy と Normal のノーツ数が同じになり、`bundledSongIsPlayable`（易しいほどノーツが少ない）が落ちる。Easy は 1.3 秒以上空けて拾うので、4/4 で半小節が 1.3 秒以上になる BPM（92 以下）だと半小節ごとに拾い、Normal と同じになる。テンポを上げるか、旋律の音の優先度を変える（2026-10-09）
- 一覧をスクロールした先の PR 用スクリーンショットは、コミットしない一時的な UI テストで `swipeUp` してから `XCUIScreen.main.screenshot().pngRepresentation` を書き出せば、Simulator を操作する許可が無くても撮れる。書き出し先は `TEST_RUNNER_SHOT_DIR=…` のように `TEST_RUNNER_` を付けた環境変数で `xcodebuild test` から渡す（2026-10-09）
- 結果画面の PR 用の画面は、コミットしない一時的な UI テストで `-ZankyoDemoMotion` を付けて起動し、ライブラリの先頭の曲（歓喜の歌・約 62 秒）を「Easy でスタート」で始めて最後まで待てば、FINISH から結果画面まで録画できる。デモの首振りはノーツに合わないので、ランク E・0 点になる。良い成績の見た目は、一時的なユニットテストでホストアプリのウィンドウに `ResultView` を載せ、登場アニメーションが終わるまで（約 3 秒）待ってから `drawHierarchy` で書き出す（2026-10-09）
- SwiftLint はビルドのプラグインでも走るので、コミットしない一時的なテストでも違反（長い行・`large_tuple` など）があるとビルドが止まる。一時的なテストは先頭で `// swiftlint:disable` するか、規則に合わせて書く（2026-10-09）

## beatsaver / 譜面

- 検索 API の `automapper` クエリは「true = 両方 / false = AI のみ / 省略 = AI を除く」。NSFW は `nsfw` フィールドで、false のときは省略されることがある。除外はクライアント側でも `nsfw`・`automapper`・`declaredAi` を見て行う（2026-10-07）
- 日時は小数秒の有無が混在しうるので、`.iso8601` 固定ではなく両方を受けるデコードにする（2026-10-07）
- OS 標準の Ogg Vorbis デコードは iOS 18.4 / macOS 15.4 から。Deployment Target（iOS 17 / macOS 14 / visionOS 2）では OS 標準に頼れない（2026-10-07）
- `URLSession.bytes(for:)` を 1 バイトずつ読むのは遅い（Debug の Simulator で 2MB に 40 秒近くかかる）。譜面 ZIP のような数 MB 以上はデータタスクの delegate で塊ごとに受ける（2026-10-07）
- `FileHandle.read(upToCount:)` は末尾に達すると空の `Data` ではなく `nil` を返す。`nil` をエラー扱いすると、ファイルを読み終えたところで失敗する（2026-10-07）
- 難易度譜面 v2 の BPM 変化は `_events` の type 100（`_floatValue` が BPM）と、エディタ拡張の `_BPMChanges`（`_BPM`。`_bpm` の表記もある）の 2 通りで書かれる。v3 は `bpmEvents`（`b` / `m`）で、拍 0 の変化は Info.dat の BPM を置き換える。初期の v2 には `_version` が無いものがある（2026-10-07）
- beatsaver の `hash` は譜面 ZIP 全体の SHA-1 ではない。`Info.dat` と譜面ファイルの中身をつなげた SHA-1 で、v2 / v3 は `Info.dat` → 各 `_beatmapFilename`、v4 は `Info.dat` → `audioDataFilename` → 難易度ごとに `beatmapDataFilename`・`lightshowDataFilename`（同じファイルを指していても毎回足す）の順。実在の譜面で一致を確かめた（`MapHash`）（2026-10-08）
- 実在の譜面にはライトショーや難易度譜面が 1 ファイル 27MB 近いものがある（`BeatmapParser.maxBytes` の 20MB を超える）（2026-10-08）
- 最近の譜面は難易度譜面が v4（`"version": "4.x"`、`colorNotes` と `colorNotesData` に分かれた形式）のものが多い。Info.dat が v4 でも難易度譜面が v3 のこともあるので、遊べるかは難易度譜面ごとに決まる（2026-10-08）
- 実在の譜面の音源は 44.1kHz と 48kHz が混在し、モノラルもある。3 分前後の曲は Simulator（Debug）で 1 秒前後でデコードできる（2026-10-08）
- v4 の難易度譜面は `colorNotes`（`b` 拍・`i` 見た目の番号）と `colorNotesData`（`x` `y` `c` `d`）に分かれ、値が 0 のキーは省かれる（`{"b": 912}` は `i` が 0）。BPM の変化は難易度譜面ではなく、Info.dat の `audioDataFilename` の `bpmData`（サンプル位置 `si`〜`ei` が拍 `sb`〜`eb` に対応する区間）に書かれる。速度を変える演出で 1,000 BPM を超える区間もある（2026-10-08）

## モーション入力（AirPods）

- 「切る」は角速度のピークで取る。振った直後に首を戻す動きは逆向きの強いピークになるので、直前と逆向きの振りを短い時間（既定 0.35 秒）出さない。強い振りは減っていく途中でも閾値を超えたままなので、同じ向きは閾値をいったん下回るまで次の振りにしない（2026-10-07）
- `CMHeadphoneMotionManager` の更新ハンドラと delegate は CoreMotion のキューで呼ばれる。MainActor 既定のメソッドの中でクロージャを書くと MainActor に隔離され、別スレッドで呼ばれた時点で実行時に落ちうるので、`nonisolated static func` で作って渡す。ハンドラの型は Swift では `CMHeadphoneMotionManager.DeviceMotionHandler`（`CMHeadphoneDeviceMotionHandler` は改名済みでエラー）。Simulator では `isDeviceMotionAvailable` が false（2026-10-07）
- モーション入力の `AsyncStream` は受け取る側が 1 つなので、画面の見える化は入力を包む `MotionMonitor` でサンプルを中継して作る。判定には同じサンプルをそのまま渡す（2026-10-08）
- モーションの取れない Simulator で頭の動きの表示を確かめるときは、Debug ビルドの起動引数 `-ZankyoDemoMotion` で決まった首振りを繰り返す入力に切り替えられる（2026-10-08）
- 首を戻す逆向きの振りを間引く検出（`CutDetector` の `returnWindow`）は、戻す動きから振り始めると戻す側に位相がそろい、拍の裏の振りばかり数え続ける。向きを決めないヘドバン（`HeadbangDetector`）では間引かず、裏の振りはノーツの時間窓（前後 0.15 秒）に入らないことで判定から外す。ノーツの最小間隔（0.35 秒）の半分が時間窓より広いことが前提なので、どちらかを変えるときは見直す（2026-10-08）

## 画面・テーマ

- プレイ画面・キャリブレーション中の画面の色は `@Environment(\.palette)`（`ThemePalette`）から取る。明るいテーマ（モノクロ・ポップ・キュート）があるので、`.white` / `.black` を直に書くと文字や線が背景に溶ける。文字は `ink`、板は `panel`、光（`shadow`）は `glow(_:_:)` を使う。`NeonTheme` は並行ブランチのために残した deprecated の互換用で、選んだテーマに追従しない（2026-10-08）
