#!/usr/bin/env python3
"""Generate the zero-asset placeholder SFX set for Ashfall.

The prototype ships no third-party audio. Every sound is synthesized here so
the set is reproducible and license-clean.

Usage:  python tools/make_sfx.py
Output: assets/audio/*.wav (22050 Hz, mono, 16-bit)
"""

from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

SR = 22050
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio"

random.seed(7)


def fade(samples: list[float], attack: float = 0.004, release: float = 0.03) -> list[float]:
    a = max(1, int(attack * SR))
    r = max(1, int(release * SR))
    n = len(samples)
    for i in range(min(a, n)):
        samples[i] *= i / a
    for i in range(min(r, n)):
        samples[n - 1 - i] *= i / r
    return samples


def normalize(samples: list[float], peak: float = 0.72) -> list[float]:
    top = max((abs(s) for s in samples), default=0.0)
    if top <= 0.0:
        return samples
    gain = peak / top
    return [s * gain for s in samples]


def sweep(f0: float, f1: float, dur: float, kind: str = "sine", vol: float = 0.5) -> list[float]:
    n = int(dur * SR)
    out: list[float] = []
    phase = 0.0
    for i in range(n):
        k = i / max(1, n - 1)
        f = f0 + (f1 - f0) * k
        phase += 2.0 * math.pi * f / SR
        if kind == "sine":
            s = math.sin(phase)
        elif kind == "saw":
            s = 2.0 * ((phase / (2.0 * math.pi)) % 1.0) - 1.0
        else:  # square-ish with softened edges
            s = math.tanh(3.0 * math.sin(phase))
        # simple exponential body decay
        s *= math.exp(-3.2 * k)
        out.append(s * vol)
    return out


def noise_burst(dur: float, low: float, high: float, vol: float = 0.5, shape: float = 2.0) -> list[float]:
    """One-pole band-ish noise: lowpass state minus highpass state."""
    n = int(dur * SR)
    out: list[float] = []
    lp = 0.0
    hp_prev = 0.0
    for i in range(n):
        k = i / max(1, n - 1)
        white = random.uniform(-1.0, 1.0)
        cutoff = high + (low - high) * k
        alpha = max(0.001, min(0.999, cutoff / (SR * 0.5)))
        lp += alpha * (white - lp)
        # crude high-pass to remove rumble
        hp = lp - hp_prev * 0.92
        hp_prev = lp
        env = (1.0 - k) ** shape
        out.append(hp * env * vol)
    return out


def mix(*layers: list[float]) -> list[float]:
    n = max(len(layer) for layer in layers)
    out = [0.0] * n
    for layer in layers:
        for i, s in enumerate(layer):
            out[i] += s
    return out


def write(name: str, samples: list[float]) -> None:
    samples = normalize(fade(samples))
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{name}.wav"
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples)
        wf.writeframes(frames)
    print(f"wrote {path.relative_to(OUT.parent.parent)} ({len(samples) / SR:.2f}s)")


def main() -> None:
    write("swing", noise_burst(0.11, 900, 4200, 0.55, shape=1.6))
    write("hit", mix(noise_burst(0.07, 300, 2600, 0.55, 2.4), sweep(150, 72, 0.13, "sine", 0.65)))
    write("crit", mix(noise_burst(0.08, 500, 5200, 0.5, 2.0), sweep(1250, 720, 0.16, "sine", 0.35), sweep(160, 70, 0.14, "sine", 0.6)))
    write("roll", noise_burst(0.20, 260, 1300, 0.45, shape=1.2))
    write("jump", sweep(250, 500, 0.10, "sine", 0.6))
    write("land", mix(sweep(150, 58, 0.11, "sine", 0.7), noise_burst(0.06, 120, 900, 0.35, 3.0)))
    write("hurt", mix(sweep(230, 78, 0.24, "saw", 0.5), noise_burst(0.10, 200, 1600, 0.3, 2.0)))
    write("death", mix(noise_burst(0.55, 120, 2400, 0.5, 1.3), sweep(190, 38, 0.55, "saw", 0.45)))
    write("pickup", mix(sweep(880, 900, 0.06, "sine", 0.35), [0.0] * int(0.035 * SR) + sweep(1320, 1340, 0.09, "sine", 0.3)))
    write("shoot", mix(sweep(620, 240, 0.14, "sine", 0.5), noise_burst(0.05, 800, 3000, 0.3, 2.5)))
    write("ui", mix(sweep(520, 540, 0.05, "sine", 0.3), [0.0] * int(0.03 * SR) + sweep(780, 800, 0.06, "sine", 0.25)))
    write("wave", mix(sweep(110, 108, 0.36, "sine", 0.5), sweep(165, 160, 0.36, "sine", 0.28), noise_burst(0.22, 80, 500, 0.2, 2.0)))


if __name__ == "__main__":
    main()
