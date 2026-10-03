#!/usr/bin/env python3
"""Voices every line of the dialog (Dialog.lua's SCRIPTS) with ElevenLabs.
SPENDS CREDITS.

Each speaker has a cast voice and a v4 delivery tag. The machines (the
bosses) are run through a ring modulator afterwards so they sound like
gnomish machinery. Clips go to Sounds/Voice/dialog/<script>_<line>.ogg,
where Dialog.lua plays them; a line whose clip is missing falls back to a
mumble. tools/dialog_voiced.json remembers what each clip said, so an
edited line is re-voiced and an unchanged one is not.

  python tools/gen_dialog.py            # dry run: every line, its voice, the characters
  python tools/gen_dialog.py --go       # voice what is new or changed
  python tools/gen_dialog.py --go --only intro,boss_drake --force

The key comes from ELEVENLABS_API_KEY or ~/.elevenlabs_key.
Needs: pip install numpy soundfile lupa
"""
import argparse, json, os, sys

import numpy as np
import soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from gen_voice import tts, finish, RATE  # noqa: E402

OUT = os.path.join(ROOT, "Sounds", "Voice", "dialog")
DONE_FILE = os.path.join(HERE, "dialog_voiced.json")

# speaker -> (ElevenLabs voice id, v4 delivery tag, effect): effect True runs
# the voice through the machine (ring modulator), "dragon" through the
# small-dragon filter
CAST = {
    "tink":   ("wo6udizrrtpIxWGp2qJk", "[excited, cheerful gnome inventor]", False),   # Northern Terry, the announcer
    "mekka":  ("JBFqnCBsd6RMkjVDRZzb", "[warm, proud, dignified gnome leader]", False),  # George
    "razzle": ("TX3LPaxmHKxFdv7VOQHJ", "[energetic, mischievous young gnome]", False),  # Liam
    "bink":   ("cgSgspJ2msm6clMCkdW9", "[bright, playful gnome apprentice]", False),    # Jessica
    "cog":    ("N2lVS1w4EtoT3dr4eOWO", "[smug, condescending older brother]", False),  # Callum
    "drake":  ("2EiwWnXFnvU5JabPnv8n", "[snarling, hissing, raspy little dragon]", "dragon"),  # Clyde
    "golem":  ("pNInz6obpgDQGcFmaJgB", "[booming, robotic, shouting]", "golem"),       # Adam
    "spider": ("SOYHLrjzK2X1ezoPC6cr", "[creepy, whispering, hissing]", "spider"),     # Harry
    "boar":   ("IKne3meq5aSn9XLyUdCD", "[gruff, snorting, aggressive]", "boar"),       # Charlie
    "yeti":   ("nPczCjzI2devNBz1zQrb", "[deep, slow, menacing]", "yeti"),              # Brian
}


def scripts():
    """The dialog lines straight from Dialog.lua."""
    import lupa
    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    rt.execute("GnomishPachinko = {}")
    rt.execute("GnomishPachinko.HOSTS = { {id='tink'}, {id='mekka'}, {id='razzle'}, {id='bink'} }")
    rt.execute(open(os.path.join(ROOT, "Dialog.lua"), encoding="utf-8").read())
    D = rt.eval("GnomishPachinko.Dialog")
    out = []
    hosts = [h.id for h in rt.eval("GnomishPachinko.HOSTS or {}").values()] or ["tink", "mekka", "razzle", "bink"]
    for sc in D.SCRIPTS.values():
        for i, line in enumerate(sc.lines.values(), 1):
            if line[1] == "host":
                # a narrator line: voiced once for every host
                for h in hosts:
                    out.append((f"{sc.key}_{i}_{h}", h, line[2]))
            else:
                out.append((f"{sc.key}_{i}", line[1], line[2]))
    return out


def machine(data):
    """A ring modulator and a touch of grit: a voice through gnomish machinery."""
    t = np.arange(len(data)) / RATE
    ring = data * np.sin(2 * np.pi * 55 * t)
    mixed = 0.55 * data + 0.6 * ring
    crushed = np.round(mixed * 48) / 48
    out = 0.7 * mixed + 0.3 * crushed
    peak = np.max(np.abs(out)) or 1
    return (out / peak * 0.89).astype(np.float32)


def dragon(data):
    """A small tin dragon: pitched up (a little creature), a throaty growl
    fluttering through it, and a light metallic ring (it is made of tin)."""
    rate = 1.22                                  # ~3.4 semitones up, a touch quicker
    n = int(len(data) / rate)
    src = np.arange(n) * rate
    up = np.interp(src, np.arange(len(data)), data)
    t = np.arange(n) / RATE
    growl = up * (1 + 0.35 * np.sin(2 * np.pi * 31 * t))
    ring = up * np.sin(2 * np.pi * 110 * t)
    out = 0.8 * growl + 0.25 * ring
    peak = np.max(np.abs(out)) or 1
    return (out / peak * 0.89).astype(np.float32)


