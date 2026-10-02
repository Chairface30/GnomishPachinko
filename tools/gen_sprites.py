"""Generate the art slots of Gnomish Pachinko with AutoSprite, in the style
of the hand-made sprite sheet.

Four ways a slot gets its picture, cheapest first:

  sheet   cut straight off the sprite sheet (tools/sheets/pegs.json says
          which sprite is which): no credits
  derive  made locally from another slot (a pressed button is the button
          darkened, the silver key is the gold key desaturated, the later
          splash frames are the first one spread out): no credits
  pose    a sprite from the sheet is uploaded as a non-humanoid "character"
          (free) and AutoSprite draws a new state of the same object from a
          prompt ("the same orb stretched into a bar"): 3 credits each,
          keeps the sheet's exact look
  asset   a new object from a prompt (generate_asset_preview, ultra
          quality) saved as an asset, background removed: 2 credits each

Everything goes through AutoSprite's MCP endpoint (the fullest surface of
their API) with the key in ~/.autosprite_key. Results are recorded in
tools/generated_sprites.json (asset ids, pose jobs, URLs), so a second run
only does what is missing; --force redoes a slot.

Run: python tools/gen_sprites.py --sheet path/to/sheet.png          plan only
     python tools/gen_sprites.py --sheet path/to/sheet.png --go     spend credits
     python tools/gen_sprites.py --go --only boss_drake power_blast  some slots
     python tools/gen_sprites.py --stage asset --go                  assets only (no sheet needed)

Needs: pip install pillow lupa numpy
"""
import argparse
import io
import json
import os
import sys
import time
import urllib.error
import urllib.request
from collections import deque

from PIL import Image, ImageEnhance

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Textures")
TOOLS = os.path.dirname(os.path.abspath(__file__))
RECORD = os.path.join(TOOLS, "generated_sprites.json")
sys.path.insert(0, TOOLS)
from make_textures import read_slots  # noqa: E402
from cut_sheet import islands, fit, base_of, clean_crop, boxes_by_slot  # noqa: E402

MCP_URL = "https://www.autosprite.io/api/mcp"
KEY_FILE = os.path.expanduser("~/.autosprite_key")

# One look for everything new. Kept short: a description is 200 chars at most.
STYLE = "glossy cartoon game sprite, soft shading, bright specular highlight, no outline, centered, white background"
ART_STYLE = "painted"

# ---------------------------------------------------------------- the plan

# pose: base slot (uploaded from the sheet) + prompt. asset: category + description.
# derive: a function of other slots. sheet: cut from the sheet map. tool: keep the
# generated placeholder (tinted technical textures the game colours itself).
PLAN = {}


def sheet(*names):
    for n in names:
        PLAN[n] = {"how": "sheet"}


def pose(name, base, prompt):
    PLAN[name] = {"how": "pose", "base": base, "prompt": prompt}


def asset(name, category, description, keep_bg=False):
    PLAN[name] = {"how": "asset", "category": category, "description": description, "keep_bg": keep_bg}


def derive(name, source, op, **kw):
    PLAN[name] = {"how": "derive", "source": source, "op": op, **kw}


def tool(*names):
    for n in names:
        PLAN[n] = {"how": "tool"}


sheet("peg_blue", "peg_orange", "peg_green", "peg_purple",
      "peg_blue_lit", "peg_orange_lit", "peg_green_lit", "peg_purple_lit",
      "peg_blue_gone", "peg_orange_gone", "peg_green_gone",
      "spark1", "spark2", "plate", "callout_fever")
asset("bucket", "prop", "gnomish brass catching bucket on little wheels with gears and rivets, open top, front view, " + STYLE)
asset("bucket_splash1", "effect", "burst of white sparks and little brass gear bits flying upward, catch effect, " + STYLE)
# the sheet's button says START; the game writes its own labels, so the button is drawn blank
asset("button_green", "prop", "wide rounded glossy green button with a dark green bevelled edge, blank, no text, four times as wide as tall, " + STYLE)
pose("peg_purple_gone", "peg_purple", "the same purple orb broken into five separate flying glass shards with clear gaps between them and a few small sparks, mid-burst, nothing else")
for c in ("blue", "orange", "green", "purple"):
    pose("brick_%s" % c, "peg_%s" % c, "the same %s glossy material shaped as a wide rounded rectangular bar, twice as wide as tall, lit from the top, no orb" % c)
    pose("brick_%s_lit" % c, "peg_%s_lit" % c, "the same glowing %s material shaped as a wide rounded rectangular bar twice as wide as tall, bright halo, no orb" % c)
    pose("brick_%s_gone" % c, "peg_%s_gone" % c, "the same %s glass shards, now from a broken wide rounded bar: six separate rectangular fragments flying apart with gaps between them and small sparks, no orb" % c)
