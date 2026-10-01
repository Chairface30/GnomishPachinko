"""Synthesize the combo notes and the bumper boing.

Sounds/note1.ogg .. note16.ogg: a bell-like ding on a C major scale from
C4 up two octaves, one note per peg lit in a shot (the window plays
note<combo>, capped at 16). Sounds/bumper.ogg: a short low boing.

Run: python tools/make_notes.py   (pip install soundfile numpy)
"""
import math
import os

import numpy as np
import soundfile as sf

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Sounds")
RATE = 44100

# C major over two octaves: C D E F G A B, twice, then the top C
STEPS = [0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19, 21, 23, 24, 26]
BASE = 261.63  # C4


def bell(freq, secs=0.42):
    t = np.linspace(0, secs, int(RATE * secs), endpoint=False)
    tone = (np.sin(2 * math.pi * freq * t) * np.exp(-t * 7)
            + 0.45 * np.sin(2 * math.pi * freq * 2 * t) * np.exp(-t * 11)
            + 0.2 * np.sin(2 * math.pi * freq * 3.01 * t) * np.exp(-t * 16)
            + 0.08 * np.sin(2 * math.pi * freq * 4.2 * t) * np.exp(-t * 22))
    attack = np.minimum(1.0, t / 0.004)
    tone = tone * attack
    return (0.55 * tone / np.max(np.abs(tone))).astype(np.float32)


def boing(secs=0.28):
    t = np.linspace(0, secs, int(RATE * secs), endpoint=False)
    freq = 220 * np.exp(-t * 6) + 70
    phase = 2 * math.pi * np.cumsum(freq) / RATE
    tone = np.sin(phase) * np.exp(-t * 9) + 0.3 * np.sin(2 * phase) * np.exp(-t * 14)
    tone = tone * np.minimum(1.0, t / 0.003)
    return (0.6 * tone / np.max(np.abs(tone))).astype(np.float32)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for i, step in enumerate(STEPS, start=1):
        path = os.path.join(OUT, f"note{i}.ogg")
        sf.write(path, bell(BASE * 2 ** (step / 12)), RATE, format="OGG", subtype="VORBIS")
        print("wrote", path)
    path = os.path.join(OUT, "bumper.ogg")
    sf.write(path, boing(), RATE, format="OGG", subtype="VORBIS")
    print("wrote", path)
