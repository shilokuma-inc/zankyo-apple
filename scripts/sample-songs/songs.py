"""サンプル楽曲 8 曲の楽譜と編曲。

クラシックは作曲者の没後 70 年を過ぎた曲（旋律そのもの）だけを使い、既存の演奏・録音や現代の編曲は使わない。
伴奏・変奏・後半の展開は、このスクリプトのための編曲（Claude による AI 生成）。オリジナルの 2 曲も Claude が作った。
"""
from __future__ import annotations

from arrangement import Song, section

# 配色: (背景の上, 背景の下, 太陽の上, 太陽の下, 格子)
NEON_PINK = ((38, 6, 58), (6, 2, 20), (255, 214, 92), (255, 46, 136), (80, 230, 255))
NEON_BLUE = ((6, 18, 60), (2, 4, 18), (140, 240, 255), (40, 110, 255), (255, 90, 200))
NEON_GREEN = ((4, 40, 36), (2, 8, 10), (220, 255, 140), (40, 200, 120), (120, 200, 255))
NEON_RED = ((50, 4, 12), (12, 2, 6), (255, 200, 120), (230, 30, 60), (255, 160, 60))
NEON_VIOLET = ((30, 8, 60), (6, 2, 18), (255, 160, 255), (140, 60, 255), (90, 255, 210))
NEON_GOLD = ((40, 26, 4), (10, 6, 2), (255, 240, 170), (255, 150, 30), (120, 210, 255))
NEON_TEAL = ((0, 34, 52), (0, 6, 14), (255, 120, 200), (0, 200, 220), (255, 230, 90))
NEON_FIRE = ((44, 0, 30), (10, 0, 8), (255, 250, 120), (255, 60, 30), (110, 160, 255))


def ode_to_joy() -> Song:
    """歓喜の歌（ベートーヴェン 交響曲第 9 番 第 4 楽章の主題）。ニ長調"""
    a1 = "F#4/1 F#4/1 G4/1 A4/1 | A4/1 G4/1 F#4/1 E4/1 | D4/1 D4/1 E4/1 F#4/1 | F#4/1.5 E4/0.5 E4/2"
    a2 = "F#4/1 F#4/1 G4/1 A4/1 | A4/1 G4/1 F#4/1 E4/1 | D4/1 D4/1 E4/1 F#4/1 | E4/1.5 D4/0.5 D4/2"
    b = "E4/1 E4/1 F#4/1 D4/1 | E4/1 F#4/0.5 G4/0.5 F#4/1 D4/1 | E4/1 F#4/0.5 G4/0.5 F#4/1 E4/1 | D4/1 E4/1 A3/2"
    ca1 = "D/4 | A/4 | D/4 | D/2 A/2"
    ca2 = "D/4 | A/4 | D/4 | A/2 D/2"
    cb = "A/2 D/2 | A/2 D/2 | A/2 D/2 | D/2 A/2"
    bar = 4
    return Song(
        slug="ode-to-joy", title="歓喜の歌", author="ベートーヴェン", bpm=120, beats_per_bar=bar,
        palette=NEON_GOLD, seed=1, preview_start=6,
        sections=[
            section("", "D/4 | D/4", bar, lead=None, bass="long", drums="light", chart=False),
            section(" | ".join([a1, a2, b, a2]), " | ".join([ca1, ca2, cb, ca2]), bar,
                    lead="pluck", octave=1, bass="root", drums="basic", crash=True),
            section(" | ".join([a2, b, a2]), " | ".join([ca2, cb, ca2]), bar,
                    lead="lead", octave=1, double="bell", bass="eighths", arp="8th", drums="four", crash=True),
            section("D5/4", "D/4", bar, lead="lead", bass="long", crash=True, chart=False),
        ],
    )


