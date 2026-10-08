"""音の合成。1 周期分の波形の表を読み出す単純なシンセサイザーと、ドラムの音を作る（標準ライブラリだけで動く）"""
from __future__ import annotations

import math
import random
import wave
from array import array
from pathlib import Path

SAMPLE_RATE = 44_100
TABLE_SIZE = 4_096
MASK = TABLE_SIZE - 1


def _table(harmonics: list[tuple[int, float]]) -> array:
    """倍音（次数, 大きさ）を足し合わせた 1 周期分の波形。最大を 1 にそろえる"""
    values = [
        sum(amplitude * math.sin(2 * math.pi * order * index / TABLE_SIZE) for order, amplitude in harmonics)
        for index in range(TABLE_SIZE)
    ]
    peak = max(abs(value) for value in values)
    return array("d", (value / peak for value in values))


TABLES = {
    "saw": _table([(order, 1 / order) for order in range(1, 11)]),
    "soft": _table([(1, 1.0), (2, 0.4), (3, 0.2), (4, 0.1)]),
    "square": _table([(order, 1 / order) for order in (1, 3, 5, 7, 9)]),
    "pluck": _table([(1, 1.0), (2, 0.6), (3, 0.35), (4, 0.2), (5, 0.12), (6, 0.08)]),
    "bass": _table([(1, 1.0), (2, 0.5), (3, 0.25), (4, 0.1)]),
    "sine": _table([(1, 1.0)]),
}


def frequency(pitch: float) -> float:
    """MIDI のノート番号の周波数（A4 = 440Hz）"""
    return 440.0 * 2 ** ((pitch - 69) / 12)


class Mix:
    """左右 2 チャンネルの音を足し合わせる。旋律は wet に入れ、最後にディレイ（こだま）をかける"""

    def __init__(self, seconds: float, seed: int) -> None:
        size = int((seconds + 2.5) * SAMPLE_RATE)
        self.size = size
        self.dry = (array("d", bytes(8 * size)), array("d", bytes(8 * size)))
        self.wet = (array("d", bytes(8 * size)), array("d", bytes(8 * size)))
        self.random = random.Random(seed)

    def tone(
        self,
        start: float,
        length: float,
        hertz: float,
        table: array,
        gain: float,
        pan: float = 0.0,
        attack: float = 0.005,
        decay: float = 0.1,
        sustain: float = 0.8,
        release: float = 0.08,
        fade: float = 0.0,
        wet: bool = False,
    ) -> None:
        """1 つの音を足す。fade は鳴っている間の減衰（毎秒の指数）、pan は -1（左）〜 1（右）"""
        left, right = self.wet if wet else self.dry
        first = int(start * SAMPLE_RATE)
        held = max(1, int(length * SAMPLE_RATE))
        released = max(1, int(release * SAMPLE_RATE))
        count = min(held + released, self.size - first)
        if count <= 0:
            return
        attack_samples = max(1, int(attack * SAMPLE_RATE))
        decay_end = attack_samples + max(1, int(decay * SAMPLE_RATE))
        angle = (pan + 1) * math.pi / 4
        left_gain = gain * math.cos(angle)
        right_gain = gain * math.sin(angle)
        step = hertz * TABLE_SIZE / SAMPLE_RATE
        fade_step = math.exp(-fade / SAMPLE_RATE)
        level = 1.0
        phase = 0.0
        for index in range(count):
            if index < attack_samples:
                envelope = index / attack_samples
            elif index < decay_end:
                envelope = 1.0 - (1.0 - sustain) * (index - attack_samples) / (decay_end - attack_samples)
            else:
                envelope = sustain
            envelope *= level
            level *= fade_step
            if index >= held:
                envelope *= 1.0 - (index - held) / released
            sample = table[int(phase) & MASK] * envelope
            phase += step
            left[first + index] += sample * left_gain
            right[first + index] += sample * right_gain

    def kick(self, start: float, gain: float = 0.5) -> None:
        """低い音程が素早く下がるキック"""
        left, right = self.dry
        first = int(start * SAMPLE_RATE)
        phase = 0.0
        for index in range(min(int(0.35 * SAMPLE_RATE), self.size - first)):
            time = index / SAMPLE_RATE
            phase += 2 * math.pi * (46 + 120 * math.exp(-time * 30)) / SAMPLE_RATE
            sample = math.sin(phase) * math.exp(-time * 7.5) * gain
            left[first + index] += sample
            right[first + index] += sample

    def snare(self, start: float, gain: float = 0.22) -> None:
        """雑音と短い胴鳴りのスネア"""
        left, right = self.dry
        first = int(start * SAMPLE_RATE)
        uniform = self.random.uniform
        for index in range(min(int(0.2 * SAMPLE_RATE), self.size - first)):
            time = index / SAMPLE_RATE
            body = math.sin(2 * math.pi * 185 * time) * math.exp(-time * 30) * 0.7
            sample = (uniform(-1, 1) * math.exp(-time * 22) + body) * gain
            left[first + index] += sample
            right[first + index] += sample

    def hat(self, start: float, gain: float = 0.09, length: float = 0.05) -> None:
        """高い雑音だけを残したハイハット（隣り合う値の差で低い音を除く）"""
        self._noise(start, gain, length, decay=70, pan=0.3, highpass=True)

    def crash(self, start: float, gain: float = 0.06) -> None:
        self._noise(start, gain, 1.4, decay=2.6, pan=-0.2, highpass=True)

    def _noise(self, start: float, gain: float, length: float, decay: float, pan: float, highpass: bool) -> None:
        left, right = self.dry
        first = int(start * SAMPLE_RATE)
        angle = (pan + 1) * math.pi / 4
        left_gain = gain * math.cos(angle)
        right_gain = gain * math.sin(angle)
        uniform = self.random.uniform
        previous = 0.0
        for index in range(min(int(length * SAMPLE_RATE), self.size - first)):
            value = uniform(-1, 1)
            sample = (value - previous if highpass else value) * math.exp(-index / SAMPLE_RATE * decay)
            previous = value
            left[first + index] += sample * left_gain
            right[first + index] += sample * right_gain

    def render(self, delay: float, feedback: float = 0.3, taps: int = 3) -> array:
        """ディレイをかけて足し合わせ、16 ビットのステレオ（左右交互）にする。最大を -1dB 付近にそろえる"""
        left = array("d", self.dry[0])
        right = array("d", self.dry[1])
        wet_left, wet_right = self.wet
        size = self.size
        for index in range(size):
            left[index] += wet_left[index]
            right[index] += wet_right[index]
        offset = int(delay * SAMPLE_RATE)
        gain = 1.0
        for tap in range(1, taps + 1):
            gain *= feedback
            shift = offset * tap
            # 左右を入れ替えながら返す（ピンポン）
            source_left, source_right = (wet_right, wet_left) if tap % 2 else (wet_left, wet_right)
            for index in range(size - shift):
                left[index + shift] += source_left[index] * gain
                right[index + shift] += source_right[index] * gain
        peak = max(max(map(abs, left)), max(map(abs, right))) or 1.0
        scale = 0.89 * 32_767 / peak
        pcm = array("h", bytes(4 * size))
        for index in range(size):
            pcm[2 * index] = int(left[index] * scale)
            pcm[2 * index + 1] = int(right[index] * scale)
        return pcm


def write_wav(path: Path, pcm: array) -> None:
    """44.1kHz・16 ビット・ステレオの WAV"""
    with wave.open(str(path), "wb") as file:
        file.setnchannels(2)
        file.setsampwidth(2)
        file.setframerate(SAMPLE_RATE)
        file.writeframes(pcm.tobytes())
