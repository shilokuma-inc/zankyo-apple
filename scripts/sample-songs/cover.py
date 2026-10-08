"""ジャケット画像。ネオンの太陽と、奥へ続く床の格子を描いた PNG（標準ライブラリだけで書き出す）"""
from __future__ import annotations

import math
import struct
import zlib

SIZE = 512
HORIZON = 330


def _mix(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[float, float, float]:
    t = min(max(t, 0.0), 1.0)
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def _pixel(x: int, y: int, palette: tuple[tuple[int, int, int], ...]) -> tuple[int, int, int]:
    top, bottom, sun_top, sun_bottom, grid = palette
    red, green, blue = _mix(top, bottom, y / SIZE)

    # 太陽: 上から下へ色を変え、下半分は横の切れ目を入れる（下ほど太く）
    center_x, center_y, radius = SIZE / 2, 215, 135
    distance = math.hypot(x - center_x, y - center_y)
    if y < HORIZON:
        glow = max(0.0, 1 - (distance - radius) / 90) if distance > radius else 0.0
        red, green, blue = _mix((int(red), int(green), int(blue)), sun_bottom, glow * 0.35)
        if distance <= radius:
            stripe = False
            if y > center_y - 10:
                band = (y - center_y + 10) % 26
                stripe = band < 3 + (y - center_y + 10) / 26
            if not stripe:
                edge = min(1.0, (radius - distance) / 1.5)
                sun = _mix(sun_top, sun_bottom, (y - (center_y - radius)) / (2 * radius))
                red, green, blue = _mix((int(red), int(green), int(blue)), (int(sun[0]), int(sun[1]), int(sun[2])), edge)
        return int(red), int(green), int(blue)

    # 床: 消失点へ向かう縦の線と、手前ほど間の広い横の線
    depth = y - HORIZON + 1
    lateral = (x - center_x) / depth
    vertical = abs(lateral - round(lateral / 1.6) * 1.6) * depth
    forward = 900 / depth
    horizontal = abs(forward - round(forward / 7) * 7) * depth * depth / 900
    line = min(vertical, horizontal)
    intensity = max(0.0, 1 - line / 1.6) + 0.35 * math.exp(-line / 5)
    fade = min(1.0, depth / 60)
    floor = _mix(bottom, top, 0.25)
    red, green, blue = _mix((int(floor[0]), int(floor[1]), int(floor[2])), grid, intensity * fade)
    # 地平線を光らせる
    red, green, blue = _mix((int(red), int(green), int(blue)), sun_bottom, max(0.0, 1 - depth / 14) * 0.8)
    return int(red), int(green), int(blue)


def png(palette: tuple[tuple[int, int, int], ...]) -> bytes:
    rows = bytearray()
    for y in range(SIZE):
        rows.append(0)
        for x in range(SIZE):
            rows.extend(_pixel(x, y, palette))

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b"")
