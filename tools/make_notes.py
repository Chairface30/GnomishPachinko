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


def fanfare(secs=6.0):
    """A placeholder clearing fanfare: a brass-like chord progression over a
    drum roll, ending on the chord it starts on so it loops."""
    t = np.linspace(0, secs, int(RATE * secs), endpoint=False)
    out = np.zeros_like(t)
    chords = [(261.63, 329.63, 392.00, 523.25), (349.23, 440.00, 523.25, 698.46),
              (392.00, 493.88, 587.33, 783.99), (261.63, 329.63, 392.00, 523.25)]
    beat = secs / len(chords)
    for i, chord in enumerate(chords):
        start = i * beat
        seg = (t >= start) & (t < start + beat)
        tt = t[seg] - start
        env = np.minimum(1.0, tt / 0.03) * (1.0 - 0.3 * tt / beat)
        for k, f in enumerate(chord):
            brass = (np.sin(2 * math.pi * f * tt) + 0.5 * np.sin(2 * math.pi * 2 * f * tt)
                     + 0.3 * np.sin(2 * math.pi * 3 * f * tt) + 0.15 * np.sin(2 * math.pi * 4 * f * tt))
            out[seg] += brass * env * (1.0 if k == 3 else 0.7)
        # a bass note under each chord
        out[seg] += 0.8 * np.sin(2 * math.pi * chord[0] / 2 * tt) * env
    # drum roll: bursts of noise every eighth
    rng = np.random.default_rng(21)
    noise = rng.standard_normal(t.size)
    roll = np.zeros_like(t)
    step = beat / 4
    for k in range(int(secs / step)):
        s0 = k * step
        roll += (t >= s0) * np.exp(-np.maximum(0, t - s0) * 40) * (1.2 if k % 4 == 0 else 0.6)
    out += 0.35 * noise * roll
    return norm(out, 0.6)


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


def tone_seq(freqs, each=0.12, decay=9, level_=0.5):
    """A quick run of bell tones, one after another."""
    total = each * len(freqs) + 0.35
    t = np.linspace(0, total, int(RATE * total), endpoint=False)
    out = np.zeros_like(t)
    for i, f in enumerate(freqs):
        start = i * each
        tt = np.maximum(0, t - start)
        out += (np.sin(2 * math.pi * f * tt) + 0.4 * np.sin(2 * math.pi * 2 * f * tt)) * np.exp(-tt * decay) * (t >= start)
    return norm(out, level_)


def sweep(f0, f1, secs=0.5, decay=6, level_=0.5):
    t = np.linspace(0, secs, int(RATE * secs), endpoint=False)
    freq = f0 + (f1 - f0) * t / secs
    phase = 2 * math.pi * np.cumsum(freq) / RATE
    return norm(np.sin(phase) * np.exp(-t * decay) * np.minimum(1.0, t / 0.005), level_)


def kaching(secs=1.1):
    """A cash register: the drawer latch clacks, the bell rings (inharmonic
    partials, not a clean tone), and a handful of coins ping and rattle."""
    rng = np.random.default_rng(17)
    t = np.linspace(0, secs, int(RATE * secs), endpoint=False)
    out = np.zeros_like(t)
    # the latch: a sharp click of filtered noise
    click = rng.standard_normal(t.size) * np.exp(-t * 180)
    out += 0.9 * click
    # the bell: struck at 60 ms, bell-like partial ratios with a bright edge
    tb = np.maximum(0, t - 0.06)
    bell = np.zeros_like(t)
    for ratio, amp, dec in ((1.0, 1.0, 5), (2.76, 0.6, 7), (5.40, 0.4, 10), (8.93, 0.25, 14), (1.02, 0.5, 5)):
        bell += amp * np.sin(2 * math.pi * 1180 * ratio * tb) * np.exp(-tb * dec)
    bell *= (t >= 0.06) * np.minimum(1.0, tb / 0.002)
    out += 0.8 * bell
    # the drawer sliding open: a short low rumble of noise
    k = 40
    rumble = np.convolve(rng.standard_normal(t.size), np.ones(k) / k, mode="same")
    rumble *= ((t >= 0.08) & (t < 0.30)) * np.exp(-np.maximum(0, t - 0.08) * 12)
    out += 1.4 * rumble
    # coins: a scatter of tiny metallic pings over the next half second
    for i in range(9):
        start = 0.12 + i * 0.045 + rng.uniform(0, 0.02)
        f = rng.uniform(3200, 6400)
        tt = np.maximum(0, t - start)
        out += 0.22 * (np.sin(2 * math.pi * f * tt) + 0.5 * np.sin(2 * math.pi * f * 1.5 * tt)) * np.exp(-tt * 45) * (t >= start)
    return norm(out, 0.6)


STANDINS = {
    "bucket.ogg": kaching,
    "rim.ogg": lambda: tone_seq((1900, 1400), each=0.03, decay=28),
    "boss_turn.ogg": lambda: tone_seq((110, 110, 110, 90), each=0.09, decay=16, level_=0.6),
    "unlock.ogg": lambda: tone_seq((1400, 1100, 1800, 2200, 2600), each=0.06, decay=12),
    "combo.ogg": lambda: tone_seq((523, 659, 784, 1047, 1319), each=0.07),
    "bin.ogg": lambda: tone_seq((880,), decay=6),
    "lost.ogg": lambda: sweep(300, 90, 0.5, 5),
    "spooky.ogg": lambda: sweep(200, 600, 0.6, 4),
    "fail.ogg": lambda: tone_seq((330, 311, 294, 262), each=0.25, decay=4),
    "start.ogg": lambda: tone_seq((523, 784), each=0.18, decay=5),
    "shield.ogg": lambda: tone_seq((1200, 900), each=0.05, decay=14),
    "heal.ogg": lambda: sweep(200, 900, 0.6, 3),
    "hop.ogg": lambda: sweep(400, 1200, 0.3, 8),
    "gem_free.ogg": lambda: tone_seq((1568, 1319), each=0.06, decay=12),
    "pyramid.ogg": lambda: sweep(180, 90, 0.3, 10),
    "power_multiball.ogg": lambda: tone_seq((880, 880, 1109, 1109), each=0.09),
    "power_guide.ogg": lambda: tone_seq((660, 660, 990), each=0.1, decay=12),
    "power_fireball.ogg": lambda: sweep(120, 700, 0.6, 4),
    "power_spooky.ogg": lambda: sweep(500, 150, 0.8, 3),
    "power_pyramid.ogg": lambda: sweep(140, 60, 0.6, 5),
    "power_lightning.ogg": lambda: sweep(300, 2400, 0.4, 5),
}


EFFECTS = {
    "clink.ogg": clink, "crack.ogg": crack, "hatch.ogg": hatch, "gem.ogg": gem,
    "boss_hit.ogg": boss_hit, "boss_down.ogg": boss_down, "zap.ogg": zap, "blast.ogg": blast,
    "slowmo.ogg": slowmo, "fanfare.ogg": fanfare,
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
    for name, fn in STANDINS.items():
        path = os.path.join(OUT, name)
        sf.write(path, fn(), RATE, format="OGG", subtype="VORBIS")
        print("wrote", path)