asset("ball", "item", "small chrome steel ball, mirror polished, bright highlight, " + STYLE)
pose("ball_fire", "ball", "the same ball wreathed in orange fire, flames trailing")
pose("ball_electric", "ball", "the same ball crackling with blue electricity, small lightning arcs around it")
pose("ball_rainbow", "ball", "the same ball with a rainbow sheen swirling over its surface")
pose("ball_wing", "ball", "the same ball with two small white feathered wings spread either side")
pose("ball_spooky", "ball", "the same ball as a pale green translucent ghost with two dark eyes")
derive("ball_small", "ball", "copy")
asset("egg", "item", "cream speckled egg, slightly pointed top, " + STYLE)
pose("egg_cracked", "egg", "the same egg with a jagged crack across its shell")
pose("egg_hatched", "egg", "the same egg broken open with a tiny yellow chick peeking out of the bottom half")
asset("gem", "item", "faceted cut cyan gem, hexagonal, sparkling, " + STYLE)
asset("key_gold", "item", "ornate old-fashioned gold key, round bow at the top, two teeth, " + STYLE)
derive("key_silver", "key_gold", "silver")
asset("cage_gold", "prop", "one horizontal gold cage bar with three vertical slats, metal, twice as wide as tall, " + STYLE)
derive("cage_silver", "cage_gold", "silver")
asset("rail", "prop", "horizontal riveted grey steel bar with end caps, twice as wide as tall, " + STYLE)
asset("block", "prop", "round riveted grey steel plate, solid, " + STYLE)
asset("bumper", "item", "round pink candy bumper with a white star in the middle, glossy, " + STYLE)
for bid, look in (("drake", "tin dragon face, steel, cold eyes"), ("golem", "brass golem face, square eyes, bolts"),
                  ("spider", "green mechanical spider face, four eyes"), ("boar", "red mechano-boar face, tusks"),
                  ("yeti", "ice-blue cog yeti face, fangs")):
    asset("boss_" + bid, "character", "round mechanical boss face, gear teeth round the rim, %s, " % look + STYLE)
asset("launcher_barrel", "prop", "copper cannon barrel pointing straight down, brass rings, vertical, " + STYLE)
asset("launcher_hub", "prop", "round copper pivot plate with six rivets, " + STYLE)
derive("launcher_flash", "spark1", "copy")
derive("bucket_splash2", "bucket_splash1", "spread", amount=1.25)
derive("bucket_splash3", "bucket_splash1", "spread", amount=1.5)
derive("bucket_splash4", "bucket_splash1", "spread", amount=1.75, fade=0.6)
asset("fever_bucket", "prop", "wide gnomish brass hopper cup with rivets and a small gear at each end, open top, front view, four times as wide as tall, " + STYLE)
derive("fever_bucket_lit", "fever_bucket", "bright")
for pid, look in (("multiball", "two chrome balls"), ("guide", "a dotted aiming arc"), ("blast", "an orange starburst explosion"),
                  ("fireball", "a flaming orange ball"), ("spooky", "a pale green ghost"), ("pyramid", "a golden trapezoid ramp"),
                  ("lightning", "a blue lightning bolt"), ("frenzy", "a winged chrome ball with sparkles")):
    asset("power_" + pid, "item", "round game power icon on a copper disc: %s, " % look + STYLE)
for iid, look in (("ring", "an orange ring of fire"), ("rainbow", "a rainbow arc"), ("green", "a green orb with a plus sign")):
    asset("item_" + iid, "item", "round game power-up icon on a copper disc: %s, " % look + STYLE)
