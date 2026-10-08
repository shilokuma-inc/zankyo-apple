import Foundation

/// 遊び方（ノーツの切り方）。設定で選び、検出（`SwingDetection`）と判定に使う。
/// 選んだ遊び方は `rawValue` で保存するので、case の名前を変えない
nonisolated enum PlayStyle: String, CaseIterable, Identifiable, Sendable {
    /// 向きを問わず、ノーツに合わせて頭を振れば切れる（ヘドバン）。既定
    case headbang
    /// ノーツの矢印の向き（上下左右）に首を振って切る。違う向きに振るとミス
    case directional

    var id: Self { self }

    var title: String {
        switch self {
        case .headbang: "ヘドバン"
        case .directional: "向きを合わせて切る"
        }
    }

    var summary: String {
        switch self {
        case .headbang: "向きは問わず、ノーツに合わせて頭を振る"
        case .directional: "矢印の向き（上下左右）に首を振る。違う向きはミス"
        }
    }

    /// ノーツの向きを判定に使う
    var usesDirection: Bool {
        self == .directional
    }
}
