"""旋律から譜面（Beat Saber の v2 形式の難易度譜面）を作る。

アプリは譜面の 8 方向を上下左右に畳み、近すぎるノーツ（0.35 秒未満）を間引く（FaceNoteConverter）。
ここでは間引かれないよう、難易度ごとに間隔を空けて旋律の音を選び、旋律の上がり下がりで振る向きを決める。
"""
from __future__ import annotations

import json
from dataclasses import dataclass

from notation import Note


@dataclass(frozen=True)
class Difficulty:
    name: str
    rank: int
    # ノーツの最小の間隔（秒）
    gap: float
    # 使う音の拍の位置の下限（3: 小節の頭、2: 小節の半ば、1: 拍の頭、0: どこでも）
    min_priority: int
    # 上下に振るノーツにする、旋律の上がり下がりの幅（半音）
    vertical_step: int
    note_jump_speed: float


DIFFICULTIES = [
    Difficulty("Easy", 1, gap=1.3, min_priority=2, vertical_step=7, note_jump_speed=10),
    Difficulty("Normal", 3, gap=0.75, min_priority=1, vertical_step=4, note_jump_speed=12),
    Difficulty("Hard", 5, gap=0.4, min_priority=0, vertical_step=3, note_jump_speed=14),
]

# 振る向き → (_cutDirection, _type, _lineIndex, _lineLayer)
CUTS = {
    "up": (0, 1, 2, 2),
    "down": (1, 0, 1, 0),
    "left": (2, 0, 1, 1),
    "right": (3, 1, 2, 1),
}


def _priority(beat: float, beats_per_bar: int) -> int:
    position = beat % beats_per_bar

    def near(value: float) -> bool:
        return abs(position - value) < 1e-6

    if near(0) or near(beats_per_bar):
        return 3
    if beats_per_bar % 2 == 0 and near(beats_per_bar / 2):
        return 2
    if abs(position - round(position)) < 1e-6:
        return 1
    return 0


def pick(notes: list[Note], bpm: float, beats_per_bar: int, difficulty: Difficulty) -> list[tuple[Note, str]]:
    """旋律の音から間隔を空けてノーツを選び、振る向きを付ける"""
    seconds_per_beat = 60.0 / bpm
    picked: list[Note] = []
    last = float("-inf")
    for note in sorted(notes, key=lambda n: n.beat):
        time = note.beat * seconds_per_beat
        if _priority(note.beat, beats_per_bar) < difficulty.min_priority or time - last < difficulty.gap:
            continue
        picked.append(note)
        last = time

    result: list[tuple[Note, str]] = []
    side = "left"
    previous: Note | None = None
    for note in picked:
        direction = None
        # 上下は続けない（うなずきが続くと疲れるため）
        if previous is not None and (not result or result[-1][1] not in ("up", "down")):
            difference = note.pitch - previous.pitch
            if difference >= difficulty.vertical_step:
                direction = "up"
            elif difference <= -difficulty.vertical_step:
                direction = "down"
        if direction is None:
            direction = side
            side = "right" if side == "left" else "left"
        result.append((note, direction))
        previous = note
    return result


def beatmap(notes: list[tuple[Note, str]]) -> bytes:
    """v2 形式の難易度譜面"""
    entries = []
    for note, direction in notes:
        cut, kind, index, layer = CUTS[direction]
        entries.append({
            "_time": round(note.beat, 4),
            "_lineIndex": index,
            "_lineLayer": layer,
            "_type": kind,
            "_cutDirection": cut,
        })
    document = {"_version": "2.2.0", "_notes": entries, "_obstacles": [], "_events": []}
    return json.dumps(document, ensure_ascii=False, separators=(",", ":")).encode()


def info(title: str, author: str, bpm: float, preview_start: float, difficulties: list[Difficulty]) -> bytes:
    """v2 形式の Info.dat"""
    document = {
        "_version": "2.0.0",
        "_songName": title,
        "_songSubName": "",
        "_songAuthorName": author,
        "_levelAuthorName": "斬響",
        "_beatsPerMinute": bpm,
        "_songTimeOffset": 0,
        "_shuffle": 0,
        "_shufflePeriod": 0.5,
        "_previewStartTime": preview_start,
        "_previewDuration": 12,
        "_songFilename": "song.egg",
        "_coverImageFilename": "cover.png",
        "_environmentName": "DefaultEnvironment",
        "_allDirectionsEnvironmentName": "GlassDesertEnvironment",
        "_difficultyBeatmapSets": [{
            "_beatmapCharacteristicName": "Standard",
            "_difficultyBeatmaps": [
                {
                    "_difficulty": difficulty.name,
                    "_difficultyRank": difficulty.rank,
                    "_beatmapFilename": f"{difficulty.name}Standard.dat",
                    "_noteJumpMovementSpeed": difficulty.note_jump_speed,
                    "_noteJumpStartBeatOffset": 0,
                }
                for difficulty in difficulties
            ],
        }],
    }
    return json.dumps(document, ensure_ascii=False, indent=2).encode()
