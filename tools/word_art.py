"""Gnomish word-art for the side panel's headings.

Each heading is drawn in brass capitals with gnomish machinery standing in
for some letters: every O is a cogwheel, every I a piston. The spelling is
exact (drawn from a font, not painted by a model), so it stays legible.

    python tools/word_art.py            # writes every word_* slot to Textures/
    python tools/word_art.py --sheet    # also a preview sheet in tools/sheets/

The words and their slots are listed in WORDS; Art.lua has a slot for each.
"""
import argparse
import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "Textures")
FONT = r"C:\Windows\Fonts\georgiab.ttf"
W, H = 512, 64          # every word sits left-aligned on a 512 x 64 canvas
SS = 4                   # drawn four times bigger, then scaled down

WORDS = {
    "word_objective": "OBJECTIVE",
    "word_power": "POWER",
    "word_balls": "BALLS",
    "word_score": "SCORE",
    "word_multiplier": "MULTIPLIER",
    "word_combo": "COMBO",
    "word_best": "BEST",
    "word_next_free_ball": "NEXT FREE BALL",
    "word_stars": "STARS",
    "word_goal_classic": "ORANGE PEGS LEFT",
    "word_goal_eggs": "EGGS LEFT",
    "word_goal_gems": "GEMS TO DROP",
    "word_goal_boss": "BOSS HEALTH",
    "word_goal_longshots": "LONG SHOTS LEFT",
    "word_goal_mixed": "GOALS LEFT",
    "word_shop": "GOLDEN GEAR SHOP",
}

BRASS_TOP = (255, 236, 160)
BRASS_BOTTOM = (176, 112, 30)
OUTLINE = (52, 30, 10)


def cog_mask(size):
    """A cogwheel the height of a capital: eight teeth, a rim, a hub hole."""
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    c = size / 2
    r_out, r_body, r_hole = size * 0.5, size * 0.38, size * 0.13
    teeth = 8
    for k in range(teeth):
        a = k * 2 * math.pi / teeth
        w = 0.24
        pts = []
        for da, rr in ((-w, r_body), (-w * 0.6, r_out), (w * 0.6, r_out), (w, r_body)):
            pts.append((c + math.cos(a + da) * rr, c + math.sin(a + da) * rr))
        d.polygon(pts, fill=255)
    d.ellipse([c - r_body, c - r_body, c + r_body, c + r_body], fill=255)
    # spokes cut through a ring, a hub left in the middle
    d.ellipse([c - r_body * 0.68, c - r_body * 0.68, c + r_body * 0.68, c + r_body * 0.68], fill=0)
    for k in range(4):
        a = k * math.pi / 4 * 2 + math.pi / 4
        d.line([(c, c), (c + math.cos(a) * r_body * 0.7, c + math.sin(a) * r_body * 0.7)], fill=255, width=max(2, int(size * 0.09)))
    d.ellipse([c - r_body * 0.32, c - r_body * 0.32, c + r_body * 0.32, c + r_body * 0.32], fill=255)
    d.ellipse([c - r_hole * 0.7, c - r_hole * 0.7, c + r_hole * 0.7, c + r_hole * 0.7], fill=0)
    return m


def piston_mask(h):
    """A piston standing in for an I: a cylinder head, a rod, a foot."""
    w = int(h * 0.42)
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    head = int(h * 0.36)
    d.rounded_rectangle([0, 0, w - 1, head], radius=max(1, int(w * 0.12)), fill=255)
    # rings round the head
    for k in (0.33, 0.66):
        y = int(head * k)
        d.line([(0, y), (w, y)], fill=0, width=max(1, int(h * 0.035)))
    rod = int(w * 0.32)
    d.rectangle([(w - rod) // 2, head, (w + rod) // 2, h - int(h * 0.14)], fill=255)
    d.rounded_rectangle([int(w * 0.12), h - int(h * 0.16), int(w * 0.88), h - 1], radius=max(1, int(w * 0.08)), fill=255)
    return m


def word_mask(text, cap):
    """The word as a mask: glyphs from the font, cogs and pistons for O and I."""
    font = ImageFont.truetype(FONT, int(cap * 1.38))
    # the font's cap height, to line glyphs up with the machine parts
    bbox = font.getbbox("H")
    glyph_top, glyph_bottom = bbox[1], bbox[3]
    gap = int(cap * 0.08)
    parts = []
    x = 0
    for ch in text:
        if ch == " ":
            x += int(cap * 0.45)
            continue
        if ch == "O":
            m = cog_mask(int(cap * 1.08))
            parts.append((m, x, -int(cap * 0.04)))
            x += m.width + gap
        elif ch == "I":
            m = piston_mask(cap)
            parts.append((m, x, 0))
            x += m.width + gap
        else:
            b = font.getbbox(ch)
            gw = b[2] - b[0]
            m = Image.new("L", (gw + 4, cap + 4), 0)
            ImageDraw.Draw(m).text((-b[0] + 2, -glyph_top + 2), ch, font=font, fill=255)
            # the glyph drawn at the font's size; squeeze it to the cap height
            m = m.resize((m.width, cap + 4))
            parts.append((m, x, -2))
            x += gw + gap
    width = max(1, x - gap)
    out = Image.new("L", (width + 8, int(cap * 1.2) + 8), 0)
    for m, px, py in parts:
        out.paste(m, (px + 4, py + 4 + int(cap * 0.08)), m)
    return out


def render(text):
    pad = 6 * SS
    cap = int((H - 16) * SS)
    mask = word_mask(text, cap)
    # too wide for the canvas: scale the whole word down to fit
    limit = W * SS - 2 * pad
    if mask.width > limit:
        f = limit / mask.width
        mask = mask.resize((limit, max(1, int(mask.height * f))), Image.LANCZOS)
    canvas = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    oy = (H * SS - mask.height) // 2
    # shadow, outline, brass
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 150), (pad + 3 * SS, oy + 3 * SS), mask)
    shadow = shadow.filter(ImageFilter.GaussianBlur(2 * SS))
    canvas = Image.alpha_composite(canvas, shadow)
    outline = mask.filter(ImageFilter.MaxFilter(2 * SS + 1))
    o = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    o.paste(OUTLINE + (255,), (pad, oy), outline)
    canvas = Image.alpha_composite(canvas, o)
    grad = Image.new("RGBA", mask.size)
    gd = ImageDraw.Draw(grad)
    for y in range(mask.height):
        t = y / max(1, mask.height - 1)
        # bright band across the upper third, darker toward the foot
        k = 1 - abs(t - 0.3) / 0.7 if t < 0.3 else 1 - (t - 0.3) / 0.7
        k = max(0, min(1, 0.35 + 0.65 * k))
        c = tuple(int(BRASS_BOTTOM[i] + (BRASS_TOP[i] - BRASS_BOTTOM[i]) * k) for i in range(3))
        gd.line([(0, y), (mask.width, y)], fill=c + (255,))
    fill = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    fill.paste(grad, (pad, oy), mask)
    canvas = Image.alpha_composite(canvas, fill)
    return canvas.resize((W, H), Image.LANCZOS)