def fur_elise() -> Song:
    """エリーゼのために（ベートーヴェン）。イ短調・8 分の 3 拍子。1 拍を 8 分音符にとる"""
    core = (
        "E5/0.5 D#5/0.5 E5/0.5 B4/0.5 D5/0.5 C5/0.5 | A4/1 r/0.5 C4/0.5 E4/0.5 A4/0.5 | "
        "B4/1 r/0.5 E4/0.5 G#4/0.5 B4/0.5 | C5/1 r/0.5 E4/0.5 E5/0.5 D#5/0.5 | "
        "E5/0.5 D#5/0.5 E5/0.5 B4/0.5 D5/0.5 C5/0.5 | A4/1 r/0.5 C4/0.5 E4/0.5 A4/0.5 | "
        "B4/1 r/0.5 E4/0.5 C5/0.5 B4/0.5"
    )
    again = core + " | A4/1 r/1 E5/0.5 D#5/0.5"
    to_b = core + " | A4/1 r/0.5 B4/0.5 C5/0.5 D5/0.5"
    final = core + " | A4/3"
    ca = "Am/3 | Am/3 | E/3 | Am/3 | Am/3 | Am/3 | E/3 | Am/3"
    b = (
        "E5/1.5 G4/0.5 F5/0.5 E5/0.5 | D5/1.5 F4/0.5 E5/0.5 D5/0.5 | C5/1.5 E4/0.5 D5/0.5 C5/0.5 | "
        "B4/1 r/0.5 E4/0.5 E5/0.5 D#5/0.5 | E5/0.5 D#5/0.5 E5/0.5 D#5/0.5 E5/0.5 D#5/0.5"
    )
    cb = "C/3 | G/3 | Am/3 | E/3 | E/3"
    bar = 3
    quiet = {"lead": "pluck", "bass": "broken", "pad": False}
    soft = {"lead": "pluck", "bass": "broken", "drums": "waltz"}
    loud = {"lead": "lead", "double": "bell", "bass": "broken", "drums": "waltz", "arp": "8th"}
    return Song(
        slug="fur-elise", title="エリーゼのために", author="ベートーヴェン", bpm=140, beats_per_bar=bar,
        palette=NEON_VIOLET, seed=2, preview_start=3,
        sections=[
            section("r/3 | r/2 E5/0.5 D#5/0.5", "Am/3 | Am/3", bar, **quiet, chart=False),
            section(again, ca, bar, **quiet),
            section(to_b, ca, bar, **soft),
            section(b, cb, bar, **soft),
            section(again, ca, bar, **loud, crash=True),
            section(b, cb, bar, **loud),
            section(final, ca, bar, **loud, crash=True),
            section("", "Am/3", bar, lead=None, bass="long", crash=True, chart=False),
        ],
    )


def mountain_king() -> Song:
    """山の魔王の宮殿にて（グリーグ『ペール・ギュント』より）。ロ短調。同じ旋律を、楽器を足しながら 4 回くり返す"""
    theme = (
        "B3/0.5 C#4/0.5 D4/0.5 E4/0.5 F#4/0.5 D4/0.5 F#4/1 | F4/0.5 C#4/0.5 F4/1 E4/0.5 C4/0.5 E4/1 | "
        "B3/0.5 C#4/0.5 D4/0.5 E4/0.5 F#4/0.5 D4/0.5 F#4/0.5 B4/0.5 | A4/0.5 F#4/0.5 D4/0.5 F#4/0.5 A4/2"
    )
    chords = "Bm/4 | C#/2 C/2 | Bm/4 | D/4"
    bar = 4
    passes = [
        {"lead": "pizz", "octave": 1, "bass": "pulse", "pad": False},
        {"lead": "pizz", "octave": 1, "bass": "pulse", "drums": "basic"},
        {"lead": "lead", "octave": 1, "bass": "eighths", "drums": "four", "arp": "16th", "crash": True},
        {"lead": "lead", "octave": 1, "double": "lead", "bass": "eighths", "drums": "four", "arp": "16th", "crash": True},
    ]
    sections = [section("", "Bm/4 | Bm/4", bar, lead=None, bass="pulse", pad=False, drums="light", chart=False)]
    for options in passes:
        sections.append(section(theme, chords, bar, **options))
        # 2 回目は 5 度上（嬰ヘ短調）で
        sections.append(section(theme, chords, bar, transpose=7, **{**options, "crash": False}))
    sections.append(section("B4/4", "Bm/4", bar, lead="lead", bass="long", crash=True, chart=False))
    return Song(
        slug="mountain-king", title="山の魔王の宮殿にて", author="グリーグ", bpm=138, beats_per_bar=bar,
        palette=NEON_RED, seed=3, preview_start=30, sections=sections,
    )


