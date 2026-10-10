import SwiftUI

/// 判定の線の上の、ノーツと同じ形のターゲット枠。降りてきたノーツがこの枠にぴったり収まった瞬間がヒットのタイミング
///
/// 近づくノーツごとに、そのノーツの色の枠を外から縮め、ぴったりの瞬間にターゲット枠と重ねる（線の上の位置を読まなくても、
/// 枠が重なる瞬間でタイミングが分かる）。ぴったりの瞬間を過ぎたら、ターゲット枠を一瞬光らせる。ノーツより奥に描く
struct HitTarget: View {
    /// まだ判定していないノーツ
    struct Note {
        /// 譜面の中の位置（同じ時刻のノーツがあっても重ならない ID）
        let index: Int
        /// 判定の線に届くまでの残り秒
        let remaining: TimeInterval
        let direction: SwingDirection?
    }

    let notes: [Note]
    /// 直前に判定したノーツの、判定の線に届くまでの残り秒。判定したノーツは `notes` から外れるので、
    /// ぴったりの瞬間の前後に切ったときもターゲット枠を光らせるために別に受け取る。無ければ nil
    var judgedRemaining: TimeInterval?
    /// 判定の線の上でのノーツの大きさ
    let noteSize: CGFloat

    @Environment(\.palette) private var palette

    var body: some View {
        let size = noteSize * PlayfieldGeometry.targetScale
        let remainings = notes.map(\.remaining) + [judgedRemaining].compactMap { $0 }
        let flash = remainings.map(PlayfieldGeometry.targetFlash(remaining:)).max() ?? 0
        ZStack {
            ForEach(notes, id: \.index) { note in
                if let scale = PlayfieldGeometry.cueScale(remaining: note.remaining) {
                    let color = palette.noteColor(for: note.direction).color
                    Self.frame(size: size * scale)
                        .stroke(color, lineWidth: 3)
                        .frame(width: size * scale, height: size * scale)
                        .shadow(color: palette.glow(color), radius: 6)
                        .opacity(PlayfieldGeometry.cueOpacity(remaining: note.remaining))
                }
            }
            Self.frame(size: size)
                .fill(palette.laser.opacity(0.08 + 0.3 * flash))
                .frame(width: size, height: size)
            Self.frame(size: size)
                .stroke(palette.ink.opacity(0.45 + 0.55 * flash), lineWidth: 2 + 2 * flash)
                .frame(width: size, height: size)
                .shadow(color: palette.glow(palette.laser, 0.6 + 0.4 * flash), radius: 4 + 10 * flash)
        }
    }

    /// ノーツ（`NoteBlock`）と同じ角の丸めの枠
    private static func frame(size: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
    }
}

#Preview {
    HitTarget(
        notes: [
            HitTarget.Note(index: 0, remaining: 0.15, direction: .left),
            HitTarget.Note(index: 1, remaining: 0.45, direction: .up)
        ],
        noteSize: 64
    )
    .padding(80)
    .background(ThemePalette.zankyo.spaceBottom)
}
