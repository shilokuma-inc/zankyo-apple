import SwiftUI

/// プレイ画面の奥の空間。空の色を上から下へ敷き、画面の端まで広げる。地平を光で照らすことはしない
///
/// 背景の光の演出の「奥の光」（`back`）があれば、レーンの奥（上）に地平の線を 1 本、刃の形で引く
/// （にじませず、線の濃さだけで光の強さを見せる。レーンの枠で切れないよう、画面全体の背景に描く）
struct PlayfieldBackdrop: View {
    var back: LightState.Light?

    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            LinearGradient(colors: [palette.spaceTop, palette.spaceBottom], startPoint: .top, endPoint: .bottom)
            if let back, back.intensity > 0.01 {
                let color = PlayfieldLights.color(of: back, palette: palette)
                Canvas { context, size in
                    let y = size.height * 0.15
                    let blade = PlayfieldLights.blade(
                        from: CGPoint(x: size.width * 0.04, y: y),
                        to: CGPoint(x: size.width * 0.96, y: y),
                        width: 3
                    )
                    context.fill(blade, with: .color(color.opacity(0.6 * min(back.intensity, 1.4) / 1.4)))
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// 背景の光の演出に合わせて照らす `PlayfieldBackdrop`。曲の時刻が変わるたびに、ここだけを描き直す
struct LitPlayfieldBackdrop: View {
    let lights: LightShow?
    let session: GameSession

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PlayfieldBackdrop(back: lights.map { reduceMotion ? LightState.calm.back : $0.state(at: session.currentTime).back })
    }
}

/// 奥へすぼまるレーン。左右の縁は Beat Saber の左右のセイバーにならって左右のノーツの色で光らせ、判定の線はレーザーにする。
/// 上端と下端は背景に溶かし、判定の線のあたりを最も明るくする。
/// 曲の時刻では変わらないので、フレームごとに描き直す床のグリッド（`PlayfieldGrid`）と分けている
struct PlayfieldLane: View {
    let geometry: PlayfieldGeometry

    @Environment(\.palette) private var palette

    var body: some View {
        Canvas { [palette] context, _ in
            Self.drawFloor(&context, geometry: geometry, palette: palette)
            Self.drawLane(&context, geometry: geometry, palette: palette)
            Self.drawRails(&context, geometry: geometry, palette: palette)
            Self.drawHitLine(&context, geometry: geometry, palette: palette)
        }
    }

    /// レーンの外の床。レーンと同じ消失点へ向かう線を薄く引く
    private static func drawFloor(_ context: inout GraphicsContext, geometry: PlayfieldGeometry, palette: ThemePalette) {
        let height = geometry.size.height
        let vanishing = CGPoint(x: geometry.centerX, y: geometry.vanishingY)
        let bottomHalf = geometry.laneHalfWidth * geometry.scale(atY: height)
        var path = Path()
        for ratio in [1.7, 2.6, 3.8, 5.5, 8.0] {
            for sign in [-1.0, 1.0] {
                path.move(to: vanishing)
                path.addLine(to: CGPoint(x: geometry.centerX + sign * ratio * bottomHalf, y: height))
            }
        }
        context.stroke(path, with: glow(palette.horizon, peak: 0.35, height: height), lineWidth: 1)
    }

    /// レーンの床と、ノーツの通り道を示す 2 本のガイド
    private static func drawLane(_ context: inout GraphicsContext, geometry: PlayfieldGeometry, palette: ThemePalette) {
        let height = geometry.size.height
        context.fill(trapezoid(geometry: geometry), with: glow(palette.spaceBottom, peak: 0.85, height: height))
        var guides = Path()
        for ratio in [-0.5, 0.5] {
            let top = geometry.laneHalfWidth * geometry.scale(atY: 0) * ratio
            let bottom = geometry.laneHalfWidth * geometry.scale(atY: height) * ratio
            guides.move(to: CGPoint(x: geometry.centerX + top, y: 0))
            guides.addLine(to: CGPoint(x: geometry.centerX + bottom, y: height))
        }
        context.stroke(guides, with: glow(palette.laser, peak: 0.25, height: height), lineWidth: 1)
    }

    /// 左右の縁
    private static func drawRails(_ context: inout GraphicsContext, geometry: PlayfieldGeometry, palette: ThemePalette) {
        let height = geometry.size.height
        let top = geometry.laneEdges(atY: 0)
        let bottom = geometry.laneEdges(atY: height)
        let rails = [
            (line(from: CGPoint(x: top.left, y: 0), to: CGPoint(x: bottom.left, y: height)), palette.left.color),
            (line(from: CGPoint(x: top.right, y: 0), to: CGPoint(x: bottom.right, y: height)), palette.right.color)
        ]
        for (path, color) in rails {
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 6))
                layer.stroke(path, with: glow(color, peak: palette.glowIntensity, height: height), lineWidth: 6)
            }
            context.stroke(path, with: glow(color, peak: 1, height: height), lineWidth: 2)
        }
    }

    /// 判定の線。芯のまわりをレーザーの色で光らせ、両端に印を付ける
    private static func drawHitLine(_ context: inout GraphicsContext, geometry: PlayfieldGeometry, palette: ThemePalette) {
        let y = geometry.hitY
        let edges = geometry.laneEdges(atY: y)
        let beam = line(from: CGPoint(x: edges.left, y: y), to: CGPoint(x: edges.right, y: y))
        var caps = Path()
        for x in [edges.left, edges.right] {
            caps.addRoundedRect(in: CGRect(x: x - 2, y: y - 10, width: 4, height: 20), cornerSize: CGSize(width: 2, height: 2))
        }
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 8))
            layer.stroke(beam, with: .color(palette.glow(palette.laser)), lineWidth: 10)
            layer.fill(caps, with: .color(palette.glow(palette.laser)))
        }
        context.stroke(beam, with: .color(palette.laser), lineWidth: 3)
        context.stroke(beam, with: .color(palette.core), lineWidth: 1)
        context.fill(caps, with: .color(palette.core))
    }

    /// レーンの台形（上端から下端まで）
    private static func trapezoid(geometry: PlayfieldGeometry) -> Path {
        let top = geometry.laneEdges(atY: 0)
        let bottom = geometry.laneEdges(atY: geometry.size.height)
        var path = Path()
        path.move(to: CGPoint(x: top.left, y: 0))
        path.addLine(to: CGPoint(x: top.right, y: 0))
        path.addLine(to: CGPoint(x: bottom.right, y: geometry.size.height))
        path.addLine(to: CGPoint(x: bottom.left, y: geometry.size.height))
        path.closeSubpath()
        return path
    }

    private static func line(from start: CGPoint, to end: CGPoint) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        return path
    }

    /// 上端と下端で透明になり、判定の線の高さで不透明度 `peak` になる色
    private static func glow(_ color: Color, peak: Double, height: CGFloat) -> GraphicsContext.Shading {
        .linearGradient(
            Gradient(stops: [
                .init(color: color.opacity(0), location: 0),
                .init(color: color.opacity(peak), location: Double(PlayfieldGeometry.hitLineRatio)),
                .init(color: color.opacity(0), location: 1)
            ]),
            startPoint: .zero,
            endPoint: CGPoint(x: 0, y: height)
        )
    }
}

