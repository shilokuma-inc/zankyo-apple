import Foundation
import Testing
@testable import Zankyo

struct FaceNoteConverterTests {
    @Test(arguments: [
        (CutDirection.up, SwingDirection?.some(.up)),
        (.down, .down),
        (.left, .left),
        (.right, .right),
        (.upLeft, .left),
        (.downLeft, .left),
        (.upRight, .right),
        (.downRight, .right),
        (.any, nil)
    ])
    func foldsDirections(cutDirection: CutDirection, expected: SwingDirection?) {
        #expect(FaceNoteConverter.direction(for: cutDirection) == expected)
    }

    @Test
    func ignoresColorAndKeepsTiming() {
        let notes = [
            Self.note(beat: 1, time: 0.5, color: .red, .left),
            Self.note(beat: 2, time: 1, color: .blue, .up)
        ]

        #expect(FaceNoteConverter.convert(notes) == [
            FaceNote(beat: 1, time: 0.5, direction: .left),
            FaceNote(beat: 2, time: 1, direction: .up)
        ])
    }

    @Test
    func mergesSimultaneousNotesWithSameDirection() {
        let notes = [
            Self.note(beat: 4, time: 2, color: .red, .down),
            Self.note(beat: 4, time: 2.01, color: .blue, .down)
        ]

        #expect(FaceNoteConverter.convert(notes) == [FaceNote(beat: 4, time: 2, direction: .down)])
    }

    @Test
    func mergesConflictingSimultaneousNotesIntoAny() {
        // 赤が左・青が右のように頭では同時に振れない組み合わせは、方向不問にする
        let notes = [
            Self.note(beat: 4, time: 2, color: .red, .left),
            Self.note(beat: 4, time: 2, color: .blue, .right)
        ]

        #expect(FaceNoteConverter.convert(notes) == [FaceNote(beat: 4, time: 2, direction: nil)])
    }

    @Test
    func anyDoesNotOverrideSpecifiedDirection() {
        let notes = [
            Self.note(beat: 4, time: 2, color: .red, .any),
            Self.note(beat: 4, time: 2, color: .blue, .upRight)
        ]

        #expect(FaceNoteConverter.convert(notes) == [FaceNote(beat: 4, time: 2, direction: .right)])
    }

    @Test
    func thinsNotesCloserThanMinimumInterval() {
        // 0.25 秒おきのノーツは、0.35 秒の最小間隔で 1 つおきになる
        let notes = (0..<8).map { index in
            Self.note(beat: Double(index), time: Double(index) * 0.25, color: .red, .down)
        }

        #expect(FaceNoteConverter.convert(notes).map(\.time) == [0, 0.5, 1, 1.5])
    }

    @Test
    func prefersNoteOnBeat() {
        // 拍 0.5（裏拍）より、最小間隔の中にある拍 1（拍の頭）を残す
        let notes = [
            Self.note(beat: 0.5, time: 0.25, color: .red, .left),
            Self.note(beat: 1, time: 0.5, color: .blue, .right),
            Self.note(beat: 2, time: 1, color: .red, .up)
        ]

        #expect(FaceNoteConverter.convert(notes) == [
            FaceNote(beat: 1, time: 0.5, direction: .right),
            FaceNote(beat: 2, time: 1, direction: .up)
        ])
    }

    @Test
    func keepsOffBeatNoteWhenNoBeatNoteNearby() {
        let notes = [
            Self.note(beat: 0.5, time: 0.25, color: .red, .left),
            Self.note(beat: 2.5, time: 1.25, color: .blue, .right)
        ]

        #expect(FaceNoteConverter.convert(notes).map(\.beat) == [0.5, 2.5])
    }

    @Test
    func sortsUnorderedInput() {
        let notes = [
            Self.note(beat: 4, time: 2, color: .red, .up),
            Self.note(beat: 2, time: 1, color: .red, .down)
        ]

        #expect(FaceNoteConverter.convert(notes).map(\.direction) == [.down, .up])
    }

    @Test
    func emptyInputGivesNoNotes() {
        #expect(FaceNoteConverter.convert([BeatmapNote]()).isEmpty)
    }

    @Test
    func convertsParsedBeatmap() throws {
        let json = """
        { "version": "3.0.0", "colorNotes": [
          { "b": 1, "x": 0, "y": 0, "c": 0, "d": 4 },
          { "b": 1, "x": 3, "y": 0, "c": 1, "d": 4 },
          { "b": 3, "x": 1, "y": 1, "c": 1, "d": 8 }
        ] }
        """
        let beatmap = try BeatmapParser.parse(Data(json.utf8), bpm: 60)

        #expect(FaceNoteConverter.convert(beatmap) == [
            FaceNote(beat: 1, time: 1, direction: .left),
            FaceNote(beat: 3, time: 3, direction: nil)
        ])
    }

    private static func note(beat: Double, time: TimeInterval, color: NoteColor, _ direction: CutDirection) -> BeatmapNote {
        BeatmapNote(beat: beat, time: time, lineIndex: 0, lineLayer: 0, color: color, cutDirection: direction)
    }
}
