import Foundation

/// 1 ノーツの判定
nonisolated enum Judgement: Sendable, Hashable {
    /// 正しい向きで切った
    case hit(FaceNote, CutScore, timingError: TimeInterval)
    /// 時間窓の中で違う向きに振った（Beat Saber のバッドカットに当たる。ミスと同じ扱い）
    case badCut(FaceNote, SwingDirection)
    /// 切らずに時間窓を過ぎた
    case miss(FaceNote)

    var note: FaceNote {
        switch self {
        case .hit(let note, _, _), .badCut(let note, _), .miss(let note):
            note
        }
    }
}

/// 顔のノーツと「切る」動きを照合し、スコアを数える。時刻はすべて曲の先頭からの秒で受け取る
///
/// 振りの時刻は、キャリブレーションで測った `offset`（動きが音より遅れる秒）を引いてから照合する
nonisolated struct Judge: Sendable {
    let rules: ScoringRules
    /// 動きが音より遅れる秒（キャリブレーションの値）。振りの時刻から引く
    let offset: TimeInterval
    private(set) var keeper = ScoreKeeper()
    private(set) var judgements: [Judgement] = []
    private let notes: [FaceNote]
    /// まだ判定していない最初のノーツ
    private var nextIndex = 0

    init(notes: [FaceNote], rules: ScoringRules = ScoringRules(), offset: TimeInterval = 0) {
        self.notes = notes.sorted { $0.time < $1.time }
        self.rules = rules
        self.offset = offset.isFinite ? offset : 0
    }

    var isFinished: Bool { nextIndex >= notes.count }
    var remainingNotes: ArraySlice<FaceNote> { notes[nextIndex...] }
    var maxScore: Int { ScoreKeeper.maxScore(noteCount: notes.count) }

    /// 曲の時刻 `songTime` までに時間窓を過ぎたノーツをミスにする。毎フレーム呼ぶ。
    /// 振りと同じくオフセットを引いてから比べる（遅めに振る人の正しい振りを、窓の手前でミスにしないため）
    @discardableResult
    mutating func advance(to songTime: TimeInterval) -> [Judgement] {
        missPassedNotes(before: songTime - offset)
    }

    /// 振りを照合する。時間窓の中にノーツが無い振りは何もしない（減点しない）
    @discardableResult
    mutating func cut(_ event: CutEvent, at songTime: TimeInterval) -> Judgement? {
        let time = songTime - offset
        guard time.isFinite else { return nil }
        // 振りより前に窓を過ぎたノーツは、先にミスにしておく
        _ = missPassedNotes(before: time)
        guard nextIndex < notes.count else { return nil }
        let note = notes[nextIndex]
        let timingError = time - note.time
        guard abs(timingError) <= rules.hitWindow else { return nil }
        if let direction = note.direction, direction != event.direction {
            return record(.badCut(note, event.direction))
        }
        let score = CutScore(peakRate: event.peakRate, timingError: timingError, rules: rules)
        return record(.hit(note, score, timingError: timingError))
    }

    /// オフセットを引いた時刻 `time` までに時間窓を過ぎたノーツをミスにする
    private mutating func missPassedNotes(before time: TimeInterval) -> [Judgement] {
        guard time.isFinite else { return [] }
        var result: [Judgement] = []
        while nextIndex < notes.count, notes[nextIndex].time + rules.hitWindow < time {
            result.append(record(.miss(notes[nextIndex])))
        }
        return result
    }

    private mutating func record(_ judgement: Judgement) -> Judgement {
        switch judgement {
        case .hit(_, let score, _):
            keeper.recordHit(score)
        case .badCut, .miss:
            keeper.recordMiss()
        }
        judgements.append(judgement)
        nextIndex += 1
        return judgement
    }
}
