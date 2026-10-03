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


# The side column's buttons: an enamelled plate in a riveted brass rim,
# an icon in a porthole on the left, the word in cream with the same cog
# and piston letters.
BUTTONS = {
    "btn_next":    ("NEXT LEVEL",   (90, 200, 90), (24, 100, 40), "next"),
    "btn_restart": ("RESTART",      (240, 120, 70), (150, 40, 20), "restart"),
    "btn_levels":  ("LEVEL SELECT", (80, 170, 230), (24, 70, 140), "map"),
}


def _icon(kind, size):
    """A cream icon on transparent, `size` square."""
    m = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(m)
    cream = (255, 246, 220, 255)
    c, r = size / 2, size * 0.36
    w = max(2, int(size * 0.1))
    if kind == "restart":
        d.arc([c - r, c - r, c + r, c + r], 40, 330, fill=cream, width=w)
        a = math.radians(40)
        tx, ty = c + math.cos(a) * r, c + math.sin(a) * r
        s = size * 0.2
        d.polygon([(tx + s * 0.9, ty - s * 0.2), (tx - s * 0.6, ty - s * 0.5), (tx - s * 0.1, ty + s * 0.8)], fill=cream)
    elif kind == "map":
        x0, y0, x1, y1 = size * 0.16, size * 0.24, size * 0.84, size * 0.78
        d.polygon([(x0, y0), (c - size * 0.11, y0 - size * 0.06), (c + size * 0.11, y0), (x1, y0 - size * 0.06),
                   (x1, y1 - size * 0.06), (c + size * 0.11, y1), (c - size * 0.11, y1 - size * 0.06), (x0, y1)], outline=cream, width=w)
        for k, (px, py) in enumerate(((0.3, 0.62), (0.46, 0.5), (0.6, 0.58))):
            rr = size * 0.035
            d.ellipse([size * px - rr, size * py - rr, size * px + rr, size * py + rr], fill=cream)
        pr = size * 0.09
        d.ellipse([size * 0.72 - pr, size * 0.36 - pr, size * 0.72 + pr, size * 0.36 + pr], fill=(255, 90, 70, 255))
    else:   # next: two chevrons
        for k in (0, 1):
            ox = size * (0.22 + 0.24 * k)
            d.line([(ox, size * 0.24), (ox + size * 0.24, c), (ox, size * 0.76)], fill=cream, width=w + 1, joint="curve")
    return m


