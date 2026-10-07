import SwiftUI

/// 検索結果の行に付ける取り込みボタンと進み具合
struct DownloadControl: View {
    let state: DownloadModel.State
    /// この曲を取得し始められない（別の曲を取得中・取得できる版が無い）
    let isBlocked: Bool
    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        switch state {
        case .notDownloaded:
            Button(action: onStart) {
                Label("取り込む", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
            .disabled(isBlocked)
        case .downloading(let progress):
            HStack(spacing: 8) {
                Group {
                    if let progress {
                        ProgressView(value: progress)
                            .accessibilityValue("\(Int(progress * 100))%")
                    } else {
                        ProgressView()
                    }
                }
                .accessibilityLabel("取り込み中")
                Button(role: .cancel, action: onCancel) {
                    Label("中止", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
            }
        case .downloaded:
            Label("取り込み済み", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
        case .failed(let error):
            VStack(alignment: .leading, spacing: 4) {
                Text(error.message)
                    .font(.caption)
                    .foregroundStyle(.red)
                Button(action: onStart) {
                    Label("もう一度取り込む", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isBlocked)
            }
        }
    }
}
