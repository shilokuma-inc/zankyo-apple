"""編曲: 区間（旋律・和音・伴奏の組み合わせ）を並べて 1 曲を描き出す"""
from __future__ import annotations

from dataclasses import dataclass, field

import notation
from notation import Chord, Note
from synth import TABLES, Mix, frequency


@dataclass
class Section:
    """曲の 1 区間。拍は区間の頭から数える"""

    melody: list[Note]
    chords: list[Chord]
    beats: float
    # 旋律の楽器（None なら旋律を鳴らさない）と、上げるオクターブ数
    lead: str | None = "lead"
    octave: int = 0
    # 旋律を 1 オクターブ上で重ねる楽器
    double: str | None = None
    # 伴奏
    bass: str | None = "root"
    pad: bool = True
    arp: str | None = None
    drums: str | None = None
    # 区間の頭でシンバルを鳴らす
    crash: bool = False
    # 旋律を譜面のノーツに使う
    chart: bool = True


@dataclass
class Song:
    slug: str
    title: str
    author: str
    bpm: float
    beats_per_bar: int
    sections: list[Section]
    # ジャケットの配色（背景の上・下、太陽の上・下、格子）
    palette: tuple[tuple[int, int, int], ...]
    seed: int
    # 曲の選択画面での試聴の頭（秒）
    preview_start: float = 10.0
    # この曲を足した一覧の版。アプリは、入れたことのある版より新しい曲だけを入れる（消した曲を入れ直さない）
    since: int = 1
    chart_notes: list[Note] = field(default_factory=list)

    @property
    def total_beats(self) -> float:
        return sum(section.beats for section in self.sections)

    @property
    def seconds_per_beat(self) -> float:
        return 60.0 / self.bpm


def section(melody_text: str, chord_text: str, beats_per_bar: int, transpose: int = 0, **options) -> Section:
    """記法から区間を作る。旋律と和音の長さが合わなければ止める"""
    chords, beats = notation.chords(chord_text, beats_per_bar, transpose)
    melody: list[Note] = []
    if melody_text:
        melody, melody_beats = notation.melody(melody_text, beats_per_bar, transpose)
        if abs(melody_beats - beats) > 1e-6:
            raise ValueError(f"旋律（{melody_beats} 拍）と和音（{beats} 拍）の長さが違う")
    return Section(melody, chords, beats, **options)


# 楽器: (Mix, 始まりの秒, 長さの秒, ノート番号, 音量の倍率)


def lead(mix: Mix, start: float, length: float, pitch: int, gain: float = 1.0) -> None:
    """少しずらした 2 つのノコギリ波を左右に置いたリード"""
    for detune, pan in ((-0.003, -0.35), (0.003, 0.35)):
        mix.tone(start, length * 0.92, frequency(pitch) * (1 + detune), TABLES["saw"], 0.2 * gain, pan,
                 attack=0.01, decay=0.15, sustain=0.65, release=0.12, wet=True)


def pluck(mix: Mix, start: float, length: float, pitch: int, gain: float = 1.0) -> None:
    """はじいた弦（チェンバロ・ピアノの代わり）"""
    mix.tone(start, length, frequency(pitch), TABLES["pluck"], 0.55 * gain, 0.0,
             attack=0.003, decay=0.01, sustain=1.0, release=0.12, fade=3.5, wet=True)


def pizz(mix: Mix, start: float, length: float, pitch: int, gain: float = 1.0) -> None:
    """短いピチカート"""
    mix.tone(start, min(length, 0.25), frequency(pitch), TABLES["pluck"], 0.6 * gain, 0.0,
             attack=0.002, decay=0.01, sustain=1.0, release=0.06, fade=9.0, wet=True)


def bell(mix: Mix, start: float, length: float, pitch: int, gain: float = 1.0) -> None:
    """整数倍でない倍音を持つ鐘（グロッケン）"""
    for ratio, amplitude, fade in ((1.0, 1.0, 2.5), (2.76, 0.35, 7.0), (5.4, 0.15, 12.0)):
        mix.tone(start, length, frequency(pitch) * ratio, TABLES["sine"], 0.38 * amplitude * gain, 0.1,
                 attack=0.002, decay=0.01, sustain=1.0, release=0.3, fade=fade, wet=True)


def strings(mix: Mix, start: float, length: float, pitch: int, gain: float = 1.0) -> None:
    """ゆっくり立ち上がる弦"""
    for detune, pan in ((-0.004, -0.5), (0.004, 0.5)):
        mix.tone(start, length, frequency(pitch) * (1 + detune), TABLES["soft"], 0.22 * gain, pan,
                 attack=0.08, decay=0.2, sustain=0.85, release=0.3, wet=True)


INSTRUMENTS = {"lead": lead, "pluck": pluck, "pizz": pizz, "bell": bell, "strings": strings}


def _chord_at(chords: list[Chord], beat: float) -> Chord:
    for chord in chords:
        if chord.beat <= beat + 1e-6 < chord.beat + chord.length:
            return chord
    return chords[-1]


def _steps(beats: float, step: float):
    beat = 0.0
    while beat < beats - 1e-6:
        yield beat
        beat += step


