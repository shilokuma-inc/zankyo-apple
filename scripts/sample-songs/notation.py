"""楽譜を文字で書くための簡単な記法。

旋律: "F#4/1 G4/0.5 r/0.5 | ..."
  音名（C〜B、# か b、オクターブ。C4 が中央のド）/ 拍数。r は休符。| は小節の区切りで、拍数の合計を確かめる
和音: "D/2 A/2 | Bm/4 | C#7/4"
  根音（C〜B、# か b）と種類（なし: 長三和音、m: 短三和音、7: 属七、m7: 短七）/ 拍数
"""
from __future__ import annotations

from dataclasses import dataclass, replace

NOTE_OFFSETS = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
QUALITIES = {"": (0, 4, 7), "m": (0, 3, 7), "7": (0, 4, 7, 10), "m7": (0, 3, 7, 10)}


@dataclass(frozen=True)
class Note:
    """1 つの音。拍は区間の頭から数える"""

    beat: float
    length: float
    pitch: int


@dataclass(frozen=True)
class Chord:
    """1 つの和音。root は 0〜11（C が 0）"""

    beat: float
    length: float
    root: int
    intervals: tuple[int, ...]

    def tones(self, low: int, count: int) -> list[int]:
        """low 以上の、和音の構成音を低い方から count 個"""
        result: list[int] = []
        pitch = low
        while len(result) < count:
            if (pitch - self.root) % 12 in self.intervals:
                result.append(pitch)
            pitch += 1
        return result

    def bass(self, low: int = 36) -> int:
        """low 以上で最も低い根音"""
        return low + (self.root - low) % 12


def _accidental(text: str) -> tuple[int, str]:
    shift = 0
    while text and text[0] in "#b":
        shift += 1 if text[0] == "#" else -1
        text = text[1:]
    return shift, text


def pitch(name: str) -> int:
    """音名を MIDI のノート番号にする（C4 = 60）"""
    shift, octave = _accidental(name[1:])
    return 12 * (int(octave) + 1) + NOTE_OFFSETS[name[0]] + shift


def _bars(text: str):
    """小節ごとに (拍数, [(記号, 拍数)]) を返す"""
    for bar in text.split("|"):
        tokens = []
        for token in bar.split():
            symbol, length = token.split("/")
            tokens.append((symbol, float(length)))
        if tokens:
            yield sum(length for _, length in tokens), tokens


def _check(total: float, beats_per_bar: float | None, text: str) -> None:
    if beats_per_bar is not None and abs(total - beats_per_bar) > 1e-6:
        raise ValueError(f"小節の長さが {total} 拍（{beats_per_bar} 拍のはず）: {text}")


def melody(text: str, beats_per_bar: float | None = None, transpose: int = 0) -> tuple[list[Note], float]:
    """旋律の記法を音の列にする。戻り値は音の列と、全体の拍数"""
    notes: list[Note] = []
    beat = 0.0
    for total, tokens in _bars(text):
        _check(total, beats_per_bar, " ".join(f"{s}/{n}" for s, n in tokens))
        for symbol, length in tokens:
            if symbol != "r":
                notes.append(Note(beat, length, pitch(symbol) + transpose))
            beat += length
    return notes, beat


def chords(text: str, beats_per_bar: float | None = None, transpose: int = 0) -> tuple[list[Chord], float]:
    """和音の記法を和音の列にする。戻り値は和音の列と、全体の拍数"""
    result: list[Chord] = []
    beat = 0.0
    for total, tokens in _bars(text):
        _check(total, beats_per_bar, " ".join(f"{s}/{n}" for s, n in tokens))
        for symbol, length in tokens:
            shift, quality = _accidental(symbol[1:])
            root = (NOTE_OFFSETS[symbol[0]] + shift + transpose) % 12
            result.append(Chord(beat, length, root, QUALITIES[quality]))
            beat += length
    return result, beat


def shifted(notes: list[Note], beats: float) -> list[Note]:
    return [replace(note, beat=note.beat + beats) for note in notes]