/// レーンの床のグリッド。ノーツと同じ速さで手前へ流し、1 秒ごとの線を明るくする。曲を止めるとグリッドも止まる
struct PlayfieldGrid: View {
    let geometry: PlayfieldGeometry
    /// 曲の時刻
    let currentTime: TimeInterval

    /// 線の間隔（秒）
    static let interval: TimeInterval = 0.25
    /// 明るい線の間隔（線の本数）
    private static let majorEvery = 4

    @Environment(\.palette) private var palette

    var body: some View {
        Canvas { [palette] context, _ in
            for time in geometry.gridTimes(at: currentTime, interval: Self.interval) {
                let y = geometry.y(remaining: time - currentTime)
                let edges = geometry.laneEdges(atY: y)
                var path = Path()
                path.move(to: CGPoint(x: edges.left, y: y))
                path.addLine(to: CGPoint(x: edges.right, y: y))
                // 奥ほど細く薄くし、判定の線より手前は下端へ向けて消す
                let depth = min(geometry.scale(atY: y), 1)
                let isMajor = Int((time / Self.interval).rounded()).isMultiple(of: Self.majorEvery)
                let opacity = (isMajor ? 0.55 : 0.22) * Double(depth * depth) * geometry.nearFade(atY: y)
                context.stroke(path, with: .color(palette.laser.opacity(opacity)), lineWidth: (isMajor ? 1.5 : 1) * depth)
            }
        }
    }
}