def canon() -> Song:
    """カノン（パッヘルベル）。ニ長調。2 小節の和音の進行の上で、旋律を変えていく"""
    progression = "D/1 A/1 Bm/1 F#m/1 | G/1 D/1 G/1 A/1"
    lines = [
        "F#5/1 E5/1 D5/1 C#5/1 | B4/1 A4/1 B4/1 C#5/1",
        "D5/1 C#5/1 B4/1 A4/1 | G4/1 F#4/1 G4/1 E4/1",
        "D4/0.5 F#4/0.5 A4/0.5 G4/0.5 F#4/0.5 D4/0.5 F#4/0.5 E4/0.5 | "
        "D4/0.5 B3/0.5 D4/0.5 A4/0.5 G4/0.5 B4/0.5 A4/0.5 G4/0.5",
        # ここからは和音の構成音をたどる編曲
        "F#5/0.5 A5/0.5 E5/0.5 A5/0.5 D5/0.5 F#5/0.5 C#5/0.5 F#5/0.5 | "
        "B4/0.5 D5/0.5 A4/0.5 D5/0.5 B4/0.5 D5/0.5 C#5/0.5 E5/0.5",
    ]
    bar = 4
    sections = [section("", progression, bar, lead=None, chart=False)]
    for index, line in enumerate(lines):
        sections.append(section(line, progression, bar, lead="strings", octave=1 if index == 2 else 0))
    for index, line in enumerate(lines):
        options = {"lead": "bell" if index < 2 else "lead", "arp": "8th",
                   "drums": "half" if index < 2 else "basic", "crash": index == 0}
        sections.append(section(line, progression, bar, octave=1 if index == 2 else 0, **options))
    for index, line in enumerate(lines[:2]):
        sections.append(section(line, progression, bar, lead="lead", double="bell", arp="16th",
                                drums="basic", crash=index == 0))
    sections.append(section("D5/4", "D/4", bar, lead="strings", bass="long", crash=True, chart=False))
    return Song(
        slug="canon", title="カノン", author="パッヘルベル", bpm=96, beats_per_bar=bar,
        palette=NEON_TEAL, seed=4, preview_start=25, sections=sections,
    )


def minuet() -> Song:
    """メヌエット ト長調（ペツォールト。『アンナ・マグダレーナ・バッハの音楽帳』より）。4 分の 3 拍子"""
    head = (
        "D5/1 G4/0.5 A4/0.5 B4/0.5 C5/0.5 | D5/1 G4/1 G4/1 | E5/1 C5/0.5 D5/0.5 E5/0.5 F#5/0.5 | "
        "G5/1 G4/1 G4/1 | C5/1 D5/0.5 C5/0.5 B4/0.5 A4/0.5 | B4/1 C5/0.5 B4/0.5 A4/0.5 G4/0.5"
    )
    a = head + " | F#4/1 G4/0.5 A4/0.5 B4/0.5 G4/0.5 | A4/3 | " + head + " | A4/1 B4/0.5 A4/0.5 G4/0.5 F#4/0.5 | G4/3"
    ca = "G/3 | G/3 | C/3 | G/3 | C/3 | G/3 | D/3 | D/3 | G/3 | G/3 | C/3 | G/3 | C/3 | G/3 | D/3 | G/3"
    b = (
        "B5/1 G5/0.5 A5/0.5 B5/0.5 G5/0.5 | A5/1 D5/0.5 E5/0.5 F#5/0.5 D5/0.5 | G5/1 E5/0.5 F#5/0.5 G5/0.5 D5/0.5 | "
        "C#5/1 B4/0.5 C#5/0.5 A4/1 | A4/0.5 B4/0.5 C#5/0.5 D5/0.5 E5/0.5 F#5/0.5 | G5/1 F#5/1 E5/1 | "
        "F#5/1 A4/1 C#5/1 | D5/3"
    )
    cb = "G/3 | D/3 | Em/3 | A/3 | A/3 | Em/3 | A/3 | D/3"
    bar = 3
    return Song(
        slug="minuet", title="メヌエット ト長調", author="ペツォールト", bpm=132, beats_per_bar=bar,
        palette=NEON_GREEN, seed=5, preview_start=4,
        sections=[
            section("", "G/3 | G/3", bar, lead=None, bass="waltz", chart=False),
            section(a, ca, bar, lead="pluck", bass="waltz", pad=False),
            section(b, cb, bar, lead="pluck", bass="waltz", drums="waltz"),
            section(a, ca, bar, lead="lead", double="bell", bass="waltz", drums="waltz", arp="8th", crash=True),
            section("G4/3", "G/3", bar, lead="pluck", bass="long", crash=True, chart=False),
        ],
    )


