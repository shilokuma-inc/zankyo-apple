import SwiftUI

/// 設定の「効果音」。ノーツを切ったときの音と音量を選ぶ。音を選んだとき・音量を変え終えたときに、試しに鳴らす
struct HitSoundSettingsSection: View {
    var store = HitSoundStore()

    @State private var settings = HitSoundSettings()
    /// 試し聞きの音。鳴り終わる前に捨てられないよう持っておく
    @State private var preview: EngineHitSoundPlayer?

    var body: some View {
        Section {
            ForEach(HitSound.allCases) { sound in
                HitSoundRow(sound: sound, isSelected: sound == settings.sound) {
                    settings.sound = sound
                    save()
                    playPreview()
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("音量")
                    Spacer()
                    Text(settings.isAudible ? settings.volume.formatted(.percent.precision(.fractionLength(0))) : "鳴らさない")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.volume, in: 0...1, step: 0.05) {
                    Text("音量")
                } minimumValueLabel: {
                    Image(systemName: "speaker.slash.fill")
                        .accessibilityLabel("鳴らさない")
                } maximumValueLabel: {
                    Image(systemName: "speaker.wave.3.fill")
                        .accessibilityLabel("最大")
                } onEditingChanged: { isEditing in
                    guard !isEditing else { return }
                    save()
                    playPreview()
                }
                .accessibilityValue(settings.isAudible ? settings.volume.formatted(.percent.precision(.fractionLength(0))) : "鳴らさない")
            }
        } header: {
            Text("効果音")
        } footer: {
            Text("ノーツを切ったときに鳴らします。音量を 0% にすると鳴らしません。")
        }
        .onAppear {
            settings = store.settings
        }
        .onDisappear {
            preview?.stop()
            preview = nil
        }
    }

    private func save() {
        store.save(settings)
    }

    private func playPreview() {
        preview?.stop()
        guard settings.isAudible else {
            preview = nil
            return
        }
        let player = EngineHitSoundPlayer(settings: settings, managesAudioSession: true)
        player.play()
        preview = player
    }
}

/// 効果音の 1 行。名前と説明を並べ、選んでいるものに印を付ける
private struct HitSoundRow: View {
    let sound: HitSound
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: "speaker.wave.2")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sound.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(sound.summary)
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
        .accessibilityHint("選ぶと試しに鳴らします")
    }
}

#Preview {
    Form {
        HitSoundSettingsSection(store: HitSoundStore(suiteName: "Preview.HitSound"))
    }
}
