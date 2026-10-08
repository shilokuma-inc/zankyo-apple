#!/bin/bash
# サンプル楽曲の音源を Ogg Vorbis にするエンコーダーをビルドする。
#
# アプリが使っている vorbis-swift / ogg-swift（SPM）のソースから、libvorbis の examples/encoder_example.c をビルドする。
# 外部からのダウンロードは要らない（Xcode で一度ビルドして、SourcePackages に取得済みであること）。
#
# 使い方: scripts/sample-songs/build-encoder.sh <SourcePackages のパス> <出力先のパス>
#   例: scripts/sample-songs/build-encoder.sh ~/Library/Developer/Xcode/DerivedData/Zankyo-xxxx/SourcePackages /tmp/vorbis-encoder
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "使い方: $0 <SourcePackages のパス> <出力先のパス>" >&2
  exit 1
fi

CHECKOUTS="$1/checkouts"
OUTPUT="$2"
VORBIS="$CHECKOUTS/vorbis-swift/Sources/vorbis-swift/native"
OGG="$CHECKOUTS/ogg-swift/Sources/ogg-swift/native"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# libogg の config_types.h は configure で作られるので、標準の固定幅の型で書く
mkdir -p "$WORK/include/ogg"
cat > "$WORK/include/ogg/config_types.h" <<'HEADER'
#ifndef __CONFIG_TYPES_H__
#define __CONFIG_TYPES_H__
#include <stdint.h>
typedef int16_t ogg_int16_t;
typedef uint16_t ogg_uint16_t;
typedef int32_t ogg_int32_t;
typedef uint32_t ogg_uint32_t;
typedef int64_t ogg_int64_t;
typedef uint64_t ogg_uint64_t;
#endif
HEADER

# 品質は 0.3（約 112kbps）。ストリームの番号を固定して、同じ入力からは同じファイルができるようにする
sed -e 's/ret=vorbis_encode_init_vbr(&vi,2,44100,0.1);/ret=vorbis_encode_init_vbr(\&vi,2,44100,0.3);/' \
    -e 's/srand(time(NULL));/srand(0);/' \
    "$VORBIS/examples/encoder_example.c" > "$WORK/encoder.c"
# 依存先の更新で encoder_example.c の書き方が変わると、置換が効かないまま進んでしまうので確かめる
grep -Fq 'vorbis_encode_init_vbr(&vi,2,44100,0.3);' "$WORK/encoder.c" || { echo "品質の置換に失敗しました" >&2; exit 1; }
grep -Fq 'srand(0);' "$WORK/encoder.c" || { echo "乱数の種の置換に失敗しました" >&2; exit 1; }

SOURCES=()
for file in "$VORBIS"/lib/*.c; do
  # main を持つ調査用のプログラムは除く
  case "$(basename "$file")" in barkmel.c|psytune.c|tone.c) continue ;; esac
  SOURCES+=("$file")
done

clang -O2 -w -I"$WORK/include" -I"$OGG/include" -I"$VORBIS/include" -I"$VORBIS/lib" \
  "$WORK/encoder.c" "${SOURCES[@]}" "$OGG/src/bitwise.c" "$OGG/src/framing.c" -lm -o "$OUTPUT"
echo "ビルドしました: $OUTPUT"
