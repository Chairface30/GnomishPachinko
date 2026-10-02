#!/usr/bin/env python3
"""Gnomish Pachinko's sound effects from ElevenLabs. SPENDS CREDITS.

Every effect the game plays is listed in EFFECTS with the prompt sent to
ElevenLabs' sound-effects model and the length asked for. The combo scale
is made from ONE generated note: its pitch is measured and the clip is
resampled to the sixteen steps of a C major scale over two octaves
(note1.ogg .. note16.ogg), so every note is the same instrument.

Nothing is sent without --go. Without it this lists what would be made and
how many seconds of audio that is. Each clip comes back as mp3, is decoded
(soundfile reads mp3), trimmed of leading and trailing silence, peak
levelled, and written as Ogg Vorbis into Sounds/ over the placeholder of the
same name. generated.json remembers what is done, so a run that hits the
quota picks up where it stopped; --force redoes clips anyway.

  set ELEVENLABS_API_KEY=sk_...        (PowerShell: $env:ELEVENLABS_API_KEY="sk_...")
  python tools/gen_sfx.py                 # dry run: every prompt and the total seconds
  python tools/gen_sfx.py --go            # generate every clip not yet generated
  python tools/gen_sfx.py --go --only peg,notes,combo
  python tools/gen_sfx.py --go --force    # regenerate everything

Every clip is the pachinko's own: nothing is shared with the casino.

Needs: pip install numpy soundfile
"""
import argparse, io, json, math, os, sys, time, urllib.error, urllib.request

import numpy as np
import soundfile as sf

API = "https://api.elevenlabs.io/v1/sound-generation"
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "Sounds")
DONE_FILE = os.path.join(HERE, "generated.json")
RATE = 44100
PEAK = 0.89                 # -1 dBFS
SILENCE_DB = -45.0

