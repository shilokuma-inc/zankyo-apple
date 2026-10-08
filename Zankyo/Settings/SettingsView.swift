import SwiftUI

/// 設定の画面。いまはテーマの選択だけを置く。選ぶとすぐにアプリ全体へ反映し、上の見本でプレイ画面の見た目を確かめられる
struct SettingsView: View {
    @Binding var theme: AppTheme

    var body: some View {
        NavigationStack {
            Form {
                Section("プレイ画面の見本") {
                    ThemePreview()
                        .frame(height: 220)
                        .listRowInsets(EdgeInsets())
                }
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

/// 選んでいるテーマのプレイ画面の見本。プレイ画面と同じ部品で、レーン・4 つの向きのノーツ・スコアを止めた状態で描く
private struct ThemePreview: View {
    /// 見本のノーツ（判定の線に届くまでの秒と向き）
    private static let notes: [(remaining: TimeInterval, direction: SwingDirection?)] = [
        (0.15, .left), (0.4, .right), (0.65, .up), (0.9, nil)
    ]

    var body: some View {
        GeometryReader { proxy in
            let geometry = PlayfieldGeometry(size: proxy.size, approachTime: 1)
            ZStack {
                PlayfieldLane(geometry: geometry)
                PlayfieldGrid(geometry: geometry, currentTime: 0)
                ForEach(Self.notes.indices, id: \.self) { index in
                    let note = Self.notes[index]
                    let y = geometry.y(remaining: note.remaining)
                    NoteBlock(direction: note.direction, size: 40 * geometry.scale(atY: y))
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
        .background { PlayfieldBackdrop() }
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
    SettingsView(theme: $theme)
        .appTheme(theme)
}