for gid, look in (("orange", "an orange orb"), ("egg", "a cream egg"), ("gem", "a cyan gem"), ("boss", "a red mechanical face"),
                  ("duel", "a green orb and a red orb side by side"), ("longshot", "two orange orbs far apart joined by a line")):
    asset("goal_" + gid, "item", "small round game objective icon: %s, " % look + STYLE)
asset("frame_bg", "texture", "square copper and brass machine plate with riveted dark bevelled border all round, even border, flat centre", keep_bg=True)
asset("card", "texture", "square dark navy parchment card with an ornate gold bevelled border all round, even border, plain centre", keep_bg=True)
derive("button_orange", "button_green", "hue", hue=28)
derive("button_grey", "button_green", "grey")
for c in ("green", "orange", "grey"):
    derive("button_%s_down" % c, "button_%s" % c, "darken", amount=0.72)
derive("gauge", "plate", "copy")
derive("gauge_fill", "button_green", "rainbow")
asset("fever_balloon", "item", "round inflated glossy purple rubber balloon bumper with a brass band and rivets, " + STYLE)
asset("logo", "item", "one very wide horizontal game logo banner: the words GNOMISH PACHINKO in chunky glossy gold letters across a long copper plate with gears at both ends, wide aspect, " + STYLE)
asset("portrait_frame", "prop", "round ornate copper frame ring with rivets, hollow empty centre, thick, " + STYLE)
asset("banner", "prop", "long horizontal navy ribbon banner with gold edges and notched ends, eight times as wide as tall, " + STYLE)
asset("map_node", "item", "round carved wooden level button, brown, " + STYLE)
asset("map_node_done", "item", "round carved wooden level button with a green gem centre, " + STYLE)
asset("map_node_locked", "item", "round grey stone level button with an iron padlock, " + STYLE)
asset("map_node_boss", "item", "round red iron level button with a skull, " + STYLE)
BIOMES = [('Elwynn Forest', 'sunlit oak forest with meadows, a stream and a farmhouse'),
          ('Durotar', 'red desert of dry earth, cacti and rust-coloured canyons'),
          ('Dun Morogh', 'snowy pine mountains with frozen lakes and stone huts'),
          ('Mulgore', 'golden rolling grassland with mesas and totem poles'),
          ('Teldrassil', 'moonlit forest of giant purple-leafed trees and glowing lanterns'),
          ('Tirisfal Glades', 'gloomy dead forest with graveyards, fog and crooked trees'),
          ('Westfall', 'dry golden farmland with windmills and haystacks under a hazy sky'),
          ('Loch Modan', 'a calm lake among green hills with pines and a stone dam'),
          ('Darkshore', 'dark pine coast with moonlit cliffs and crashing waves'),
          ('Silverpine Forest', 'gray misty pine forest with mossy stones'),
          ('The Barrens', 'dry savanna with acacia trees, red earth and distant mesas'),
          ('Redridge Mountains', 'red cliffs round a blue lake with pines'),
          ('Stonetalon Mountains', 'rocky crags with a burnt forest and logging camps'),
          ('Ashenvale', 'lush ancient forest in purple and green with moonwells'),
          ('Duskwood', 'dark haunted forest of crooked bare trees and fog'),
          ('Wetlands', 'misty marsh with reeds, pools and mossy boulders'),
          ('Hillsbrad Foothills', 'green rolling foothills with farms and stone walls'),
          ('Thousand Needles', 'towering red rock spires rising from a dry canyon floor'),
          ('Alterac Mountains', 'snowy mountains with ruined stone walls and pines'),
          ('Arathi Highlands', 'windswept highland moors with standing stones'),
          ('Desolace', 'gray barren wasteland with giant bones and dust'),
          ('Stranglethorn Vale', 'dense tropical jungle with vine-covered ruins'),
          ('Dustwallow Marsh', 'dark swamp with mangroves, mist and still black water'),
          ('Badlands', 'cracked red desert canyons under a hot sky'),
          ('Swamp of Sorrows', 'green swamp with giant mushrooms and glowing pools'),
          ('Feralas', 'lush jungle of giant trees with waterfalls and ruins'),
          ('The Hinterlands', 'misty pine highlands with troll stone ruins'),
          ('Tanaris', 'sand dunes desert with an oasis and palm trees'),
          ('Searing Gorge', 'lava flows, ash and molten rock under a smoky sky'),
          ('Azshara', 'autumn forest in red and gold with ruins on sea cliffs'),
          ('Blasted Lands', 'red scorched wasteland with cracked earth and a dark stone portal'),
          ("Un'Goro Crater", 'prehistoric jungle crater with a volcano and giant ferns'),
          ('Felwood', 'corrupted green forest with glowing fungus and twisted trees'),
          ('Burning Steppes', 'volcanic black rock with lava rivers and ash'),
          ('Western Plaguelands', 'sickly brown blighted fields with dead trees'),
          ('Eastern Plaguelands', 'dead orange blighted land with plague cauldrons and ruins'),
          ('Winterspring', 'snowy valley with frozen lakes and tall pines under the moon'),
          ('Deadwind Pass', 'dark stormy mountain pass with a ruined tower'),
          ('Silithus', 'orange desert with giant insect hives and sand'),
          ('Moonglade', 'serene moonlit glade with a still lake and soft lights')]