def gear_sprite(size=128):
    """The shop's button: a shiny golden gear, lit from the top left, with a
    glint on its rim."""
    big = size * SS
    mask = cog_mask(int(big * 0.92))
    canvas = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    off = (big - mask.width) // 2
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 160), (off + 3 * SS, off + 4 * SS), mask)
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(3 * SS)))
    o = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    o.paste(OUTLINE + (255,), (off, off), mask.filter(ImageFilter.MaxFilter(3 * SS + 1)))
    canvas = Image.alpha_composite(canvas, o)
    # gold lit from the top left
    grad = Image.new("RGBA", mask.size)
    px = grad.load()
    n = mask.width
    for y in range(n):
        for x in range(0, n, 1):
            t = ((x / n) + (y / n)) / 2
            k = max(0.0, 1 - t * 1.25)
            c = tuple(int(BRASS_BOTTOM[i] + (BRASS_TOP[i] - BRASS_BOTTOM[i]) * (0.25 + 0.75 * k)) for i in range(3))
            px[x, y] = c + (255,)
    fill = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    fill.paste(grad, (off, off), mask)
    canvas = Image.alpha_composite(canvas, fill)
    # a white glint on the upper left of the rim, and a little star
    glint = Image.new("L", canvas.size, 0)
    gd = ImageDraw.Draw(glint)
    c = big / 2
    r = mask.width * 0.33
    gd.arc([c - r, c - r, c + r, c + r], 200, 250, fill=230, width=int(5 * SS))
    glint = glint.filter(ImageFilter.GaussianBlur(1.5 * SS))
    canvas = Image.alpha_composite(canvas, Image.merge("RGBA", (glint.point(lambda v: 255),) * 3 + (glint,)))
    sd = ImageDraw.Draw(canvas)
    sx, sy, sr = big * 0.27, big * 0.24, big * 0.07
    sd.polygon([(sx, sy - sr), (sx + sr * 0.22, sy - sr * 0.22), (sx + sr, sy), (sx + sr * 0.22, sy + sr * 0.22),
                (sx, sy + sr), (sx - sr * 0.22, sy + sr * 0.22), (sx - sr, sy), (sx - sr * 0.22, sy - sr * 0.22)], fill=(255, 255, 240, 255))
    return canvas.resize((size, size), Image.LANCZOS)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet", action="store_true")
    ap.add_argument("--only", nargs="*")
    args = ap.parse_args()
    made = []
    for slot, text in WORDS.items():
        if args.only and slot not in args.only:
            continue
        img = render(text)
        img.save(os.path.join(OUT, slot + ".tga"), format="TGA")
        made.append((slot, img))
        print("wrote", slot)
    if not args.only or "shop_gear" in args.only:
        g = gear_sprite(128)
        g.save(os.path.join(OUT, "shop_gear.tga"), format="TGA")
        print("wrote shop_gear")
    if args.sheet and made:
        sheet = Image.new("RGBA", (W, H * len(made)), (34, 30, 44, 255))
        for i, (_, img) in enumerate(made):
            sheet.alpha_composite(img, (0, i * H))
        os.makedirs(os.path.join(HERE, "sheets"), exist_ok=True)
        path = os.path.join(HERE, "sheets", "words.png")
        sheet.save(path)
        print("sheet", path)


if __name__ == "__main__":
    main()
