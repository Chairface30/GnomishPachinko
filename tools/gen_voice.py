#!/usr/bin/env python3
"""The Gnomish Pachinko announcer from ElevenLabs (Eleven v4). SPENDS CREDITS.

Every line the game can call is in LINES with the v4 audio tag that directs
its delivery (the model takes the tag as direction and does not say it).
The voice is the pachinko's own: Trixie's voices (the casino's Arabella and
the one in Get Out, Sugar) are never used here. Pick one with --voice <name
or id> (see --list-voices); without it the tool takes the first voice in your
library that is not one of hers, preferring one whose labels say male and
energetic or excited, and tells you which it chose.

Nothing is sent without --go. Each clip comes back as mp3, is decoded
(soundfile reads mp3), trimmed, peak levelled and written as Ogg Vorbis into
Sounds/Voice/<name>.ogg, where the game picks it up on its own. voiced.json
remembers what is done, so a run that hits the quota picks up where it
stopped; --force redoes clips anyway.

  set ELEVENLABS_API_KEY=sk_...        (PowerShell: $env:ELEVENLABS_API_KEY="sk_...")
  python tools/gen_voice.py --list-voices
  python tools/gen_voice.py                       # dry run: every line, the voice, the character count
  python tools/gen_voice.py --go --voice "Brian"  # generate every line not yet made
  python tools/gen_voice.py --go --only fever,level_cleared --force

Needs: pip install numpy soundfile
"""
import argparse, io, json, os, sys, time, urllib.error, urllib.request

import numpy as np
import soundfile as sf

API = "https://api.elevenlabs.io/v1"
MODEL_ID = os.environ.get("ELEVENLABS_MODEL_ID", "eleven_v4")
OUTPUT_FORMAT = "mp3_44100_128"
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "Sounds", "Voice")
DONE_FILE = os.path.join(HERE, "voiced.json")
RATE = 44100
PEAK = 0.89
SILENCE_DB = -45.0

# Trixie's voices, never the announcer's
EXCLUDE_NAMES = {"arabella"}
EXCLUDE_IDS = {"DODLEQrClDo8wCz460ld"}

# Settings tried in turn; newer models accept fewer of them.
SETTINGS = [
    {"stability": 0.4, "similarity_boost": 0.75, "style": 0.5, "use_speaker_boost": True},
    {"stability": 0.5, "similarity_boost": 0.75},
    {"stability": 0.5},
    None,
]

# The announcer: an excitable gnome engineer on a loudspeaker, Peggle-announcer
# energy. name -> text with its v4 audio tag.
LINES = {
    "level_start":     "[excited] Here we go!",
    "boss_start":      "[dramatic] Boss fight! Watch yourself!",
    "duel_start":      "[sly] A duel! Make every shot count.",
    "boss_turn":       "[mechanical, taunting] My move!",
    "ball_stolen":     "[gloating] Ha! That one's mine now.",
    "free_ball":       "[cheerful] Free ball!",
    "fever":           "[shouting, thrilled] Fever!",
    "level_cleared":   "[triumphant] Level cleared!",
    "three_stars":     "[ecstatic] Three stars! Magnificent!",
    "out_of_balls":    "[disappointed sigh] Awww... out of balls.",
    "out_of_plays":    "[gentle, apologetic] That's all your plays for today, friend.",
    "combo":           "[excited] Combo!",
    "combo_huge":      "[astonished, shouting] Unbelievable combo!",
    "last_one":        "[hushed, tense] Last one...",
    "total_miss":      "[deflated] Total miss.",
    "style":           "[impressed] Now that's style!",
    "gnome_bonus":     "[ecstatic, shouting] GNOME BONUS!",
    "hatched":         "[delighted] It hatched!",
    "gem":             "[pleased] Gem!",
    "boss_shield":     "[warning] Shields up!",
    "boss_down":       "[triumphant shout] Boss down!",
    "power_multiball": "[excited] Multiball!",
    "power_guide":     "[confident] Super Guide!",
    "power_blast":     "[shouting] Space Blast!",
    "power_fireball":  "[fierce] Fireball!",
    "power_spooky":    "[spooky, playful] Spooky Ball!",
    "power_pyramid":   "[grand] Pyramid!",
    "power_lightning": "[electric, excited] Chain Lightning!",
}


def api_get(path, key):
    req = urllib.request.Request(API + path, headers={"xi-api-key": key})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def voices(key):
    out = []
    for v in api_get("/voices", key).get("voices", []):
        labels = v.get("labels") or {}
        out.append({"id": v.get("voice_id"), "name": v.get("name", "?"),
                    "labels": " ".join(str(x) for x in labels.values()).lower()})
    return out


def allowed(v):
    return v["name"].strip().lower() not in EXCLUDE_NAMES and v["id"] not in EXCLUDE_IDS