def plate_button(text, top, bottom, icon):
    bw, bh = W * SS, H * SS
    img = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rad = int(bh * 0.32)
    # the brass rim
    rim = Image.new("RGBA", (bw, bh))
    rd = ImageDraw.Draw(rim)
    for y in range(bh):
        t = y / (bh - 1)
        k = 1 - t
        rd.line([(0, y), (bw, y)], fill=tuple(int(BRASS_BOTTOM[i] + (BRASS_TOP[i] - BRASS_BOTTOM[i]) * k) for i in range(3)) + (255,))
    rmask = Image.new("L", (bw, bh), 0)
    ImageDraw.Draw(rmask).rounded_rectangle([0, 0, bw - 1, bh - 1], radius=rad, fill=255)
    img.paste(rim, (0, 0), rmask)
    d.rounded_rectangle([0, 0, bw - 1, bh - 1], radius=rad, outline=OUTLINE + (255,), width=SS * 2)
    # the enamel
    inset = int(bh * 0.13)
    en = Image.new("RGBA", (bw, bh))
    ed = ImageDraw.Draw(en)
    for y in range(bh):
        t = y / (bh - 1)
        k = 1 - abs(t - 0.25) / 0.75 if t >= 0.25 else 1
        ed.line([(0, y), (bw, y)], fill=tuple(int(bottom[i] + (top[i] - bottom[i]) * k) for i in range(3)) + (255,))
    emask = Image.new("L", (bw, bh), 0)
    ImageDraw.Draw(emask).rounded_rectangle([inset, inset, bw - 1 - inset, bh - 1 - inset], radius=rad - inset, fill=255)
    img.paste(en, (0, 0), emask)
    # a gloss across the top half
    gloss = Image.new("L", (bw, bh), 0)
    ImageDraw.Draw(gloss).rounded_rectangle([inset + SS * 4, inset + SS * 2, bw - 1 - inset - SS * 4, bh // 2], radius=rad // 2, fill=60)
    img = Image.alpha_composite(img, Image.merge("RGBA", (gloss.point(lambda v: 255),) * 3 + (gloss,)))
    d = ImageDraw.Draw(img)
    # rivets at the ends
    for x in (inset * 2.2, bw - inset * 2.2):
        for y in (bh * 0.32, bh * 0.68):
            rr = SS * 2.6
            d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=(250, 225, 150, 255), outline=OUTLINE + (255,), width=SS)
    # the porthole and its icon
    ph = int(bh * 0.74)
    px = int(inset * 3.4)
    py = (bh - ph) // 2
    d.ellipse([px, py, px + ph, py + ph], fill=tuple(int(v * 0.55) for v in bottom) + (255,), outline=(250, 225, 150, 255), width=SS * 2)
    ic = _icon(icon, ph)
    img.alpha_composite(ic, (px, py))
    # the word, in cream with a dark outline, centred in the rest of the plate
    cap = int(bh * 0.46)
    mask = word_mask(text, cap)
    room = bw - (px + ph) - inset * 4
    if mask.width > room:
        f = room / mask.width
        mask = mask.resize((room, max(1, int(mask.height * f))), Image.LANCZOS)
    mx = px + ph + (bw - (px + ph) - inset * 2 - mask.width) // 2
    my = (bh - mask.height) // 2
    o = Image.new("RGBA", img.size, (0, 0, 0, 0))
    o.paste((40, 20, 8, 255), (mx, my), mask.filter(ImageFilter.MaxFilter(2 * SS + 1)))
    img = Image.alpha_composite(img, o)
    f = Image.new("RGBA", img.size, (0, 0, 0, 0))
    f.paste((255, 246, 220, 255), (mx, my), mask)
    img = Image.alpha_composite(img, f)
    return img.resize((W, H), Image.LANCZOS)


# The side column's buttons are small copies of the logo: its two cog
# end-caps, its copper plate between them (a slice from the gap between the
# logo's words, stretched), and the button's word in the logo's gold.
LOGO_SOURCE = os.path.join(HERE, "sheets", "logo_source.tga")
LOGO_CAP = 56            # the end-caps' width in the logo (128 tall)
LOGO_GAP = (252, 262)    # a text-free column range of the plate


def logo_button(text):
    logo = Image.open(LOGO_SOURCE).convert("RGBA")
    lw, lh = logo.size
    cw, ch = 1024, 128
    img = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    left = logo.crop((0, 0, LOGO_CAP, lh))
    right = logo.crop((lw - LOGO_CAP, 0, lw, lh))
    mid = logo.crop((LOGO_GAP[0], 0, LOGO_GAP[1], lh)).resize((cw - 2 * LOGO_CAP, lh), Image.BICUBIC)
    img.alpha_composite(mid, (LOGO_CAP, 0))
    img.alpha_composite(left, (0, 0))
    img.alpha_composite(right, (cw - LOGO_CAP, 0))
    if not text:
        # the blank plate: buttons whose words change draw them in the game
        return img.resize((W, H), Image.LANCZOS)
    # the word in the logo's gold: bright, a dark rim, a soft shadow
    cap = 50
    mask = word_mask(text, cap * SS)
    mask = mask.resize((max(1, mask.width // SS), max(1, mask.height // SS)), Image.LANCZOS)
    room = cw - 2 * LOGO_CAP - 40
    if mask.width > room:
        f = room / mask.width
        mask = mask.resize((room, max(1, int(mask.height * f))), Image.LANCZOS)
    mx = (cw - mask.width) // 2
    my = (ch - mask.height) // 2 + 2
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    sh.paste((0, 0, 0, 170), (mx + 3, my + 4), mask)
    img = Image.alpha_composite(img, sh.filter(ImageFilter.GaussianBlur(3)))
    o = Image.new("RGBA", img.size, (0, 0, 0, 0))
    o.paste((70, 34, 8, 255), (mx, my), mask.filter(ImageFilter.MaxFilter(5)))
    img = Image.alpha_composite(img, o)
    grad = Image.new("RGBA", mask.size)
    gd = ImageDraw.Draw(grad)
    for y in range(mask.height):
        t = y / max(1, mask.height - 1)
        k = 1 - t
        c = (int(200 + 55 * k), int(140 + 100 * k), int(30 + 90 * k))
        gd.line([(0, y), (mask.width, y)], fill=c + (255,))
    fl = Image.new("RGBA", img.size, (0, 0, 0, 0))
    fl.paste(grad, (mx, my), mask)
    img = Image.alpha_composite(img, fl)
    return img.resize((W, H), Image.LANCZOS)


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
    if not args.only or "btn_logo" in args.only:
        logo_button("").save(os.path.join(OUT, "btn_logo.tga"), format="TGA")
        print("wrote btn_logo")
    for slot, (text, top, bottom, icon) in BUTTONS.items():
        if args.only and slot not in args.only:
            continue
        img = logo_button(text)
        img.save(os.path.join(OUT, slot + ".tga"), format="TGA")
        made.append((slot, img))
        print("wrote", slot)
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
