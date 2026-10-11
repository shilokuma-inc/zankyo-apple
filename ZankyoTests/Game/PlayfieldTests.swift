import CoreGraphics
import Foundation
import Testing
@testable import Zankyo

struct PlayfieldGeometryTests {
    /// 判定の線は高さ 510、その下に 90 の余白
    private let geometry = PlayfieldGeometry(size: CGSize(width: 400, height: 600), approachTime: 1.5)

    @Test
    func noteReachesHitLineWhenRemainingIsZero() {
        #expect(geometry.hitY == 510)
        #expect(geometry.y(remaining: 0) == geometry.hitY)
        #expect(geometry.y(remaining: 1.5) == 0)
        #expect(geometry.y(remaining: 0.75) == 255)
    }

    @Test
    func notesFallAtConstantSpeed() {
        // 奥行きで速さを変えない（同じ秒数で同じだけ降りる）
        let far = geometry.y(remaining: 1.2) - geometry.y(remaining: 1.5)
        let near = geometry.y(remaining: 0) - geometry.y(remaining: 0.3)
        #expect(isClose(far, near))
    }

    @Test
    func scaleGrowsTowardHitLine() {
        #expect(geometry.scale(atY: 0) == PlayfieldGeometry.farScale)
        #expect(geometry.scale(atY: geometry.hitY) == 1)
        #expect(geometry.scale(atY: geometry.size.height) > 1)
        #expect(isClose(geometry.scale(atY: geometry.vanishingY), 0))
    }

    @Test
    func laneNarrowsToVanishingPoint() {
        let near = geometry.laneEdges(atY: geometry.hitY)
        let far = geometry.laneEdges(atY: 0)
        let vanishing = geometry.laneEdges(atY: geometry.vanishingY)

        #expect(isClose(near.right - near.left, geometry.laneHalfWidth * 2))
        #expect(isClose(far.right - far.left, geometry.laneHalfWidth * 2 * PlayfieldGeometry.farScale))
        #expect(isClose(vanishing.right - vanishing.left, 0))
        #expect(geometry.vanishingY < 0)
    }

    @Test
    func laneWidthIsCappedOnWideScreens() {
        let wide = PlayfieldGeometry(size: CGSize(width: 1200, height: 800), approachTime: 1.5)

        #expect(wide.laneHalfWidth == 150)
        #expect(isClose(geometry.laneHalfWidth, 128))
    }

    @Test
    func noteFadesInAtTopAndOutAfterHitLine() {
        #expect(geometry.noteOpacity(remaining: 1.5) == 0)
        #expect(isClose(geometry.noteOpacity(remaining: 1.5 - 1.5 * PlayfieldGeometry.fadeInProgress / 2), 0.5))
        #expect(geometry.noteOpacity(remaining: 1.0) == 1)
        #expect(geometry.noteOpacity(remaining: -0.1) == 1)
        #expect(geometry.noteOpacity(remaining: -0.3) == 0)
    }

    @Test
    func nearFadeFadesOutBelowHitLine() {
        #expect(geometry.nearFade(atY: 0) == 1)
        #expect(geometry.nearFade(atY: geometry.hitY) == 1)
        #expect(geometry.nearFade(atY: 555) == 0.5)
        #expect(geometry.nearFade(atY: 600) == 0)
    }

    @Test
    func judgementLabelStaysInsideLane() {
        // 下の余白（90）に収まるので、決めた分だけ線の下に出す
        #expect(isClose(geometry.judgementLabelOffset(noteSize: 64, labelHeight: 36), 64 * 0.95))
        // 下の余白（72）が少ないので、下端に収まるところまで縮める
        let short = PlayfieldGeometry(size: CGSize(width: 400, height: 480), approachTime: 1.5)
        #expect(isClose(short.judgementLabelOffset(noteSize: 64, labelHeight: 36), 72 - 18))
        // 下の余白（60）ではノーツと重なるので、線の上に出す
        let shorter = PlayfieldGeometry(size: CGSize(width: 400, height: 400), approachTime: 1.5)
        #expect(isClose(shorter.judgementLabelOffset(noteSize: 64, labelHeight: 36), -64 * 0.95))
    }