for i, (zone, look) in enumerate(BIOMES, 1):
    asset("map_bg_%d" % i, "texture", "tall painted fantasy landscape, %s, winding dirt path, soft, low contrast, portrait, level map backdrop" % look, keep_bg=True)
    asset("field_bg_%d" % i, "texture", "tall very low contrast game board backdrop: %s at dusk, dark, no objects, portrait" % look, keep_bg=True)
    asset("field_boss_%d" % i, "texture", "tall very low contrast boss arena backdrop: %s at night, ominous red glow, dark, no objects, portrait" % look, keep_bg=True)
asset("minimap", "item", "round purple glossy button with gold letters GP, " + STYLE)
derive("spark3", "spark1", "spread", amount=1.3, fade=0.8)
derive("spark4", "spark2", "spread", amount=1.4, fade=0.6)
asset("confetti", "effect", "scattered colourful confetti bits mid-air, " + STYLE)
asset("firework", "effect", "radial firework burst, white centre, golden rays, " + STYLE)
tool("peg", "brick", "key", "boss", "ring", "rim", "crack", "dot", "star", "blast", "pyramid", "icon", "trail", "glow_soft")


# ---------------------------------------------------------------- MCP client

class AutoSprite:
    def __init__(self, key):
        self.key = key
        self.sid = None
        self.rid = 0
        self.init()

    def _post(self, method, params):
        self.rid += 1
        body = json.dumps({"jsonrpc": "2.0", "id": self.rid, "method": method, "params": params}).encode()
        req = urllib.request.Request(MCP_URL, data=body, method="POST")
        req.add_header("Authorization", "Bearer " + self.key)
        req.add_header("Content-Type", "application/json")
        req.add_header("Accept", "application/json, text/event-stream")
        if self.sid:
            req.add_header("Mcp-Session-Id", self.sid)
        for attempt in range(4):
            try:
                with urllib.request.urlopen(req, timeout=120) as r:
                    self.sid = r.headers.get("Mcp-Session-Id") or self.sid
                    raw = r.read().decode("utf-8", "replace")
                    if "text/event-stream" in r.headers.get("Content-Type", ""):
                        msgs = [json.loads(l[5:].strip()) for l in raw.splitlines() if l.startswith("data:")]
                        return msgs[-1] if msgs else None
                    return json.loads(raw) if raw.strip() else None
            except urllib.error.HTTPError as e:
                text = e.read().decode("utf-8", "replace")
                if e.code == 429 and attempt < 3:
                    wait = int(e.headers.get("Retry-After", "30") or 30)
                    print(f"    rate limited, waiting {wait}s")
                    time.sleep(wait)
                    continue
                raise RuntimeError(f"HTTP {e.code}: {text[:300]}")
        raise RuntimeError("gave up after retries")

    def init(self):
        self._post("initialize", {"protocolVersion": "2025-03-26", "capabilities": {}, "clientInfo": {"name": "gnomish-pachinko", "version": "1.0"}})
        try:
            self._post("notifications/initialized", {})
        except Exception:
            pass

    def call(self, tool, **args):
        res = self._post("tools/call", {"name": tool, "arguments": args})
        if not res:
            raise RuntimeError(f"{tool}: empty response")
        if "error" in res:
            raise RuntimeError(f"{tool}: {res['error']}")
        result = res.get("result", {})
        if result.get("isError"):
            raise RuntimeError(f"{tool}: " + " ".join(c.get("text", "") for c in result.get("content", [])))
        texts = [c.get("text", "") for c in result.get("content", []) if c.get("type") == "text"]
        for t in texts:
            t = t.strip()
            if t.startswith("{") or t.startswith("["):
                try:
                    return json.loads(t)
                except Exception:
                    pass
        return {"text": "\n".join(texts)}

    def rest_get(self, path):
        """The REST API (x-api-key): pose jobs (cf_...) are only visible here."""
        req = urllib.request.Request("https://www.autosprite.io/api/v1" + path)
        req.add_header("x-api-key", self.key)
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read().decode("utf-8", "replace"))

    def upload(self, path):
        info = self.call("request_upload_url", fileName=os.path.basename(path), contentType="image/png")
        url, key = info["uploadUrl"], info["uploadKey"]
        data = open(path, "rb").read()
        req = urllib.request.Request(url, data=data, method="PUT")
        req.add_header("Content-Type", "image/png")
        with urllib.request.urlopen(req, timeout=120) as r:
            r.read()
        return key