def pick_voice(key, wanted):
    lib = [v for v in voices(key) if allowed(v)]
    if wanted:
        for v in lib:
            if v["id"] == wanted or v["name"].strip().lower() == wanted.strip().lower():
                return v
        if wanted in EXCLUDE_IDS or wanted.strip().lower() in EXCLUDE_NAMES:
            sys.exit(f"Voice '{wanted}' is one of Trixie's and is not used for the announcer.")
        if len(wanted) >= 16 and wanted.isalnum():
            # an id outside My Voices (a library voice): use it as given
            print(f"Voice id {wanted} is not in your library list; using it directly.")
            return {"id": wanted, "name": wanted, "labels": ""}
        sys.exit(f"Voice '{wanted}' not found (or it is one of Trixie's). Try --list-voices.")
    if not lib:
        sys.exit("No voice in the library besides Trixie's. Add one and pass --voice.")
    def score(v):
        s = 0
        if "male" in v["labels"] and "female" not in v["labels"]:
            s += 2
        for word in ("energetic", "excited", "upbeat", "announcer", "character"):
            if word in v["labels"]:
                s += 1
        return -s
    return sorted(lib, key=score)[0]


def tts(key, voice_id, text):
    url = f"{API}/text-to-speech/{voice_id}?output_format={OUTPUT_FORMAT}"
    last = None
    for settings in SETTINGS:
        body = {"text": text, "model_id": MODEL_ID}
        if settings:
            body["voice_settings"] = settings
        req = urllib.request.Request(url, data=json.dumps(body).encode("utf-8"), method="POST",
                                     headers={"xi-api-key": key, "Content-Type": "application/json",
                                              "Accept": "audio/mpeg"})
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            last = (e.code, e.read().decode("utf-8", "replace"))
            if e.code == 429:
                time.sleep(5)
            elif e.code not in (400, 422):
                break
    sys.exit(f"ElevenLabs refused ({last[0]}): {last[1]}")


def to_mono(data):
    return data.mean(axis=1) if data.ndim > 1 else data


def resample(data, src, dst):
    if src == dst:
        return data
    n = int(round(len(data) * dst / src))
    return np.interp(np.linspace(0, 1, n, endpoint=False), np.linspace(0, 1, len(data), endpoint=False), data)


def finish(mp3):
    data, rate = sf.read(io.BytesIO(mp3), dtype="float32")
    data = resample(to_mono(data), rate, RATE)
    thresh = 10 ** (SILENCE_DB / 20)
    loud = np.where(np.abs(data) > thresh)[0]
    if loud.size:
        data = data[max(0, loud[0] - int(0.02 * RATE)): min(len(data), loud[-1] + int(0.12 * RATE))].copy()
    fade = int(0.01 * RATE)
    if len(data) > 3 * fade:
        data[:fade] *= np.linspace(0, 1, fade)
        data[-fade:] *= np.linspace(1, 0, fade)
    peak = np.max(np.abs(data)) if data.size else 0
    if peak > 0:
        data = data * (PEAK / peak)
    return data.astype(np.float32)


def load_done():
    if os.path.exists(DONE_FILE):
        with open(DONE_FILE, encoding="utf-8") as f:
            return json.load(f)
    return {}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--go", action="store_true", help="actually call ElevenLabs (spends credits)")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--only", help="comma-separated line names")
    ap.add_argument("--voice", help="voice name or id (never Trixie's)")
    ap.add_argument("--list-voices", action="store_true")
    args = ap.parse_args()

    key = os.environ.get("ELEVENLABS_API_KEY")
    if args.list_voices:
        if not key:
            sys.exit("Set ELEVENLABS_API_KEY first.")
        for v in voices(key):
            mark = "" if allowed(v) else "   (Trixie: not for the announcer)"
            print(f"  {v['name']:<24} {v['id']}  {v['labels']}{mark}")
        return

    done = load_done()
    only = set(x.strip() for x in args.only.split(",")) if args.only else None
    todo = [(n, t) for n, t in LINES.items() if (only is None or n in only) and (args.force or n not in done)]
    chars = sum(len(t) for _, t in todo)
    print(f"Output: {OUT}")
    print(f"{len(todo)} line(s), {chars} characters, model {MODEL_ID}" + ("" if args.go else "  (dry run: add --go to generate)"))
    for n, t in todo:
        print(f"  {n:<18} {t}")
    if not args.go or not todo:
        return
    if not key:
        sys.exit("Set ELEVENLABS_API_KEY first (see the header of this file).")

    voice = pick_voice(key, args.voice)
    print(f"Voice: {voice['name']} ({voice['id']})")
    os.makedirs(OUT, exist_ok=True)
    for n, t in todo:
        print(f"-> {n}")
        data = finish(tts(key, voice["id"], t))
        path = os.path.join(OUT, n + ".ogg")
        sf.write(path, data, RATE, format="OGG", subtype="VORBIS")
        print(f"      wrote {os.path.basename(path)} {len(data) / RATE:.2f}s")
        done[n] = {"text": t, "voice": voice["name"], "at": time.strftime("%Y-%m-%d %H:%M")}
        with open(DONE_FILE, "w", encoding="utf-8") as f:
            json.dump(done, f, indent=2, sort_keys=True)
        time.sleep(0.4)
    print("done")


if __name__ == "__main__":
    main()