# name -> prompt, seconds asked for, options
#   loop: the clip must loop (the fanfare)
#   keep_tail: do not trim the end (ringing sounds)
EFFECTS = {
    # the ball and the pegs
    "launch":   ("A small spring-loaded cannon firing a steel ball, a short mechanical thunk with a quick whoosh, dry.", 0.6, {}),
    "peg1":     ("A steel ball tapping a glass peg, one short bright tick, no reverb.", 0.4, {}),
    "peg2":     ("A steel ball tapping a glass peg, one short bright tick, slightly higher, no reverb.", 0.4, {}),
    "peg3":     ("A steel ball tapping a glass peg, one short bright tick, slightly lower, no reverb.", 0.4, {}),
    "note_base": ("A single clean bright marimba note, one strike, short, dry, no reverb, no other sounds.", 0.8, {"keep_tail": True, "internal": True}),
    "orange":   ("A bright glassy ping with a tiny sparkle, a bonus target lighting up, short.", 0.6, {"keep_tail": True}),
    "clink":    ("A short bright metallic tink, a steel ball striking an iron peg, no reverb.", 0.3, {}),
    "bumper":   ("A springy pinball bumper boing, low and bouncy, short.", 0.4, {}),
    "lost":     ("A soft descending womp as a ball drops out of play, short and mild, cartoon.", 0.6, {}),
    "spooky":   ("A ghostly whoosh with a quick cartoon boo as a ball reappears, short.", 0.8, {}),
    # rewards
    "bucket":   ("An old mechanical cash register ka-ching: the key clacks, the drawer slams open with a loud brass bell ring, coins rattle in the tray, short.", 1.2, {"keep_tail": True}),
    "rim":      ("A steel ball striking the brass rim of a metal bucket, one short bright bell-like clang, metallic ring, no reverb.", 0.5, {"keep_tail": True}),
    "free_ball": ("A cheerful rising three-note chime, a bonus awarded, bright and short.", 0.9, {"keep_tail": True}),
    "combo":    ("A sparkling ascending arpeggio burst, a combo reward, bright and quick.", 1.0, {"keep_tail": True}),
    "bin":      ("A ball landing in a scoring slot with a satisfying bright ding, short.", 0.6, {"keep_tail": True}),
    # powers
    "power_multiball": ("A bright ping that splits into two echoing pings, a power-up, short.", 1.0, {"keep_tail": True}),
    "power_guide":     ("A soft futuristic targeting beep sequence locking on, short.", 1.0, {}),
    "power_fireball":  ("A fireball igniting with a whoosh and a crackle, short.", 1.0, {}),
    "power_spooky":    ("A spooky ghostly whoosh with a faint cartoon boo, a power-up, short.", 1.2, {}),
    "power_pyramid":   ("Heavy stone blocks sliding into place with a dusty thud, short.", 1.0, {}),
    "power_lightning": ("An electric charge building for a moment then a crackling zap, short.", 1.0, {}),
    "power_frenzy":    ("Three quick bouncy pops in a row followed by a bright sparkle, extra balls arriving, cheerful.", 1.2, {"keep_tail": True}),
    "blast":    ("A deep cartoon explosion with a quick boom and a short sparkle tail, no long rumble.", 1.2, {"keep_tail": True}),
    "zap":      ("A short crackling electric arc jumping between metal pins, zappy and bright.", 0.5, {}),
    "pyramid":  ("A ball bouncing hard off a stone ramp with a springy thump, short.", 0.4, {}),
    "web_shoot": ("A mechanical spider squirting sticky webbing, two quick wet thwips, short.", 0.7, {}),
    "web_catch": ("A ball caught in a sticky spider web, a stretchy elastic thwump, short.", 0.6, {}),
    "pyramid_crumble": ("Sandstone blocks cracking and a few stones crumbling off, gritty, short.", 0.8, {"keep_tail": True}),
    "pyramid_dust": ("A stone pyramid collapsing into rubble with a whooshing dusty rumble, falling grit, short.", 1.6, {"keep_tail": True}),
    # pieces
    "crack":    ("An eggshell cracking, one quick sharp snap, close-miked, short.", 0.4, {}),
    "hatch":    ("A tiny creature chirping once as it hatches from an egg, cute and quick.", 0.8, {}),
    "gem_free": ("A crystal coming loose from rock with a short glassy clink and a tumble.", 0.6, {}),
    "gem":      ("A sparkling crystal chime, three rising glassy notes, short.", 0.8, {"keep_tail": True}),
    # bosses
    "boss_hit":  ("A dull metallic thud, a ball hitting a hollow iron machine, with a brief rattle.", 0.5, {}),
    "boss_down": ("A small steam-powered machine breaking down: a clank, a hiss of steam, parts falling, cartoonish.", 1.5, {}),
    "shield":    ("A metallic force-field deflection, a short ringing clang.", 0.5, {"keep_tail": True}),
    "heal":      ("A low mechanical whir winding up ending in a soft chime, a machine repairing itself, short.", 0.8, {}),
    "hop":       ("A quick cartoon spring boing with a whoosh, something jumping away, short.", 0.5, {}),
    "boss_turn": ("A heavy mechanical ratchet winding and a clank, a machine taking its turn, short.", 0.8, {}),
    "unlock":    ("A padlock clicking open and a small cage of metal bars falling apart with a jingle, short.", 0.9, {}),
    # moments
    "start":    ("A short cheerful arcade level-start jingle, two bright rising notes.", 1.0, {"keep_tail": True}),
    "slowmo":   ("A dramatic slow-motion whoosh with a single heartbeat thump, short.", 0.9, {}),
    "mumble1": ("A cartoon character mumbling nonsense syllables like a muted trombone, wah wah, mrh hrm, friendly and quick, no words, variation 1.", 1.2, {}),
    "mumble2": ("A cartoon character mumbling nonsense syllables like a muted trombone, wah wah, mrh hrm, friendly and quick, no words, variation 2.", 1.2, {}),
    "mumble3": ("A cartoon character mumbling nonsense syllables like a muted trombone, wah wah, mrh hrm, friendly and quick, no words, variation 3.", 1.2, {}),
    "mumble4": ("A cartoon character mumbling nonsense syllables like a muted trombone, wah wah, mrh hrm, friendly and quick, no words, variation 4.", 1.2, {}),
    "mumble5": ("A cartoon character mumbling nonsense syllables like a muted trombone, wah wah, mrh hrm, friendly and quick, no words, variation 5.", 1.2, {}),
    "mumble6": ("A cartoon character mumbling nonsense syllables like a muted trombone, wah wah, mrh hrm, friendly and quick, no words, variation 6.", 1.2, {}),
    "grumble1": ("A low mechanical robot grumbling nonsense syllables like a muted tuba, mrh hrm, menacing, no words, variation 1.", 1.4, {}),
    "grumble2": ("A low mechanical robot grumbling nonsense syllables like a muted tuba, mrh hrm, menacing, no words, variation 2.", 1.4, {}),
    "grumble3": ("A low mechanical robot grumbling nonsense syllables like a muted tuba, mrh hrm, menacing, no words, variation 3.", 1.4, {}),
    "grumble4": ("A low mechanical robot grumbling nonsense syllables like a muted tuba, mrh hrm, menacing, no words, variation 4.", 1.4, {}),
    "grumble5": ("A low mechanical robot grumbling nonsense syllables like a muted tuba, mrh hrm, menacing, no words, variation 5.", 1.4, {}),
    "grumble6": ("A low mechanical robot grumbling nonsense syllables like a muted tuba, mrh hrm, menacing, no words, variation 6.", 1.4, {}),
    "suction":  ("A cartoon vacuum cleaner sucking air through a brass tube, a steady whooshing hoovering whoosh with a gentle wobble, seamless loop.", 2.0, {"loop": True}),
    "fever_music": ("A short exciting arcane fever music loop, bright synth arpeggios over driving drums and brass hits, building, about eight seconds.", 8.0, {"loop": True}),
    "fanfare":  ("A grand triumphant brass fanfare with timpani and a snare roll, celebratory, seamless loop.", 6.0, {"loop": True}),
    "fail":     ("A short sad trombone wah-wah, cartoon failure, brief.", 1.4, {"keep_tail": True}),
    "fever":    ("A triumphant bright sting with a shimmering rise, a goal completed, short.", 1.5, {"keep_tail": True}),
    "clear":    ("A short victorious arcade jingle, bright and happy, level cleared.", 2.5, {"keep_tail": True}),
}

