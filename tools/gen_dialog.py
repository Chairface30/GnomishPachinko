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

# speaker -> (ElevenLabs voice id, v4 delivery tag, machine?)
CAST = {
    "tink":   ("wo6udizrrtpIxWGp2qJk", "[excited, cheerful gnome inventor]", False),   # Northern Terry, the announcer
    "cog":    ("N2lVS1w4EtoT3dr4eOWO", "[smug, condescending older brother]", False),  # Callum
    "drake":  ("onwK4e9ZLuTAKqWW03F9", "[cold, flat, mechanical]", True),              # Daniel
    "golem":  ("pNInz6obpgDQGcFmaJgB", "[booming, robotic, shouting]", True),          # Adam
    "spider": ("SOYHLrjzK2X1ezoPC6cr", "[creepy, whispering, hissing]", True),         # Harry
    "boar":   ("IKne3meq5aSn9XLyUdCD", "[gruff, snorting, aggressive]", True),         # Charlie
    "yeti":   ("nPczCjzI2devNBz1zQrb", "[deep, slow, menacing]", True),                # Brian
}


def scripts():
    """The dialog lines straight from Dialog.lua."""
    import lupa
    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    rt.execute("GnomishPachinko = {}")
    rt.execute(open(os.path.join(ROOT, "Dialog.lua"), encoding="utf-8").read())
    D = rt.eval("GnomishPachinko.Dialog")
    out = []
    for sc in D.SCRIPTS.values():
        for i, line in enumerate(sc.lines.values(), 1):
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
        if want and name.rsplit("_", 1)[0] not in want:
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
        if is_machine:
            data = machine(data)
        sf.write(os.path.join(OUT, name + ".ogg"), data, RATE, format="OGG", subtype="VORBIS")
        done[name] = text
        json.dump(done, open(DONE_FILE, "w", encoding="utf-8"), indent=1, sort_keys=True)
        print(f"  wrote {name}.ogg {len(data) / RATE:.1f}s")
    print("done")


if __name__ == "__main__":
    main()