def _shift(data, rate):
    """Resample: rate > 1 raises the pitch (and quickens), < 1 lowers it."""
    n = int(len(data) / rate)
    return np.interp(np.arange(n) * rate, np.arange(len(data)), data)


def _echo(data, taps):
    out = np.copy(data)
    for delay, gain in taps:
        k = int(delay * RATE)
        if k < len(out):
            out[k:] += gain * data[:-k]
    return out


def _norm(out):
    peak = np.max(np.abs(out)) or 1
    return (out / peak * 0.89).astype(np.float32)


def golem(data):
    """A big iron golem: pitched down, a heavy low ring, crushed bits, a
    metal-room echo."""
    d = _shift(data, 0.82)
    t = np.arange(len(d)) / RATE
    ring = d * np.sin(2 * np.pi * 38 * t)
    mixed = 0.5 * d + 0.7 * ring
    crushed = np.round(mixed * 24) / 24
    return _norm(_echo(0.6 * mixed + 0.4 * crushed, [(0.07, 0.35), (0.14, 0.18)]))


def spider(data):
    """An electric spider: a little higher, a fast flutter, a breathy hiss
    under it and a crackle of electricity."""
    d = _shift(data, 1.1)
    t = np.arange(len(d)) / RATE
    env = np.convolve(np.abs(d), np.ones(400) / 400, mode="same")
    rng = np.random.default_rng(7)
    hiss = rng.normal(0, 1, len(d)) * env * 0.9
    crackle = (rng.random(len(d)) < 0.002) * rng.normal(0, 1, len(d)) * env * 6
    flutter = d * (1 + 0.45 * np.sin(2 * np.pi * 13 * t))
    return _norm(flutter + hiss + crackle)


def boar(data):
    """A great armored boar: lower, a rough snorting growl, driven hard."""
    d = _shift(data, 0.9)
    t = np.arange(len(d)) / RATE
    growl = d * (1 + 0.5 * np.sin(2 * np.pi * 22 * t))
    return _norm(np.tanh(growl * 3.0))


def yeti(data):
    """A yeti in an ice cave: deep and slow, a long cold echo."""
    d = _shift(data, 0.78)
    return _norm(_echo(d, [(0.12, 0.45), (0.26, 0.3), (0.41, 0.18)]))


EFFECTS = {"dragon": None, "golem": golem, "spider": spider, "boar": boar, "yeti": yeti}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--go", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--only", help="comma-separated script keys (intro,boss_drake,...)")
    args = ap.parse_args()

    lines = scripts()
    want = set(args.only.split(",")) if args.only else None
    done = json.load(open(DONE_FILE, encoding="utf-8")) if os.path.exists(DONE_FILE) else {}
    todo = []
    for name, speaker, text in lines:
        if want and not any(name == w or name.startswith(w + "_") for w in want):
            continue
        if not args.force and done.get(name) == text and os.path.exists(os.path.join(OUT, name + ".ogg")):
            continue
        todo.append((name, speaker, text))
    chars = sum(len(t) for _, _, t in todo)
    print(f"{len(lines)} lines in Dialog.lua; {len(todo)} to voice, {chars} characters")
    for name, speaker, text in todo:
        print(f"  {name:22s} {speaker:7s} {text[:80]}")
    if not args.go:
        print("dry run: add --go to voice them")
        return
    key = os.environ.get("ELEVENLABS_API_KEY")
    if not key:
        path = os.path.expanduser("~/.elevenlabs_key")
        key = open(path, encoding="utf-8").read().strip() if os.path.exists(path) else None
    if not key:
        sys.exit("no ElevenLabs key: set ELEVENLABS_API_KEY or write ~/.elevenlabs_key")
    os.makedirs(OUT, exist_ok=True)
    for name, speaker, text in todo:
        voice, tag, is_machine = CAST.get(speaker, CAST["tink"])
        data = finish(tts(key, voice, f"{tag} {text}"))
        if is_machine == "dragon":
            data = dragon(data)
        elif isinstance(is_machine, str) and EFFECTS.get(is_machine):
            data = EFFECTS[is_machine](data)
        elif is_machine:
            data = machine(data)
        sf.write(os.path.join(OUT, name + ".ogg"), data, RATE, format="OGG", subtype="VORBIS")
        done[name] = text
        json.dump(done, open(DONE_FILE, "w", encoding="utf-8"), indent=1, sort_keys=True)
        print(f"  wrote {name}.ogg {len(data) / RATE:.1f}s")
    print("done")


if __name__ == "__main__":
    main()