def twinkle() -> Song:
    """きらきら星（フランス民謡。モーツァルトの変奏曲の主題）。ハ長調。2 回目は 8 分音符の変奏（編曲）"""
    theme = (
        "C4/1 C4/1 G4/1 G4/1 | A4/1 A4/1 G4/2 | F4/1 F4/1 E4/1 E4/1 | D4/1 D4/1 C4/2 | "
        "G4/1 G4/1 F4/1 F4/1 | E4/1 E4/1 D4/2 | G4/1 G4/1 F4/1 F4/1 | E4/1 E4/1 D4/2 | "
        "C4/1 C4/1 G4/1 G4/1 | A4/1 A4/1 G4/2 | F4/1 F4/1 E4/1 E4/1 | D4/1 D4/1 C4/2"
    )
    chords = (
        "C/4 | F/2 C/2 | F/2 C/2 | G/2 C/2 | C/2 F/2 | C/2 G/2 | C/2 F/2 | C/2 G/2 | "
        "C/4 | F/2 C/2 | F/2 C/2 | G/2 C/2"
    )
    one = "C5/0.5 E5/0.5 C5/0.5 E5/0.5 G5/0.5 E5/0.5 G5/0.5 E5/0.5"
    two = "A5/0.5 F5/0.5 A5/0.5 F5/0.5 G5/1 E5/1"
    three = "F5/0.5 A5/0.5 F5/0.5 A5/0.5 E5/0.5 G5/0.5 E5/0.5 G5/0.5"
    four = "D5/0.5 B4/0.5 D5/0.5 B4/0.5 C5/2"
    five = "G5/0.5 E5/0.5 G5/0.5 E5/0.5 F5/0.5 A5/0.5 F5/0.5 A5/0.5"
    six = "E5/0.5 C5/0.5 E5/0.5 C5/0.5 D5/1 B4/1"
    variation = " | ".join([one, two, three, four, five, six, five, six, one, two, three, four])
    bar = 4
    return Song(
        slug="twinkle", title="きらきら星", author="フランス民謡", bpm=112, beats_per_bar=bar,
        palette=NEON_BLUE, seed=6, preview_start=30,
        sections=[
            section("", "C/4 | G/2 C/2", bar, lead=None, bass="long", chart=False),
            section(theme, chords, bar, lead="bell", octave=1, bass="root", drums="light"),
            section(variation, chords, bar, lead="lead", double="bell", bass="eighths", arp="16th", drums="basic",
                    crash=True),
            section("C5/4", "C/4", bar, lead="bell", bass="long", crash=True, chart=False),
        ],
    )


