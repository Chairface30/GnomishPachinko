"""Synthesize the combo notes and the bumper boing.

Sounds/note1.ogg .. note16.ogg: a bell-like ding on a C major scale from
C4 up two octaves, one note per peg lit in a shot (the window plays
note<combo>, capped at 16). Sounds/bumper.ogg: a short low boing.

Placeholder effects (replace with real ones under the same names):
clink.ogg (a tough piece cracking), crack.ogg (an egg cracking),
hatch.ogg (an egg hatching), gem.ogg (a gem knocked loose or caught),
boss_hit.ogg (a thud), boss_down.ogg (a crash), zap.ogg (chain
lightning), blast.ogg (the space blast).

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


def norm(tone, level=0.6):
    return (level * tone / max(1e-6, np.max(np.abs(tone)))).astype(np.float32)


def clink(secs=0.16):
    t = np.linspace(0, secs, int(RATE * secs), endpoint=False)
    tone = (np.sin(2 * math.pi * 2600 * t) * np.exp(-t * 40)
            + 0.5 * np.sin(2 * math.pi * 4100 * t) * np.exp(-t * 55))
    return norm(tone * np.minimum(1.0, t / 0.002), 0.45)


def crack(secs=0.22):
    rng = np.random.default_rng(3)
    t = np.linspace(0, secs, int(RATE * secs), endpoint=False)
    noise = rng.standard_normal(t.size)
    # a few sharp snaps riding on a short burst of noise
    env = np.exp(-t * 30)
    for k in (0.0, 0.03, 0.07):
        env += 2.0 * np.exp(-np.maximum(0, t - k) * 220) * (t >= k)
    return norm(noise * env, 0.5)


def hatch(secs=0.5):
    t = np.linspace(0, secs, int(RATE * secs), endpoint=False)
    freq = 900 + 900 * np.sin(2 * math.pi * 6 * t) * np.exp(-t * 3) + 600 * t
    phase = 2 * math.pi * np.cumsum(freq) / RATE
    tone = np.sin(phase) * np.exp(-t * 4) * np.minimum(1.0, t / 0.01)
    return norm(tone, 0.5)


def gem(secs=0.45):
    t = np.linspace(0, secs, int(RATE * secs), endpoint=False)
    tone = np.zeros_like(t)
    for i, f in enumerate((1568, 2093, 2637, 3136)):
        start = i * 0.05
        tt = np.maximum(0, t - start)
        tone += np.sin(2 * math.pi * f * tt) * np.exp(-tt * 9) * (t >= start)
    return norm(tone, 0.5)


def boss_hit(secs=0.3):
    rng = np.random.default_rng(7)
    t = np.linspace(0, secs, int(RATE * secs), endpoint=False)
    freq = 160 * np.exp(-t * 10) + 50
    phase = 2 * math.pi * np.cumsum(freq) / RATE
    tone = np.sin(phase) * np.exp(-t * 12) + 0.4 * rng.standard_normal(t.size) * np.exp(-t * 40)
    return norm(tone, 0.6)


def boss_down(secs=1.0):
    rng = np.random.default_rng(11)
    t = np.linspace(0, secs, int(RATE * secs), endpoint=False)
    noise = rng.standard_normal(t.size) * np.exp(-t * 4)
    freq = 120 * np.exp(-t * 3) + 30
    phase = 2 * math.pi * np.cumsum(freq) / RATE
    tone = 0.7 * np.sin(phase) * np.exp(-t * 3) + 0.6 * noise
    return norm(tone, 0.65)


def zap(secs=0.35):
    rng = np.random.default_rng(5)
    t = np.linspace(0, secs, int(RATE * secs), endpoint=False)
    buzz = np.sign(np.sin(2 * math.pi * 90 * t)) * np.sin(2 * math.pi * 1800 * t)
    tone = (buzz + 0.5 * rng.standard_normal(t.size)) * np.exp(-t * 9)
    return norm(tone, 0.45)


def slowmo(secs=0.7):
    t = np.linspace(0, secs, int(RATE * secs), endpoint=False)
    # a falling whoosh with a heartbeat thump under it
    freq = 1400 * np.exp(-t * 5) + 120
    phase = 2 * math.pi * np.cumsum(freq) / RATE
    tone = 0.5 * np.sin(phase) * np.exp(-t * 3)
    thump = np.sin(2 * math.pi * 55 * t) * np.exp(-np.maximum(0, t - 0.25) * 18) * (t >= 0.25)
    return norm(tone + 0.8 * thump, 0.55)


def blast(secs=0.9):
    rng = np.random.default_rng(13)
    t = np.linspace(0, secs, int(RATE * secs), endpoint=False)
    noise = rng.standard_normal(t.size)
    # low-pass the noise by a running mean so it booms instead of hisses
    k = 24
    smooth = np.convolve(noise, np.ones(k) / k, mode="same")
    freq = 90 * np.exp(-t * 4) + 35
    phase = 2 * math.pi * np.cumsum(freq) / RATE
    tone = (0.8 * np.sin(phase) + 1.5 * smooth) * np.exp(-t * 3.5) * np.minimum(1.0, t / 0.004)
    return norm(tone, 0.7)


EFFECTS = {
    "clink.ogg": clink, "crack.ogg": crack, "hatch.ogg": hatch, "gem.ogg": gem,
    "boss_hit.ogg": boss_hit, "boss_down.ogg": boss_down, "zap.ogg": zap, "blast.ogg": blast,
    "slowmo.ogg": slowmo,
}


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for i, step in enumerate(STEPS, start=1):
        path = os.path.join(OUT, f"note{i}.ogg")
        sf.write(path, bell(BASE * 2 ** (step / 12)), RATE, format="OGG", subtype="VORBIS")
        print("wrote", path)
    path = os.path.join(OUT, "bumper.ogg")
    sf.write(path, boing(), RATE, format="OGG", subtype="VORBIS")
    print("wrote", path)
    for name, fn in EFFECTS.items():
        path = os.path.join(OUT, name)
        sf.write(path, fn(), RATE, format="OGG", subtype="VORBIS")
        print("wrote", path)
