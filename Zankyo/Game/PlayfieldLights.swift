import SwiftUI

/// 背景の光の演出。譜面の照明（リング・左右のレーザー・中央の光）を、光の輪やにじみではなく刃の形の線（`blade`）で描く。
/// 光の状態（`LightState`）に合わせて線の濃さ・傾き・振りを変える。奥の光は画面全体の背景（`PlayfieldBackdrop`）が描く
///
/// レーンより奥に描き、リングとレーザーの線はノーツの通り道を避けるので、ノーツはレーンの上で読める。
/// どのテーマでもにじませず（ぼかしを使わない）、線と色だけで見せる
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
            // ノーツの通り道（レーンの少し外まで）には、線を描かない（中央の光の線も、判定の線と見まちがえないよう左右だけに出す）
            var outside = Path(CGRect(origin: .zero, size: size))
            outside.addPath(Self.lane(geometry: geometry, widening: 1.15))
            context.clip(to: outside, style: FillStyle(eoFill: true))
            Self.drawCenter(&context, geometry: geometry, light: state.center, palette: palette)
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

    /// リングの代わりに、レーンの左右へ横に払う刃の線。奥ほど短く細く、回すと傾く
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
            let inner = geometry.laneHalfWidth * scale * 1.25
            let outer = geometry.laneHalfWidth * scale * 2.6
            let tilt = (outer - inner) * 0.35 * sin(rotation + Double(index) * 0.12)
            let opacity = 0.6 * intensity * Double(0.4 + 0.6 * scale)
            for sign in [-1.0, 1.0] {
                let blade = blade(
                    from: CGPoint(x: geometry.centerX + sign * inner, y: y),
                    to: CGPoint(x: geometry.centerX + sign * outer, y: y - sign * tilt),
                    width: max(3 * scale, 1.5)
                )
                context.fill(blade, with: .color(color.opacity(opacity)))
            }
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
            let end = CGPoint(x: origin.x + direction.dx * length, y: origin.y + direction.dy * length)
            beams.addPath(blade(from: origin, to: end, width: 4))
        }
        context.fill(beams, with: .color(color.opacity(0.75 * intensity)))
    }

    /// 中央の光。判定の線のまわりに線を添える
    private static func drawCenter(
        _ context: inout GraphicsContext,
        geometry: PlayfieldGeometry,
        light: LightState.Light,
        palette: ThemePalette
    ) {
        let intensity = min(light.intensity, 1.4)
        guard intensity > 0.01 else { return }
        let color = color(of: light, palette: palette)
        // 判定の線の少し上と下に、レーンの外まで届く刃の線を 1 本ずつ引く（レーンの中は描かない）
        let half = geometry.laneHalfWidth * 2.4
        let opacity = 0.45 * intensity
        for offset in [-10.0, 10.0] {
            let y = geometry.hitY + offset
            let blade = blade(from: CGPoint(x: geometry.centerX - half, y: y), to: CGPoint(x: geometry.centerX + half, y: y), width: 2)
            context.fill(blade, with: .color(color.opacity(opacity)))
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

    /// 刃の形の線。両端で細く尖り、`start` から 4 割のところで最も太い（`width`）。にじみを使わず、払った筆や刃の跡に見せる
    static func blade(from start: CGPoint, to end: CGPoint, width: CGFloat) -> Path {
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length > 0 else { return Path() }
        let normal = CGVector(dx: -(end.y - start.y) / length * width / 2, dy: (end.x - start.x) / length * width / 2)
        let widest = CGPoint(x: start.x + (end.x - start.x) * 0.4, y: start.y + (end.y - start.y) * 0.4)
        var path = Path()
        path.move(to: start)
        path.addLine(to: CGPoint(x: widest.x + normal.dx, y: widest.y + normal.dy))
        path.addLine(to: end)
        path.addLine(to: CGPoint(x: widest.x - normal.dx, y: widest.y - normal.dy))
        path.closeSubpath()
        return path
    }
}
