"""Synthesize the mumbles the dialog plays: Sounds/mumble1..6.ogg (the
gnomes' chatter, high and quick) and Sounds/grumble1..6.ogg (the machines,
low and slow). A muted-trombone "wah wah, mrh hrm": a buzzy tone whose
pitch wanders in syllables, through a filter that opens and closes like a
mouth. Stand-ins until generated ones replace them (tools/gen_sfx.py has
prompts for mumble and grumble).

Run: python tools/make_mumbles.py        (pip install numpy soundfile)
"""
import os

import numpy as np
import soundfile as sf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Sounds")
RATE = 44100


def mumble(seed, base, syllables, syl_len, buzz):
    rng = np.random.default_rng(seed)
    out = []
    phase = 0.0
    for k in range(syllables):
        n = int(RATE * syl_len * rng.uniform(0.7, 1.3))
        t = np.arange(n) / RATE
        f0 = base * rng.uniform(0.85, 1.25)
        glide = rng.uniform(-0.25, 0.2)
        freq = f0 * (1 + glide * t / t[-1])
        ph = phase + 2 * np.pi * np.cumsum(freq) / RATE
        phase = ph[-1]
        # a buzzy reed: a few odd harmonics
        tone = sum(np.sin(ph * h) / h for h in (1, 2, 3, 5, 7)) * buzz + np.sin(ph) * (1 - buzz)
        # the "wah": a mouth that opens and closes (an amplitude and brightness swell)
        mouth = np.sin(np.pi * t / t[-1]) ** 1.5
        bright = 0.35 + 0.65 * mouth
        tone = tone * mouth
        # a soft one-pole low-pass that follows the mouth
        y = np.zeros_like(tone)
        acc = 0.0
        for i in range(len(tone)):
            acc += bright[i] * 0.25 * (tone[i] - acc)
            y[i] = acc
        out.append(y)
        out.append(np.zeros(int(RATE * rng.uniform(0.02, 0.07))))
    sig = np.concatenate(out)
    sig = sig / (np.max(np.abs(sig)) + 1e-9) * 0.6
    return sig.astype(np.float32)


if __name__ == "__main__":
    for i in range(1, 7):
        sf.write(os.path.join(OUT, "mumble%d.ogg" % i), mumble(100 + i, 260, 4 + i % 3, 0.16, 0.6), RATE, format="OGG", subtype="VORBIS")
        sf.write(os.path.join(OUT, "grumble%d.ogg" % i), mumble(200 + i, 95, 3 + i % 2, 0.24, 0.85), RATE, format="OGG", subtype="VORBIS")
        print("wrote mumble%d, grumble%d" % (i, i))