    @Test
    func gridTimesCoverVisibleRange() {
        let times = geometry.gridTimes(at: 10.1, interval: 0.25)

        // 下端は判定の線から 0.2647 秒過ぎた所、上端は 1.5 秒先
        #expect(times == stride(from: 10.0, through: 11.5, by: 0.25).map(\.self))
        for time in times {
            let y = geometry.y(remaining: time - 10.1)
            #expect((0...geometry.size.height).contains(y))
        }
    }

    @Test
    func cueShrinksOntoTargetAtHitTime() {
        let lead = PlayfieldGeometry.cueLeadTime

        #expect(PlayfieldGeometry.cueScale(remaining: lead) == PlayfieldGeometry.cueStartScale)
        #expect(isClose(PlayfieldGeometry.cueScale(remaining: lead / 2) ?? 0, (1 + PlayfieldGeometry.cueStartScale) / 2))
        // ぴったりの瞬間の直前でターゲット枠と同じ大きさになり、その後は出さない
        #expect(isClose(PlayfieldGeometry.cueScale(remaining: 1e-9) ?? 0, 1))
        #expect(PlayfieldGeometry.cueScale(remaining: 0) == nil)
        #expect(PlayfieldGeometry.cueScale(remaining: -0.1) == nil)
        #expect(PlayfieldGeometry.cueScale(remaining: lead + 0.1) == nil)
    }

    @Test
    func cueFadesInUntilHalfway() {
        let lead = PlayfieldGeometry.cueLeadTime

        #expect(PlayfieldGeometry.cueOpacity(remaining: lead) == 0)
        #expect(isClose(PlayfieldGeometry.cueOpacity(remaining: lead * 0.75), 0.5))
        #expect(PlayfieldGeometry.cueOpacity(remaining: lead / 2) == 1)
        #expect(PlayfieldGeometry.cueOpacity(remaining: 0.01) == 1)
        #expect(PlayfieldGeometry.cueOpacity(remaining: 0) == 0)
    }

    @Test
    func targetFlashesRightAfterHitTime() {
        let duration = PlayfieldGeometry.flashDuration

        #expect(PlayfieldGeometry.targetFlash(remaining: 0.01) == 0)
        #expect(PlayfieldGeometry.targetFlash(remaining: 0) == 1)
        #expect(isClose(PlayfieldGeometry.targetFlash(remaining: -duration / 2), 0.5))
        #expect(PlayfieldGeometry.targetFlash(remaining: -duration) == 0)
    }

    private func isClose(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) < 0.0001
    }

    @Test
    func gridTimesIgnoreInvalidValues() {
        #expect(geometry.gridTimes(at: .nan, interval: 0.25).isEmpty)
        #expect(geometry.gridTimes(at: 1, interval: 0).isEmpty)
        #expect(PlayfieldGeometry(size: .zero, approachTime: 1.5).gridTimes(at: 1, interval: 0.25).isEmpty)
    }
}

struct PlayfieldBladeTests {
    @Test
    func bladeSpansFromStartToEndWithItsWidth() {
        // 横に引いた刃の線は、始点から終点まで届き、太さは width に収まる
        let blade = PlayfieldLights.blade(from: CGPoint(x: 10, y: 50), to: CGPoint(x: 110, y: 50), width: 4)
        let bounds = blade.boundingRect
        #expect(bounds.minX == 10)
        #expect(bounds.maxX == 110)
        #expect(bounds.height == 4)
        // 両端は尖る（端の点では線の外に面を持たない）
        #expect(!blade.contains(CGPoint(x: 10.5, y: 51.9)))
        #expect(blade.contains(CGPoint(x: 50, y: 51.5)))
    }

    @Test
    func bladeOfZeroLengthIsEmpty() {
        #expect(PlayfieldLights.blade(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 5, y: 5), width: 4).isEmpty)
    }
}