def neon_drive() -> Song:
    """ネオン・ドライブ（オリジナル）。イ短調のシンセウェイブ"""
    a = (
        "E5/1 A4/0.5 C5/0.5 E5/1 D5/0.5 C5/0.5 | C5/1.5 A4/0.5 F4/1 A4/1 | G4/0.5 C5/0.5 E5/1 G5/1 E5/1 | "
        "D5/1.5 B4/0.5 G4/1 B4/1 | E5/1 A5/1 G5/0.5 E5/0.5 C5/1 | F5/1 E5/0.5 C5/0.5 A4/2 | "
        "G4/0.5 A4/0.5 C5/0.5 E5/0.5 G5/1 E5/1 | D5/1 B4/1 G4/1 B4/0.5 D5/0.5"
    )
    ca = "Am/4 | F/4 | C/4 | G/4 | Am/4 | F/4 | C/4 | G/4"
    b = (
        "A5/1 G5/1 F5/1 E5/1 | D5/1.5 E5/0.5 G5/2 | B4/0.5 E5/0.5 G5/1 B5/1 G5/1 | A5/3 r/1 | "
        "C6/1 A5/1 F5/1 A5/1 | B5/1 G5/1 D5/1 G5/1 | A5/1 E5/1 C5/1 E5/1 | A5/2 r/2"
    )
    cb = "F/4 | G/4 | Em/4 | Am/4 | F/4 | G/4 | Am/4 | Am/4"
    bar = 4
    return Song(
        slug="neon-drive", title="ネオン・ドライブ", author="斬響", bpm=116, beats_per_bar=bar,
        palette=NEON_PINK, seed=7, preview_start=8,
        sections=[
            section("", "Am/4 | F/4 | C/4 | G/4", bar, lead=None, bass="eighths", drums="basic", arp="16th", chart=False),
            section(a, ca, bar, lead="lead", bass="eighths", drums="basic", arp="16th"),
            section(b, cb, bar, lead="lead", double="bell", bass="eighths", drums="four", crash=True),
            section(a, ca, bar, lead="lead", double="lead", bass="eighths", drums="four", arp="16th", crash=True),
            section("A5/4 | r/4", "Am/4 | Am/4", bar, lead="lead", bass="long", crash=True, chart=False),
        ],
    )


def zankyo_rush() -> Song:
    """斬響ラッシュ（オリジナル）。ニ短調の速いダンス曲"""
    hook = (
        "D5/0.5 r/0.5 D5/0.5 F5/0.5 r/0.5 A5/0.5 G5/0.5 F5/0.5 | F5/0.5 r/0.5 D5/0.5 F5/0.5 r/0.5 Bb5/0.5 A5/0.5 F5/0.5 | "
        "C5/0.5 r/0.5 C5/0.5 F5/0.5 r/0.5 A5/0.5 G5/0.5 F5/0.5 | E5/1 G5/1 C6/1 Bb5/0.5 A5/0.5 | "
        "D5/0.5 r/0.5 D5/0.5 F5/0.5 r/0.5 A5/0.5 G5/0.5 F5/0.5 | F5/0.5 r/0.5 D5/0.5 F5/0.5 r/0.5 Bb5/0.5 A5/0.5 F5/0.5 | "
        "C5/0.5 r/0.5 C5/0.5 F5/0.5 r/0.5 A5/0.5 G5/0.5 F5/0.5 | E5/1 G5/1 A5/2"
    )
    ch = "Dm/4 | Bb/4 | F/4 | C/4 | Dm/4 | Bb/4 | F/4 | A/4"
    brk = "G5/4 | F5/4 | E5/2 G5/2 | A5/4"
    cbrk = "Gm/4 | Bb/4 | C/4 | A/4"
    bar = 4
    return Song(
        slug="zankyo-rush", title="斬響ラッシュ", author="斬響", bpm=150, beats_per_bar=bar,
        palette=NEON_FIRE, seed=8, preview_start=6,
        sections=[
            section("", "Dm/4 | Bb/4 | F/4 | C/4", bar, lead=None, bass=None, drums="four", arp="16th", chart=False),
            section(hook, ch, bar, lead="lead", bass="eighths", drums="four", arp="16th", crash=True),
            section(brk, cbrk, bar, lead="bell", bass="long", drums="half"),
            section(hook, ch, bar, lead="lead", double="lead", bass="eighths", drums="four", arp="16th", crash=True),
            section(brk, cbrk, bar, lead="strings", double="bell", bass="long", drums="half"),
            section(hook, ch, bar, lead="lead", double="bell", bass="eighths", drums="four", arp="16th", crash=True),
            section("D5/4 | r/4", "Dm/4 | Dm/4", bar, lead="lead", bass="long", crash=True, chart=False),
        ],
    )


SONGS = [ode_to_joy, fur_elise, mountain_king, canon, minuet, twinkle, neon_drive, zankyo_rush]
