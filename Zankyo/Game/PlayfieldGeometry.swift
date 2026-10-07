import CoreGraphics
import Foundation

/// プレイ画面の譜面の配置。ノーツは上端から判定の線まで一定の速さで降り（タイミングを読みやすくするため、奥行きで速さを変えない）、
/// 奥（上）ほど小さく描く。レーンもノーツの大きさと同じ割合で奥へすぼめ、遠近感を出す
nonisolated struct PlayfieldGeometry: Sendable, Hashable {
    /// 判定の線の高さ（上端からの割合）
    static let hitLineRatio: CGFloat = 0.85
    /// 上端での大きさの倍率（判定の線の上で 1）
    static let farScale: CGFloat = 0.4
    /// 現れてから不透明になるまでの、上端からの進み具合
    static let fadeInProgress: Double = 0.15
    /// 判定の線を過ぎてから消えるまでの秒
    static let fadeOutDelay: TimeInterval = 0.2

    let size: CGSize
    /// ノーツが上端から判定の線に届くまでの秒
    let approachTime: TimeInterval
    /// 判定の線の上での、レーンの幅の半分
    let laneHalfWidth: CGFloat

    init(size: CGSize, approachTime: TimeInterval) {
        self.size = size
        self.approachTime = approachTime
        laneHalfWidth = min(size.width * 0.32, 150)
    }

    var hitY: CGFloat { size.height * Self.hitLineRatio }
    var centerX: CGFloat { size.width / 2 }

    /// レーンがすぼまって 1 点になる高さ（上端より上）
    var vanishingY: CGFloat { -hitY * Self.farScale / (1 - Self.farScale) }

    /// 判定の線に届くまでの残り秒から、ノーツの高さを求める。残り 0 秒で判定の線、`approachTime` 秒で上端
    func y(remaining: TimeInterval) -> CGFloat {
        guard approachTime > 0 else { return hitY }
        return hitY * (1 - CGFloat(remaining / approachTime))
    }

    /// 高さ `y` での大きさの倍率。上端で `farScale`、判定の線で 1 になり、その下も同じ割合で大きくなる
    func scale(atY y: CGFloat) -> CGFloat {
        guard hitY > 0 else { return 1 }
        return max(Self.farScale + (1 - Self.farScale) * y / hitY, 0)
    }

    /// 高さ `y` でのレーンの左右の端
    func laneEdges(atY y: CGFloat) -> (left: CGFloat, right: CGFloat) {
        let half = laneHalfWidth * scale(atY: y)
        return (centerX - half, centerX + half)
    }

    /// 判定の線より手前（下）の薄め方。判定の線から上で 1、下端で 0
    func nearFade(atY y: CGFloat) -> Double {
        let depth = size.height - hitY
        guard y > hitY, depth > 0 else { return 1 }
        return Double(max(1 - (y - hitY) / depth, 0))
    }

    /// 判定の表示（点数など）を判定の線からずらす量。線の上のノーツと重ならないよう線の下に出し、
    /// レーンの下の余白に収まらないときは線の上に出す（レーンは切り取られるので、はみ出すと読めない）
    func judgementLabelOffset(noteSize: CGFloat, labelHeight: CGFloat) -> CGFloat {
        let preferred = noteSize * 0.95
        // 線の上のノーツと重ならない最小のずれと、レーンの下端に収まる最大のずれ
        let clearance = (noteSize + labelHeight) / 2
        let room = size.height - hitY - labelHeight / 2
        return room >= clearance ? min(preferred, room) : -preferred
    }

    /// ノーツの不透明度。上端から現れるところで薄く出し、判定の線を過ぎたら消す
    func noteOpacity(remaining: TimeInterval) -> Double {
        guard approachTime > 0, remaining >= -Self.fadeOutDelay else { return 0 }
        let progress = 1 - remaining / approachTime
        return min(max(progress / Self.fadeInProgress, 0), 1)
    }

    /// 床のグリッドの線を引く曲の時刻。`interval` 秒ごとの線のうち、上端から下端までに見えるもの
    func gridTimes(at currentTime: TimeInterval, interval: TimeInterval) -> [TimeInterval] {
        guard interval > 0, approachTime > 0, hitY > 0, currentTime.isFinite else { return [] }
        // 下端に当たる残り秒（判定の線を過ぎた側なので負）
        let bottomRemaining = -approachTime * Double((size.height - hitY) / hitY)
        let first = ((currentTime + bottomRemaining) / interval).rounded(.up)
        let last = ((currentTime + approachTime) / interval).rounded(.down)
        guard first <= last else { return [] }
        return stride(from: first, through: last, by: 1).map { $0 * interval }
    }
}