def download(url):
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=120) as r:
        return Image.open(io.BytesIO(r.read())).convert("RGBA")


# ---------------------------------------------------------------- image helpers

def strip_background(img, tol=48):
    """If the picture has no transparency, flood the background colour
    (sampled at the corners) away from the edges."""
    if img.getextrema()[3][0] < 255:
        return img
    w, h = img.size
    px = img.load()
    corners = [px[0, 0], px[w - 1, 0], px[0, h - 1], px[w - 1, h - 1]]
    bg = tuple(sum(c[i] for c in corners) // 4 for i in range(3))

    def near(p):
        return abs(p[0] - bg[0]) + abs(p[1] - bg[1]) + abs(p[2] - bg[2]) <= tol * 3

    seen = bytearray(w * h)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if near(px[x, y]) and not seen[y * w + x]:
                seen[y * w + x] = 1
                q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if near(px[x, y]) and not seen[y * w + x]:
                seen[y * w + x] = 1
                q.append((x, y))
    while q:
        x, y = q.popleft()
        px[x, y] = (0, 0, 0, 0)
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and near(px[nx, ny]):
                seen[ny * w + nx] = 1
                q.append((nx, ny))
    return img


def crop_content(img, pad=2):
    box = img.split()[-1].getbbox()
    if not box:
        return img
    x0, y0, x1, y1 = box
    return img.crop((max(0, x0 - pad), max(0, y0 - pad), min(img.width, x1 + pad), min(img.height, y1 + pad)))


def op_silver(img):
    g = ImageEnhance.Color(img).enhance(0.0)
    px = g.load()
    for y in range(g.height):
        for x in range(g.width):
            r, gg, b, a = px[x, y]
            px[x, y] = (min(255, int(r * 0.9 + 20)), min(255, int(gg * 0.95 + 24)), min(255, int(b * 1.05 + 34)), a)
    return g


def op_gold(img):
    g = ImageEnhance.Color(img).enhance(0.0)
    px = g.load()
    for y in range(g.height):
        for x in range(g.width):
            r, gg, b, a = px[x, y]
            px[x, y] = (min(255, int(r * 1.1 + 40)), min(255, int(gg * 0.9 + 20)), int(b * 0.35), a)
    return g


def op_grey(img):
    g = ImageEnhance.Color(img).enhance(0.15)
    return ImageEnhance.Brightness(g).enhance(0.8)


def op_hue(img, hue):
    hsv = img.convert("RGB").convert("HSV")
    px = hsv.load()
    for y in range(hsv.height):
        for x in range(hsv.width):
            h, s, v = px[x, y]
            px[x, y] = (int(hue * 255 / 360), s, v)
    out = hsv.convert("RGB").convert("RGBA")
    out.putalpha(img.split()[-1])
    return out


def op_rainbow(img):
    out = img.copy()
    px = out.load()
    w = out.width
    for y in range(out.height):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a:
                t = x / max(1, w - 1) * 0.8
                rr = max(0.0, min(1.0, abs(t * 6 - 3) - 1))
                gg = max(0.0, min(1.0, 2 - abs(t * 6 - 2)))
                bb = max(0.0, min(1.0, 2 - abs(t * 6 - 4)))
                v = (r + g + b) / 3 / 255 * 0.6 + 0.4
                px[x, y] = (int(255 * rr * v), int(255 * gg * v), int(255 * bb * v), a)
    return out


def op_spread(img, amount=1.3, fade=1.0):
    w, h = img.size
    big = img.resize((max(1, int(w * amount)), max(1, int(h * amount))), Image.LANCZOS)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.alpha_composite(big, ((w - big.width) // 2, (h - big.height) // 2))
    if fade < 1:
        a = out.split()[-1].point(lambda v: int(v * fade))
        out.putalpha(a)
    return out


def op_darken(img, amount=0.72):
    return ImageEnhance.Brightness(img).enhance(amount)


def op_bright(img, amount=1.45):
    """Lit: brighter and warmer, toward white-gold."""
    out = ImageEnhance.Brightness(img).enhance(amount)
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            if a:
                px[x, y] = (min(255, r + 30), min(255, g + 20), b, a)
    return out


OPS = {"copy": lambda i: i, "silver": op_silver, "gold": op_gold, "grey": op_grey, "hue": op_hue, "rainbow": op_rainbow,
       "spread": op_spread, "darken": op_darken, "bright": op_bright}


# ---------------------------------------------------------------- the run

def load_record():
    if os.path.exists(RECORD):
        return json.load(open(RECORD, encoding="utf-8"))
    return {"characters": {}, "slots": {}}


def save_record(rec):
    json.dump(rec, open(RECORD, "w", encoding="utf-8"), indent=1, sort_keys=True)


def save_slot(img, slot, scale=None, stretch=False):
    if stretch:
        out, used = img.resize((slot["w"], slot["h"]), Image.LANCZOS), None
    else:
        out, used = fit(img, slot, scale)
    out.save(os.path.join(OUT, slot["file"] + ".tga"), format="TGA")
    return used


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet", help="the hand-made sprite sheet (PNG, transparent)")
    ap.add_argument("--map", default=os.path.join(TOOLS, "sheets", "pegs.json"))
    ap.add_argument("--go", action="store_true", help="spend credits; without it only the plan is printed")
    ap.add_argument("--only", nargs="*")
    ap.add_argument("--stage", choices=["sheet", "derive", "pose", "asset", "refit", "all"], default="all")
    ap.add_argument("--force", action="store_true", help="redo slots already recorded")
    ap.add_argument("--quality", choices=["turbo", "ultra"], default="ultra")
    ap.add_argument("--alpha", type=int, default=16, help="alpha a sheet pixel needs to count as part of a sprite")
    ap.add_argument("--merge", type=int, default=10, help="gap in pixels under which two islands are one sprite")
    ap.add_argument("--clean", type=int, default=None, help="sheet pixels fainter than this alpha are dropped (default: --alpha)")
    args = ap.parse_args()

    slots = {s["name"]: s for s in read_slots()}
    missing = [n for n in slots if n not in PLAN]
    extra = [n for n in PLAN if n not in slots]
    if missing or extra:
        print("plan out of step with Art.lua: missing", missing, "extra", extra)
        return 1
    rec = load_record()
    want = set(args.only) if args.only else set(slots)

    def todo(how):
        return [n for n in slots if n in want and PLAN[n]["how"] == how and (args.force or not rec["slots"].get(n, {}).get("done"))]

    # ---- plan
    counts = {how: len([n for n in slots if PLAN[n]["how"] == how]) for how in ("sheet", "derive", "pose", "asset", "tool")}
    credits = 3 * len(todo("pose")) + 2 * len(todo("asset"))
    print(f"slots: {counts}; to do now: sheet {len(todo('sheet'))}, derive {len(todo('derive'))}, pose {len(todo('pose'))}, asset {len(todo('asset'))}; about {credits} credits")
    if not args.go:
        for n in slots:
            p = PLAN[n]
            state = "done" if rec["slots"].get(n, {}).get("done") else "todo"
            detail = p.get("prompt") or p.get("description") or (p.get("op", "") + " of " + p.get("source", "")) or ""
            print(f"  {state:4s} {p['how']:6s} {n:22s} {detail[:90]}")
        print("dry run: add --go to generate")
        return 0

    sheet_img = Image.open(args.sheet).convert("RGBA") if args.sheet else None
    boxes = islands(sheet_img, args.alpha, args.merge) if sheet_img else []
    clean = args.alpha if args.clean is None else args.clean
    mapping = json.load(open(args.map, encoding="utf-8")) if sheet_img else {}
    sprite_of = {}
    if sheet_img:
        for name, b in boxes_by_slot(mapping, boxes, slots).items():
            sprite_of[name] = clean_crop(sheet_img, b, clean)

    # ---- 1. the sheet
    scales = {}
    if args.stage in ("sheet", "all"):
        for n in sorted(todo("sheet"), key=lambda n: base_of(n) is not None):
            if n not in sprite_of:
                print(f"  sheet  {n}: not on the sheet (give --sheet and check the map)")
                continue
            parent = base_of(n)
            used = save_slot(sprite_of[n], slots[n], scales.get(parent) if parent else None)
            scales[n] = used
            rec["slots"][n] = {"how": "sheet", "done": True}
            print(f"  sheet  {n}")
        save_record(rec)

    api = None
    if args.stage in ("pose", "asset", "all") and (todo("pose") or todo("asset")) or args.stage == "refit":
        api = AutoSprite(open(KEY_FILE, encoding="utf-8").read().strip())

    # ---- refit: fetch recorded assets again and fit them afresh (no credits)
    if args.stage == "refit":
        for n in slots:
            entry = rec["slots"].get(n, {})
            p = PLAN[n]
            if n in want and p["how"] == "asset" and entry.get("assetId"):
                try:
                    info = api.call("get_asset", assetId=entry["assetId"])
                    a = info.get("asset", info)
                    url = (a.get("baseImageNoBgUrl") if not p["keep_bg"] else None) or a.get("baseImageUrl")
                    img = download(url)
                    if not p["keep_bg"]:
                        img = crop_content(strip_background(img))
                    save_slot(img, slots[n], stretch=p["keep_bg"])
                    print(f"  refit  {n}")
                except Exception as e:
                    print(f"  refit  {n}: FAILED {e}")
        return 0

    # ---- 2. assets: preview -> save -> strip background -> download
    if args.stage in ("asset", "all"):
        for n in todo("asset"):
            p = PLAN[n]
            entry = {"how": "asset"} if args.force else rec["slots"].get(n, {"how": "asset"})
            try:
                if not entry.get("assetId"):
                    prev = api.call("generate_asset_preview", category=p["category"], description=p["description"][:200], style=ART_STYLE, quality=args.quality)
                    urls = prev.get("urls") or prev.get("imageUrls") or ([prev["url"]] if prev.get("url") else [])
                    if not urls:
                        for v in prev.values():
                            if isinstance(v, list) and v and isinstance(v[0], str) and v[0].startswith("http"):
                                urls = v
                                break
                            if isinstance(v, list) and v and isinstance(v[0], dict) and v[0].get("url"):
                                urls = [d["url"] for d in v]
                                break
                    if not urls:
                        raise RuntimeError("no preview url in " + json.dumps(prev)[:300])
                    # asset names are unique per account: a forced redraw gets a stamp
                    aname = "GP " + n + (" " + time.strftime("%m%d%H%M%S") if args.force else "")
                    created = api.call("create_asset", name=aname, imageUrl=urls[0], description=n)
                    entry["assetId"] = created.get("id") or created.get("asset", {}).get("id")
                    rec["slots"][n] = entry
                    save_record(rec)
                if not p["keep_bg"] and not entry.get("bgRemoved"):
                    try:
                        api.call("remove_asset_background", assetId=entry["assetId"])
                        entry["bgRemoved"] = True
                        save_record(rec)
                    except Exception as e:
                        print(f"    background removal failed for {n}: {e}; stripping locally")
                info = api.call("get_asset", assetId=entry["assetId"])
                a = info.get("asset", info)
                url = (a.get("baseImageNoBgUrl") if not p["keep_bg"] else None) or a.get("baseImageUrl")
                img = download(url)
                if not p["keep_bg"]:
                    img = crop_content(strip_background(img))
                save_slot(img, slots[n], stretch=p["keep_bg"])
                entry["done"] = True
                rec["slots"][n] = entry
                save_record(rec)
                print(f"  asset  {n}")
            except Exception as e:
                print(f"  asset  {n}: FAILED {e}")

    # ---- 3. poses: upload the base once, ask for each state, poll
    if args.stage in ("pose", "all"):
        jobs = {}
        for n in todo("pose"):
            p = PLAN[n]
            base = p["base"]
            if rec["slots"].get(n, {}).get("jobId") and not args.force:
                jobs[n] = rec["slots"][n]["jobId"]
                print(f"  pose   {n}: resuming {jobs[n]}")
                continue
            try:
                char = rec["characters"].get(base)
                if not char:
                    base_path = os.path.join(OUT, slots[base]["file"] + ".tga")
                    if base in sprite_of:
                        src = sprite_of[base]
                    elif os.path.exists(base_path) and rec["slots"].get(base, {}).get("done"):
                        src = Image.open(base_path).convert("RGBA")
                    else:
                        raise RuntimeError(f"base {base} is not ready (needs the sheet or its asset first)")
                    tmp = os.path.join(TOOLS, "_upload_%s.png" % base)
                    src.save(tmp)
                    key = api.upload(tmp)
                    os.remove(tmp)
                    made = api.call("upload_character", name="GP " + base, uploadKey=key, isHumanoid=False,
                                    characterDescription="a game piece: " + (slots[base].get("note") or base))
                    char = made.get("id") or made.get("character", {}).get("id")
                    rec["characters"][base] = char
                    save_record(rec)
                job = api.call("generate_pose", character_id=char, prompt=p["prompt"], name=n[:40])
                jobs[n] = job.get("jobId") or job.get("id")
                rec["slots"][n] = {"how": "pose", "jobId": jobs[n], "done": False}
                save_record(rec)
                print(f"  pose   {n}: queued {jobs[n]}")
            except Exception as e:
                print(f"  pose   {n}: FAILED {e}")
        pending = dict(jobs)
        rounds = 0
        while pending and rounds < 60:
            if rounds > 0:
                time.sleep(10)
            rounds += 1
            for n, jid in list(pending.items()):
                try:
                    st = api.rest_get("/jobs/" + jid)
                    status = st.get("status")
                    if status == "succeeded":
                        url = st.get("resultUrl")
                        img = crop_content(strip_background(download(url)))
                        base = PLAN[n]["base"]
                        save_slot(img, slots[n], scales.get(base))
                        rec["slots"][n]["done"] = True
                        save_record(rec)
                        print(f"  pose   {n}: done")
                        del pending[n]
                    elif status == "failed":
                        print(f"  pose   {n}: failed {st.get('error')}")
                        del pending[n]
                except Exception as e:
                    print(f"  pose   {n}: {e}")
        if pending:
            print("  still running (rerun later, the jobs are recorded):", ", ".join(pending))

    # ---- 4. derived slots
    if args.stage in ("derive", "all"):
        for _ in range(3):      # a few passes, as sources may be derived too
            for n in todo("derive"):
                p = PLAN[n]
                src_path = os.path.join(OUT, slots[p["source"]]["file"] + ".tga")
                if not rec["slots"].get(p["source"], {}).get("done") and PLAN[p["source"]]["how"] != "tool":
                    continue
                img = Image.open(src_path).convert("RGBA")
                kw = {k: v for k, v in p.items() if k not in ("how", "source", "op")}
                out = OPS[p["op"]](img, **kw)
                s = slots[n]
                out = out if out.size == (s["w"], s["h"]) else out.resize((s["w"], s["h"]), Image.LANCZOS)
                out.save(os.path.join(OUT, s["file"] + ".tga"), format="TGA")
                rec["slots"][n] = {"how": "derive", "done": True}
                print(f"  derive {n} <- {p['op']} of {p['source']}")
        save_record(rec)

    left = [n for n in slots if n in want and PLAN[n]["how"] != "tool" and not rec["slots"].get(n, {}).get("done")]
    print(f"done. {len(left)} slots still on placeholders: {', '.join(left) if left else 'none'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
