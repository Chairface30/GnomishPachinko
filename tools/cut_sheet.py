"""Slice a sprite sheet (a PNG with a transparent background) into the
art slots of Gnomish Pachinko.

1. See what is on the sheet. Every island of opaque pixels is a sprite;
   the tool numbers them in reading order and writes <sheet>_boxes.png
   with the numbers drawn on:

       python tools/cut_sheet.py sheet.png --list

2. Say which sprite is which slot, in a JSON map (see tools/sheets/ for
   one): {"1": "peg_blue", "2": "peg_orange", ...}. A number not in the
   map is skipped; a slot named twice takes the last.

       python tools/cut_sheet.py sheet.png --map tools/sheets/pegs.json

   Each named sprite is scaled into its slot's canvas and saved as
   Textures/<slot>.tga: round pieces so the body fills the slot's share
   (0.7 of a 64 px peg canvas), bars and skins to the full canvas. A
   _lit or _gone state is scaled exactly like its base sprite (same
   pixels per unit, centred on the base's centre), so a halo or shards
   spill into the room the base leaves. Nothing is written for a slot
   that is not in Art.lua; --dry-run shows the plan without writing.

Needs: pip install pillow lupa
"""
import argparse
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Textures")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_textures import read_slots  # noqa: E402


def islands(img, alpha_min=16, merge=10):
    """Bounding boxes of the opaque islands, close ones merged (a sparkle
    is many specks), sorted into rows top to bottom, left to right."""
    w, h = img.size
    a = img.split()[-1].load()
    seen = bytearray(w * h)
    boxes = []
    for y in range(h):
        for x in range(w):
            if a[x, y] >= alpha_min and not seen[y * w + x]:
                # flood fill
                stack = [(x, y)]
                seen[y * w + x] = 1
                x0, y0, x1, y1 = x, y, x, y
                while stack:
                    cx, cy = stack.pop()
                    x0, y0, x1, y1 = min(x0, cx), min(y0, cy), max(x1, cx), max(y1, cy)
                    for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                        if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and a[nx, ny] >= alpha_min:
                            seen[ny * w + nx] = 1
                            stack.append((nx, ny))
                boxes.append([x0, y0, x1, y1])
    # merge boxes that touch or nearly touch
    changed = True
    while changed:
        changed = False
        out = []
        while boxes:
            b = boxes.pop()
            for i, o in enumerate(out):
                if b[0] - merge <= o[2] and b[2] + merge >= o[0] and b[1] - merge <= o[3] and b[3] + merge >= o[1]:
                    out[i] = [min(b[0], o[0]), min(b[1], o[1]), max(b[2], o[2]), max(b[3], o[3])]
                    changed = True
                    break
            else:
                out.append(b)
        boxes = out
    # rows: boxes whose vertical centres are within half a box of each other
    boxes.sort(key=lambda b: (b[1] + b[3]) / 2)
    rows = []
    for b in boxes:
        cy = (b[1] + b[3]) / 2
        for row in rows:
            if abs(row["cy"] - cy) < max(30, (b[3] - b[1]) * 0.6):
                row["boxes"].append(b)
                row["cy"] = sum((q[1] + q[3]) / 2 for q in row["boxes"]) / len(row["boxes"])
                break
        else:
            rows.append({"cy": cy, "boxes": [b]})
    rows.sort(key=lambda r: r["cy"])
    ordered = []
    for row in rows:
        ordered.extend(sorted(row["boxes"], key=lambda b: b[0]))
    return ordered


def draw_boxes(img, boxes, path):
    sheet = img.convert("RGBA")
    back = Image.new("RGBA", sheet.size, (40, 40, 48, 255))
    back.alpha_composite(sheet)
    d = ImageDraw.Draw(back)
    try:
        font = ImageFont.load_default(size=22)
    except TypeError:
        font = ImageFont.load_default()
    for i, b in enumerate(boxes, 1):
        d.rectangle(b, outline=(255, 80, 80, 255), width=2)
        d.text((b[0] + 3, b[1] + 2), str(i), fill=(255, 255, 120, 255), font=font)
    back.save(path)


def base_of(name):
    for suffix in ("_lit", "_gone", "_down", "_cracked", "_hatched"):
        if name.endswith(suffix):
            return name[: -len(suffix)]
    return None


def fit(sprite, slot, scale=None, centre=None):
    """The sprite scaled into the slot's canvas. Returns the image and the
    scale used (pixels of canvas per pixel of sheet) and the centre."""
    W, H = slot["w"], slot["h"]
    sw, sh = sprite.size
    fill = slot.get("fill")
    if scale is None:
        if fill:
            # the body (this sprite) fills `fill` of the canvas
            scale = min(W * fill / sw, H * fill / sh)
        else:
            scale = min(W / sw, H / sh)
    ow, oh = max(1, int(round(sw * scale))), max(1, int(round(sh * scale)))
    small = sprite.resize((ow, oh), Image.LANCZOS)
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    cx, cy = centre or (W / 2, H / 2)
    canvas.alpha_composite(small, (int(round(cx - ow / 2)), int(round(cy - oh / 2))))
    return canvas, scale


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sheet")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--map")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--alpha", type=int, default=16, help="alpha a pixel needs to count as part of a sprite")
    ap.add_argument("--merge", type=int, default=10, help="gap in pixels under which two islands are one sprite")
    args = ap.parse_args()

    img = Image.open(args.sheet).convert("RGBA")
    boxes = islands(img, args.alpha, args.merge)
    base, _ = os.path.splitext(args.sheet)
    draw_boxes(img, boxes, base + "_boxes.png")
    print(f"{len(boxes)} sprites on the sheet; numbered picture at {base}_boxes.png")
    if args.list or not args.map:
        for i, b in enumerate(boxes, 1):
            print(f"  {i:3d}: x {b[0]}-{b[2]}  y {b[1]}-{b[3]}  ({b[2] - b[0] + 1}x{b[3] - b[1] + 1})")
        if not args.map:
            return

    mapping = json.load(open(args.map, encoding="utf-8"))
    slots = {s["name"]: s for s in read_slots()}
    # the base sprites first, so their states can borrow the scale
    plan = []
    for num, name in mapping.items():
        if name.startswith("_"):
            continue
        if name not in slots:
            print(f"  skip {num}: no slot named {name}")
            continue
        idx = int(num) - 1
        if idx < 0 or idx >= len(boxes):
            print(f"  skip {num}: no such sprite")
            continue
        plan.append((name, boxes[idx]))
    plan.sort(key=lambda p: (base_of(p[0]) is not None, p[0]))
    scales = {}
    for name, b in plan:
        slot = slots[name]
        sprite = img.crop((b[0], b[1], b[2] + 1, b[3] + 1))
        parent = base_of(name)
        scale = scales.get(parent) if parent else None
        out, used = fit(sprite, slot, scale)
        scales[name] = used
        print(f"  {name:22s} <- sprite {b[2] - b[0] + 1}x{b[3] - b[1] + 1} at scale {used:.3f}" + (f" (like {parent})" if parent and scale else ""))
        if not args.dry_run:
            out.save(os.path.join(OUT, slot["file"] + ".tga"), format="TGA")
    if args.dry_run:
        print("dry run: nothing written")
    else:
        print(f"wrote {len(plan)} textures to {OUT}")


if __name__ == "__main__":
    main()
