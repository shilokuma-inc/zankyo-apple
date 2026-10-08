import SwiftUI

/// 設定の画面。遊び方・効果音・テーマを選ぶ。選ぶとすぐにアプリ全体へ反映し、見本でプレイ画面の見た目を確かめられる
struct SettingsView: View {
    @Binding var theme: AppTheme
    /// 遊び方を切り替えると、頭の動きの表示とプレイ・キャリブレーションの検出にすぐ反映する
    let motion: MotionMonitor
    var store = SwingSensitivityStore()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(PlayStyle.allCases) { style in
                        PlayStyleRow(style: style, isSelected: style == motion.detection.style) {
                            motion.detection.style = style
                            store.save(playStyle: style)
                        }
                    }
                } header: {
                    Text("遊び方")
                } footer: {
                    Text("ハイスコアは遊び方ごとに記録します。遊び方を変えたら、キャリブレーションで測り直すと判定が合いやすくなります。")
                }
                Section {
                    NavigationLink {
                        ScoringGuideView()
                    } label: {
                        Label("スコアの仕組みとハイスコアのコツ", systemImage: "questionmark.circle")
                    }
                }
                HitSoundSettingsSection()
                Section("プレイ画面の見本") {
                    ThemePreview(showsDirections: motion.detection.style.usesDirection)
                        .frame(height: 220)
                        .listRowInsets(EdgeInsets())
                }
                BackgroundLightSettingsSection()
                Section {
                    ForEach(AppTheme.allCases) { item in
                        ThemeRow(theme: item, isSelected: item == theme) {
                            theme = item
                        }
                    }
                } header: {
                    Text("テーマ")
                } footer: {
                    Text("プレイ画面とアプリ全体の色・明るさ・書体が変わります。")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("設定")
        }
    }
}

/// 遊び方の 1 行。名前と説明を並べ、選んでいるものに印を付ける
private struct PlayStyleRow: View {
    let style: PlayStyle
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(style.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(style.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.headline)
                        .foregroundStyle(.tint)
                }
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 選んでいるテーマのプレイ画面の見本。プレイ画面と同じ部品で、レーン・ノーツ・スコアを止めた状態で描く
private struct ThemePreview: View {
    /// ノーツに向きの矢印を出す（向きを問わないヘドバンでは出さない）
    let showsDirections: Bool

    /// 背景の光の演出。オンなら、拍に合わせて光った瞬間の光を見本にも出す
    @AppStorage(BackgroundLightSetting.storageKey) private var showsLights = BackgroundLightSetting.defaultValue
    private static let lights = LightShow(lighting: .empty, timeline: BeatTimeline(bpm: 120), duration: 10).state(at: 0.08)

    /// 見本のノーツ（判定の線に届くまでの秒と向き）
    private static let notes: [(remaining: TimeInterval, direction: SwingDirection?)] = [
        (0.15, .left), (0.4, .right), (0.65, .up), (0.9, nil)
    ]

    var body: some View {
        GeometryReader { proxy in
            let geometry = PlayfieldGeometry(size: proxy.size, approachTime: 1)
            ZStack {
                if showsLights {
                    PlayfieldLights(geometry: geometry, state: Self.lights)
                }
                PlayfieldLane(geometry: geometry)
                PlayfieldGrid(geometry: geometry, currentTime: 0)
                ForEach(Self.notes.indices, id: \.self) { index in
                    let note = Self.notes[index]
                    let y = geometry.y(remaining: note.remaining)
                    NoteBlock(direction: showsDirections ? note.direction : nil, size: 40 * geometry.scale(atY: y))
                        .position(x: geometry.centerX, y: y)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            ScoreReadout(score: 12_345, combo: 42)
                .padding(12)
        }
        .overlay(alignment: .topTrailing) {
            MultiplierRing(multiplier: 4, progress: 0.6)
                .padding(12)
        }
        .background { PlayfieldBackdrop(back: showsLights ? Self.lights.back : nil) }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("プレイ画面の見本")
    }
}

/// テーマの 1 行。色見本とテーマの書体で書いた名前・説明を並べ、選んでいるものに印を付ける
private struct ThemeRow: View {
    let theme: AppTheme
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                ThemeSwatch()
                    .environment(\.palette, theme.palette)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(theme.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .fontDesign(theme.palette.fontDesign)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.headline)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// テーマの色見本。プレイ画面の空間の上に、4 つの向きのノーツを並べる
private struct ThemeSwatch: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                NoteBlock(direction: .left, size: 18)
                NoteBlock(direction: .right, size: 18)
            }
            GridRow {
                NoteBlock(direction: .up, size: 18)
                NoteBlock(direction: nil, size: 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { PlayfieldBackdrop() }
        .clipShape(.rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(palette.laser.opacity(0.6), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme.cyberpunk
    SettingsView(
        theme: $theme,
        motion: MotionMonitor(base: RecordedMotionInput(samples: [])),
        store: SwingSensitivityStore(suiteName: "Preview.Settings")
    )
    .appTheme(theme)
}
