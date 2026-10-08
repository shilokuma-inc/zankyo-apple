"""サンプル楽曲を生成する。

各曲について、音源（Ogg Vorbis。拡張子 .egg）・3 難易度の譜面・ジャケットを作り、取り込んだ譜面と同じ形の ZIP にまとめる。
アプリは ZIP を同梱し、初回起動時にライブラリへ入れる（SampleSongs.json が一覧）。

使い方:
  scripts/sample-songs/build-encoder.sh <SourcePackages のパス> /tmp/vorbis-encoder
  python3 scripts/sample-songs/generate.py --encoder /tmp/vorbis-encoder
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import tempfile
import time
import zipfile
from pathlib import Path

import chart
import cover
from arrangement import render
from songs import SONGS
from synth import write_wav

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = ROOT / "Zankyo" / "SampleSongs"
# ZIP の中の日時。毎回同じファイルができるよう固定する
ZIP_TIME = (2026, 10, 8, 0, 0, 0)
MAPPER = "斬響"


def _zip(path: Path, files: list[tuple[str, bytes, bool]]) -> None:
    with zipfile.ZipFile(path, "w") as archive:
        for name, data, compress in files:
            entry = zipfile.ZipInfo(name, date_time=ZIP_TIME)
            entry.compress_type = zipfile.ZIP_DEFLATED if compress else zipfile.ZIP_STORED
            entry.external_attr = 0o644 << 16
            archive.writestr(entry, data)


def build(song_factory, encoder: Path, output: Path) -> dict:
    began = time.time()
    song = song_factory()
    mix = render(song)
    pcm = mix.render(delay=song.seconds_per_beat * 0.75)
    with tempfile.TemporaryDirectory() as work:
        wav = Path(work) / "song.wav"
        egg = Path(work) / "song.egg"
        write_wav(wav, pcm)
        with wav.open("rb") as source, egg.open("wb") as destination:
            subprocess.run([str(encoder)], stdin=source, stdout=destination, stderr=subprocess.DEVNULL, check=True)
        audio = egg.read_bytes()

    beatmaps = []
    counts = {}
    for difficulty in chart.DIFFICULTIES:
        notes = chart.pick(song.chart_notes, song.bpm, song.beats_per_bar, difficulty)
        counts[difficulty.name] = len(notes)
        beatmaps.append((f"{difficulty.name}Standard.dat", chart.beatmap(notes)))
    info = chart.info(song.title, song.author, song.bpm, song.preview_start, chart.DIFFICULTIES)

    # beatsaver と同じ譜面ハッシュ: Info.dat と各難易度譜面を、Info.dat に並ぶ順につなげた SHA-1
    digest = hashlib.sha1(info)
    for _, data in beatmaps:
        digest.update(data)
    level_hash = digest.hexdigest()

    resource = f"sample-{song.slug}"
    files = [("Info.dat", info, True)] + [(name, data, True) for name, data in beatmaps]
    files += [("song.egg", audio, False), ("cover.png", cover.png(song.palette), False)]
    _zip(output / f"{resource}.zip", files)

    seconds = song.total_beats * song.seconds_per_beat
    print(f"{song.title}: {seconds:.1f} 秒・ノーツ {counts}・音源 {len(audio) // 1024} KB・{time.time() - began:.0f} 秒で生成")
    return {
        "id": song.slug,
        "resource": resource,
        "hash": level_hash,
        "songName": song.title,
        "songAuthorName": song.author,
        "mapperName": MAPPER,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="サンプル楽曲を生成する")
    parser.add_argument("--encoder", type=Path, required=True, help="build-encoder.sh で作ったエンコーダー")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--only", help="この slug の曲だけ作る（一覧は書き換えない）")
    arguments = parser.parse_args()
    arguments.output.mkdir(parents=True, exist_ok=True)

    factories = SONGS
    if arguments.only:
        factories = [factory for factory in SONGS if factory().slug == arguments.only]
        if not factories:
            sys.exit(f"{arguments.only} という曲は無い")
    songs = [build(factory, arguments.encoder, arguments.output) for factory in factories]
    if arguments.only:
        return
    manifest = {"version": 1, "songs": songs}
    (arguments.output / "SampleSongs.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
