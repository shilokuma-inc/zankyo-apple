import SwiftUI
import Testing
@testable import Zankyo

struct ResultMarksTests {
    private static let rect = CGRect(x: 0, y: 0, width: 40, height: 40)

    @Test
    func marksStayInsideTheirFrame() {
        // バッジやアドバイスの文字の横に並べるので、はみ出すと隣の文字に重なる
        let paths = [EnsoMark().path(in: Self.rect), SealMark().path(in: Self.rect), InkDropMark().path(in: Self.rect)]
        for path in paths {
            #expect(!path.isEmpty)
            #expect(Self.rect.insetBy(dx: -0.5, dy: -0.5).contains(path.boundingRect))
        }
    }

    @Test
    func ensoLeavesAGap() {
        // 円相は一周を閉じない（閉じると定番の丸と見分けがつかない）。輪の上の点を一周たどり、描いている割合を見る
        let path = EnsoMark().path(in: Self.rect)
        let radius = Self.rect.width / 2 - Self.rect.width * 0.1
        let samples = 72
        let covered = (0..<samples).filter { index in
            let angle = Double(index) / Double(samples) * 2 * .pi
            return path.contains(CGPoint(x: Self.rect.midX + radius * cos(angle), y: Self.rect.midY + radius * sin(angle)))
        }
        let ratio = Double(covered.count) / Double(samples)
        #expect(ratio > 0.75)
        #expect(ratio < 0.95)
        #expect(!path.contains(CGPoint(x: Self.rect.midX, y: Self.rect.midY)))
    }
}
