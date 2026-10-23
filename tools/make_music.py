#!/usr/bin/env python3
"""Generate a seamless 32-second ambient loop for Ashfall.

Everything is derived from just-intonation ratios and periodic envelopes:
- drone frequencies are exact multiples of 1/32 Hz, so the loop is seamless
- the low pulse repeats every 2 s (16 times per loop)
- bell partials use 1 : 2.4 : 3.7 : 5.1 and decay before the loop ends

Usage:  python tools/make_music.py
Output: assets/audio/music_loop.wav (22050 Hz, mono, 16-bit, 32 s)
"""

from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

SR = 22050
DURATION = 32.0
N = int(SR * DURATION)
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "music_loop.wav"

random.seed(11)

# Integer cycle counts over 32 s keep every oscillator loop-aligned.
DRONE = [
    (2350.0 / DURATION, 0.20, 1.0 / 16.0),   # D2-ish
    (3520.0 / DURATION, 0.13, 1.0 / 8.0),    # A2
    (4700.0 / DURATION, 0.07, 1.0 / 32.0),   # D3
    (5589.0 / DURATION, 0.05, 1.0 / 4.0),    # F3
]


def smoothstep(edge0: float, edge1: float, x: float) -> float:
    t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def pulse(t: float) -> float:
    """Low heartbeat, repeating every 2 seconds."""
    local = t % 2.0
    if local > 0.55:
        return 0.0
    env = math.exp(-7.0 * local) * (1.0 - math.exp(-90.0 * local))
    freq = 48.0
    return math.sin(2.0 * math.pi * freq * local) * env


def bell(t: float, start: float, base: float) -> float:
    local = t - start
    if local < 0.0 or local > 3.4:
        return 0.0
    env = math.exp(-1.9 * local) * (1.0 - math.exp(-120.0 * local))
    value = 0.0
    for index, ratio in enumerate([1.0, 2.4, 3.7, 5.1]):
        value += math.sin(2.0 * math.pi * base * ratio * local) * (0.6 ** index)
    return value * env * 0.16


def drone(t: float) -> float:
    value = 0.0
    for freq, amp, lfo in DRONE:
        breathe = 0.72 + 0.28 * math.sin(2.0 * math.pi * lfo * t)
        # A second, slower beating layer inside the same loop length.
        value += math.sin(2.0 * math.pi * freq * t) * amp * breathe
    return value


def main() -> None:
    samples: list[float] = []
    for i in range(N):
        t = i / SR
        value = drone(t)
        value += pulse(t) * 0.23
        value += bell(t, 4.0, 261.625)
        value += bell(t, 12.0, 220.0)
        value += bell(t, 20.0, 293.75)
        value += bell(t, 28.0, 174.65625)
        # Subtle harmonic shimmer. All periods divide 32 s.
        value += math.sin(2.0 * math.pi * (7040.0 / DURATION) * t) * 0.012 * (0.5 + 0.5 * math.sin(2.0 * math.pi * t / 8.0))
        value += math.sin(2.0 * math.pi * (8372.0 / DURATION) * t) * 0.008 * (0.5 + 0.5 * math.sin(2.0 * math.pi * t / 16.0))
        # Very soft noise is replaced by a periodic high-sine cloud to keep the
        # loop click-free.
        value += math.sin(2.0 * math.pi * (10560.0 / DURATION) * t) * 0.004 * math.sin(2.0 * math.pi * t / 4.0)
        samples.append(value)

    peak = max(abs(s) for s in samples)
    gain = 0.52 / peak
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * gain)) * 32767)) for s in samples)
        wf.writeframes(frames)
    print(f"wrote {OUT} ({DURATION:.0f}s, {len(samples) / SR:.1f}s)")


if __name__ == "__main__":
    main()