def _bass(mix: Mix, section_: Section, start: float, spb: float, beats_per_bar: int) -> None:
    pattern = section_.bass
    if pattern is None:
        return
    table = TABLES["bass"]

    def note(beat: float, length: float, pitch: int, gain: float = 0.24) -> None:
        mix.tone(start + beat * spb, length * spb, frequency(pitch), table, gain,
                 attack=0.005, decay=0.1, sustain=0.8, release=0.06)

    if pattern == "long":
        for chord in section_.chords:
            note(chord.beat, chord.length * 0.95, chord.bass())
    elif pattern == "root":
        for beat in _steps(section_.beats, 1.0):
            note(beat, 0.9, _chord_at(section_.chords, beat).bass())
    elif pattern == "eighths":
        for index, beat in enumerate(_steps(section_.beats, 0.5)):
            root = _chord_at(section_.chords, beat).bass()
            note(beat, 0.42, root + (12 if index % 2 else 0), 0.2)
    elif pattern == "pulse":
        for beat in _steps(section_.beats, 0.5):
            note(beat, 0.3, _chord_at(section_.chords, beat).bass(), 0.22)
    elif pattern == "waltz":
        for beat in _steps(section_.beats, beats_per_bar):
            note(beat, 1.0, _chord_at(section_.chords, beat).bass())
    elif pattern == "broken":
        # 小節の頭で 根音・5 度・オクターブ を 16 分（拍の半分）で（エリーゼのための左手）
        for beat in _steps(section_.beats, beats_per_bar):
            root = _chord_at(section_.chords, beat).bass(low=40)
            for offset, pitch in enumerate((root, root + 7, root + 12)):
                mix.tone(start + (beat + offset * 0.5) * spb, 0.9 * spb, frequency(pitch), TABLES["pluck"], 0.2,
                         attack=0.003, decay=0.01, sustain=1.0, release=0.1, fade=3.0)
    else:
        raise ValueError(f"ベースの刻み方が無い: {pattern}")


def _pad(mix: Mix, section_: Section, start: float, spb: float) -> None:
    if not section_.pad:
        return
    for chord in section_.chords:
        for index, pitch in enumerate(chord.tones(low=55, count=len(chord.intervals))):
            pan = (-0.6, 0.0, 0.6, 0.3)[index % 4]
            mix.tone(start + chord.beat * spb, chord.length * spb, frequency(pitch), TABLES["soft"], 0.05, pan,
                     attack=0.25, decay=0.3, sustain=0.8, release=0.4)


def _arp(mix: Mix, section_: Section, start: float, spb: float) -> None:
    if section_.arp is None:
        return
    step = {"8th": 0.5, "16th": 0.25}[section_.arp]
    for index, beat in enumerate(_steps(section_.beats, step)):
        tones = _chord_at(section_.chords, beat).tones(low=64, count=4)
        pitch = tones[index % len(tones)]
        mix.tone(start + beat * spb, step * 0.8 * spb, frequency(pitch), TABLES["square"], 0.035,
                 -0.4 if index % 2 else 0.4, attack=0.003, decay=0.06, sustain=0.4, release=0.04)


def _drums(mix: Mix, section_: Section, start: float, spb: float, beats_per_bar: int) -> None:
    if section_.crash:
        mix.crash(start)
    pattern = section_.drums
    if pattern is None:
        return
    for bar in _steps(section_.beats, beats_per_bar):
        def at(beat: float) -> float:
            return start + (bar + beat) * spb

        if pattern == "light":
            mix.kick(at(0), 0.4)
            for beat in range(beats_per_bar):
                mix.hat(at(beat))
        elif pattern == "basic":
            for beat in range(beats_per_bar):
                if beat % 2 == 0:
                    mix.kick(at(beat))
                else:
                    mix.snare(at(beat))
            for half in range(beats_per_bar * 2):
                mix.hat(at(half * 0.5), 0.07 if half % 2 else 0.09)
        elif pattern == "four":
            for beat in range(beats_per_bar):
                mix.kick(at(beat))
                if beat % 2:
                    mix.snare(at(beat), 0.18)
                mix.hat(at(beat + 0.5), 0.11, 0.07)
                mix.hat(at(beat + 0.25), 0.04)
                mix.hat(at(beat + 0.75), 0.04)
        elif pattern == "half":
            mix.kick(at(0))
            mix.snare(at(beats_per_bar / 2), 0.17)
            for beat in range(beats_per_bar):
                mix.hat(at(beat))
        elif pattern == "waltz":
            mix.kick(at(0), 0.42)
            for beat in range(1, beats_per_bar):
                mix.hat(at(beat), 0.08)
                mix.snare(at(beat), 0.08)
        else:
            raise ValueError(f"ドラムの型が無い: {pattern}")


def render(song: Song) -> Mix:
    """曲全体を描き出す。譜面に使う旋律（曲の頭からの拍）を song.chart_notes に入れる"""
    spb = song.seconds_per_beat
    mix = Mix(song.total_beats * spb, song.seed)
    song.chart_notes = []
    start_beat = 0.0
    for part in song.sections:
        start = start_beat * spb
        if part.lead is not None:
            play = INSTRUMENTS[part.lead]
            double = INSTRUMENTS[part.double] if part.double else None
            for note in part.melody:
                pitch = note.pitch + 12 * part.octave
                play(mix, start + note.beat * spb, note.length * spb, pitch)
                if double is not None:
                    double(mix, start + note.beat * spb, note.length * spb, pitch + 12, 0.45)
            if part.chart:
                song.chart_notes.extend(notation.shifted(part.melody, start_beat))
        _bass(mix, part, start, spb, song.beats_per_bar)
        _pad(mix, part, start, spb)
        _arp(mix, part, start, spb)
        _drums(mix, part, start, spb, song.beats_per_bar)
        start_beat += part.beats
    return mix
