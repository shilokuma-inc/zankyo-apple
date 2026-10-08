import SwiftUI

/// 背景の光の演出（Beat Saber の照明にならう）。レーンを囲むリング・左右から振るレーザー・判定の線のまわりの中央の光を、
/// 光の状態（`LightState`）に合わせて描く。奥の光は画面全体の背景（`PlayfieldBackdrop`）が描く
///
/// レーンより奥に描き、リングとレーザーはノーツの通り道を避けるので、ノーツは暗いレーンの上で読める。
/// にじみを使わないテーマ（`glowIntensity` が 0）でも、線と色だけで光って見えるようにする
struct PlayfieldLights: View {
    let geometry: PlayfieldGeometry
    let state: LightState

    /// リングの奥行き（レーンの上端からの進み具合。奥から手前の順）
    static let ringDepths: [Double] = [0.08, 0.26, 0.44, 0.62]
    /// 左右それぞれのレーザーの本数
    static let lasersPerSide = 4

    @Environment(\.palette) private var palette

    var body: some View {
        Canvas { [palette, state] context, size in
            Self.drawCenter(&context, geometry: geometry, light: state.center, palette: palette)
            // ノーツの通り道（レーンの少し外まで）には、リングとレーザーを描かない
            var outside = Path(CGRect(origin: .zero, size: size))
            outside.addPath(Self.lane(geometry: geometry, widening: 1.15))
            context.clip(to: outside, style: FillStyle(eoFill: true))
            Self.drawRings(&context, geometry: geometry, light: state.rings, rotation: state.ringRotation, palette: palette)
            Self.drawLasers(&context, size: size, state: state, isLeft: true, palette: palette)
            Self.drawLasers(&context, size: size, state: state, isLeft: false, palette: palette)
        }
    }

    /// 照明の色をテーマの色に当てる。赤は左のノーツ、青は右のノーツの色。白は暗い空間なら白、明るい空間ならレーザーの色
    static func color(of light: LightState.Light, palette: ThemePalette) -> Color {
        switch light.color {
        case .left: palette.left.color
        case .right: palette.right.color
        case .white: palette.colorScheme == .dark ? .white : palette.laser
        }
    }

    /// レーンを囲む八角形のリング。奥ほど小さく細く、回すと傾く
    private static func drawRings(
        _ context: inout GraphicsContext,
        geometry: PlayfieldGeometry,
        light: LightState.Light,
        rotation: Double,
        palette: ThemePalette
    ) {
        let intensity = min(light.intensity, 1.4)
        guard intensity > 0.01 else { return }
        let color = color(of: light, palette: palette)
        for (index, depth) in ringDepths.enumerated() {
            let y = geometry.y(remaining: geometry.approachTime * (1 - depth))
            let scale = geometry.scale(atY: y)
            let radius = geometry.laneHalfWidth * scale * 1.9
            let ring = octagon(center: CGPoint(x: geometry.centerX, y: y), radius: radius, rotation: rotation + Double(index) * 0.12)
            let opacity = 0.6 * intensity * Double(0.4 + 0.6 * scale)
            if palette.glowIntensity > 0 {
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 6))
                    layer.stroke(ring, with: .color(color.opacity(opacity * palette.glowIntensity)), lineWidth: 6 * scale)
                }
            }
            context.stroke(ring, with: .color(color.opacity(opacity)), lineWidth: max(2 * scale, 1))
        }
    }

    /// 左右の上の角から、床へ向けて扇のように振るレーザー
    private static func drawLasers(
        _ context: inout GraphicsContext,
        size: CGSize,
        state: LightState,
        isLeft: Bool,
        palette: ThemePalette
    ) {
        let light = isLeft ? state.leftLasers : state.rightLasers
        let phase = isLeft ? state.leftLaserPhase : state.rightLaserPhase
        let intensity = min(light.intensity, 1.4)
        guard intensity > 0.01 else { return }
        let color = color(of: light, palette: palette)
        let length = max(size.width, size.height) * 1.6
        var beams = Path()
        for index in 0..<lasersPerSide {
            let origin = CGPoint(x: isLeft ? 0 : size.width, y: size.height * (0.04 + 0.09 * Double(index)))
            // 水平から下へ傾け、位相に合わせて振る（左右で向きを鏡にする）
            let angle = 0.5 + 0.18 * Double(index) + 0.3 * sin(phase + Double(index) * 0.8)
            let direction = CGVector(dx: cos(angle) * (isLeft ? 1 : -1), dy: sin(angle))
            beams.move(to: origin)
            beams.addLine(to: CGPoint(x: origin.x + direction.dx * length, y: origin.y + direction.dy * length))
        }
        let opacity = 0.75 * intensity
        if palette.glowIntensity > 0 {
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 7))
                layer.stroke(beams, with: .color(color.opacity(opacity * palette.glowIntensity)), lineWidth: 9)
            }
        }
        context.stroke(beams, with: .color(color.opacity(opacity)), lineWidth: 2.5)
        if palette.colorScheme == .dark {
            context.stroke(beams, with: .color(.white.opacity(0.5 * opacity)), lineWidth: 0.8)
        }
    }

    /// 中央の光。判定の線のまわりの床を照らす
    private static func drawCenter(
        _ context: inout GraphicsContext,
        geometry: PlayfieldGeometry,
        light: LightState.Light,
        palette: ThemePalette
    ) {
        let intensity = min(light.intensity, 1.4)
        guard intensity > 0.01 else { return }
        let color = color(of: light, palette: palette)
        let radius = geometry.laneHalfWidth * 2.2
        // 円のグラデーションを縦につぶして、縁まで滑らかに消える楕円にする。下はレーンの枠（下端）に収める
        let squash = min(0.45, max(geometry.size.height - geometry.hitY, 1) / radius)
        context.drawLayer { layer in
            layer.translateBy(x: geometry.centerX, y: geometry.hitY)
            layer.scaleBy(x: 1, y: squash)
            layer.fill(
                Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)),
                with: .radialGradient(
                    Gradient(colors: [color.opacity(0.4 * intensity), color.opacity(0)]),
                    center: .zero,
                    startRadius: 0,
                    endRadius: radius
                )
            )
        }
    }

    /// レーンの台形を `widening` 倍に広げたもの（上端から下端まで）
    private static func lane(geometry: PlayfieldGeometry, widening: CGFloat) -> Path {
        let height = geometry.size.height
        let top = geometry.laneHalfWidth * geometry.scale(atY: 0) * widening
        let bottom = geometry.laneHalfWidth * geometry.scale(atY: height) * widening
        var path = Path()
        path.move(to: CGPoint(x: geometry.centerX - top, y: 0))
        path.addLine(to: CGPoint(x: geometry.centerX + top, y: 0))
        path.addLine(to: CGPoint(x: geometry.centerX + bottom, y: height))
        path.addLine(to: CGPoint(x: geometry.centerX - bottom, y: height))
        path.closeSubpath()
        return path
    }

    private static func octagon(center: CGPoint, radius: CGFloat, rotation: Double) -> Path {
        var path = Path()
        for corner in 0..<8 {
            let angle = rotation + Double(corner) * .pi / 4 + .pi / 8
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if corner == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}