# C major over two octaves from C4, the combo scale (one note per piece lit in a shot)
STEPS = [0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19, 21, 23, 24, 26]
BASE_HZ = 261.63

GROUPS = {
    "peg": ["peg1", "peg2", "peg3", "clink", "bumper", "orange"],
    "notes": ["note_base"],
    "powers": [n for n in EFFECTS if n.startswith("power_")] + ["blast", "zap", "pyramid", "pyramid_crumble", "pyramid_dust"],
    "boss": ["boss_hit", "boss_down", "shield", "heal", "hop", "web_shoot", "web_catch"],
}


def db(x):
    return 20 * math.log10(max(x, 1e-9))


def to_mono(data):
    return data.mean(axis=1) if data.ndim > 1 else data


def resample(data, src_rate, dst_rate):
    if src_rate == dst_rate:
        return data
    n = int(round(len(data) * dst_rate / src_rate))
    x_old = np.linspace(0, 1, len(data), endpoint=False)
    x_new = np.linspace(0, 1, n, endpoint=False)
    return np.interp(x_new, x_old, data)


def trim(data, keep_tail=False):
    thresh = 10 ** (SILENCE_DB / 20)
    loud = np.where(np.abs(data) > thresh)[0]
    if loud.size == 0:
        return data
    start = max(0, loud[0] - int(0.005 * RATE))
    end = len(data) if keep_tail else min(len(data), loud[-1] + int(0.04 * RATE))
    out = data[start:end].copy()
    fade = min(len(out) // 4, int(0.004 * RATE))
    if fade > 0:
        out[:fade] *= np.linspace(0, 1, fade)
        out[-fade:] *= np.linspace(1, 0, fade)
    return out


def level(data):
    peak = np.max(np.abs(data)) if data.size else 0
    if peak <= 0:
        return data
    return (data * (PEAK / peak)).astype(np.float32)


def make_loop(data, cross=0.1):
    n = int(cross * RATE)
    if len(data) < 3 * n:
        return data
    head, tail = data[:n].copy(), data[-n:].copy()
    ramp = np.linspace(0, 1, n)
    body = data[n:-n]
    joined = np.concatenate([body, tail * (1 - ramp) + head * ramp])
    return joined


def write(name, data):
    path = os.path.join(OUT, name + ".ogg")
    sf.write(path, data.astype(np.float32), RATE, format="OGG", subtype="VORBIS")
    return path


def estimate_pitch(data):
    """Fundamental of a plucked note by autocorrelation over its first 0.3 s."""
    seg = data[: int(0.3 * RATE)]
    seg = seg - seg.mean()
    if np.max(np.abs(seg)) <= 0:
        return None
    corr = np.correlate(seg, seg, mode="full")[len(seg) - 1:]
    lo, hi = int(RATE / 1500), int(RATE / 80)
    if hi >= len(corr):
        return None
    window = corr[lo:hi]
    # the first strong peak after the zero lag
    lag = lo + int(np.argmax(window))
    if corr[lag] < 0.2 * corr[0]:
        return None
    return RATE / lag


def pitch_shift(data, ratio):
    """Higher pitch = shorter clip: plain resampling, the marimba way."""
    n = int(round(len(data) / ratio))
    x_old = np.linspace(0, 1, len(data), endpoint=False)
    x_new = np.linspace(0, 1, n, endpoint=False)
    return np.interp(x_new, x_old, data)


def make_scale(base):
    f0 = estimate_pitch(base)
    if f0 is None or not (100 <= f0 <= 1500):
        print(f"      (pitch not found, treating the note as C4)")
        f0 = BASE_HZ
    else:
        print(f"      note measured at {f0:.0f} Hz")
    paths = []
    for i, step in enumerate(STEPS, start=1):
        target = BASE_HZ * 2 ** (step / 12)
        shifted = pitch_shift(base, target / f0)
        paths.append(write(f"note{i}", level(trim(shifted, keep_tail=True))))
    return paths


def fetch(key, prompt, secs, loop):
    # the model takes 0.5 s to 30 s; shorter clips are asked for at 0.5 s and trimmed
    body = {"text": prompt, "duration_seconds": max(0.5, min(30.0, secs)), "prompt_influence": 0.6}
    if loop:
        body["loop"] = True
    req = urllib.request.Request(API + "?output_format=mp3_44100_128", data=json.dumps(body).encode("utf-8"),
                                 method="POST", headers={"xi-api-key": key, "Content-Type": "application/json",
                                                         "Accept": "audio/mpeg"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            text = e.read().decode("utf-8", "replace")
            if e.code in (429, 500, 502, 503) and attempt < 2:
                time.sleep(3 * (attempt + 1))
                continue
            sys.exit(f"ElevenLabs refused ({e.code}): {text}")
    return None


def decode(mp3):
    data, rate = sf.read(io.BytesIO(mp3), dtype="float32")
    return resample(to_mono(data), rate, RATE)


def load_done():
    if os.path.exists(DONE_FILE):
        with open(DONE_FILE, encoding="utf-8") as f:
            return json.load(f)
    return {}


def save_done(done):
    with open(DONE_FILE, "w", encoding="utf-8") as f:
        json.dump(done, f, indent=2, sort_keys=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--go", action="store_true", help="actually call ElevenLabs (spends credits)")
    ap.add_argument("--force", action="store_true", help="redo clips already generated")
    ap.add_argument("--only", help="comma-separated names or groups: peg,notes,powers,boss,fanfare,...")
    args = ap.parse_args()

    wanted = None
    if args.only:
        wanted = set()
        for item in args.only.split(","):
            item = item.strip()
            wanted.update(GROUPS.get(item, [item]))

    done = load_done()
    todo = []
    for name, (prompt, secs, opts) in EFFECTS.items():
        if wanted is not None and name not in wanted:
            continue
        if not args.force and name in done:
            continue
        todo.append((name, prompt, secs, opts))

    total = sum(secs for _, _, secs, _ in todo)
    print(f"Output: {OUT}")
    print(f"{len(todo)} clip(s), {total:.1f} s of audio" + ("" if args.go else "  (dry run: add --go to generate)"))
    for name, prompt, secs, opts in todo:
        extra = " [loop]" if opts.get("loop") else ""
        extra += " -> note1..note16" if name == "note_base" else ""
        print(f"  {name:<16} {secs:>4.1f}s{extra}  {prompt}")
    if not args.go or not todo:
        return

    key = os.environ.get("ELEVENLABS_API_KEY")
    if not key:
        sys.exit("Set ELEVENLABS_API_KEY first (see the header of this file).")
    os.makedirs(OUT, exist_ok=True)
    for name, prompt, secs, opts in todo:
        print(f"-> {name}")
        mp3 = fetch(key, prompt, secs, opts.get("loop", False))
        data = decode(mp3)
        if opts.get("loop"):
            data = make_loop(level(data))
        else:
            data = level(trim(data, keep_tail=opts.get("keep_tail", False)))
        if name == "note_base":
            for p in make_scale(data):
                print("      wrote", os.path.basename(p))
        else:
            print("      wrote", os.path.basename(write(name, data)), f"{len(data) / RATE:.2f}s")
        done[name] = {"prompt": prompt, "secs": secs, "at": time.strftime("%Y-%m-%d %H:%M")}
        save_done(done)
        time.sleep(0.5)
    print("done")


if __name__ == "__main__":
    main()
