"""Generate a placeholder for every art slot of Gnomish Pachinko.

The slots are listed in Art.lua (this script reads them from there, so the
two never drift). Every slot gets a Textures/<name>.tga: round pieces at
the slot's fill share of the canvas, bars filling the width, skins with
their 9-slice border, icons as a coloured disc with a simple glyph. Real
art replaces any of them under the same name.

Run: python tools/make_textures.py            every slot
     python tools/make_textures.py --only peg_blue egg_cracked
     python tools/make_textures.py --from-base  derive the per-colour pegs,
            bricks, keys and bosses from the white peg.tga / brick.tga /
            key.tga / boss.tga already in Textures/ (a painted base) instead
            of regenerating those
     python tools/make_textures.py --sheet out.png   also write a contact
            sheet of everything, for a look

Needs: pip install pillow lupa
"""
import argparse
import math
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Textures")
os.makedirs(OUT, exist_ok=True)

SS = 4  # supersampling

COLORS = {
    "blue":   ((0.18, 0.44, 0.88), (0.56, 0.76, 1.0)),
    "orange": ((0.95, 0.42, 0.11), (1.0, 0.76, 0.48)),
    "green":  ((0.24, 0.75, 0.23), (0.71, 0.96, 0.60)),
    "purple": ((0.64, 0.25, 0.88), (0.88, 0.66, 1.0)),
}
BOSS_TINT = {
    "drake": (0.75, 0.80, 0.90), "golem": (0.95, 0.80, 0.30), "spider": (0.60, 0.90, 0.45),
    "boar": (0.90, 0.45, 0.35), "yeti": (0.70, 0.85, 1.00),
}
COPPER = (0.72, 0.40, 0.16)
COPPER_LIGHT = (0.89, 0.60, 0.33)
TRIM = (0.35, 0.18, 0.07)
PARCHMENT = (0.97, 0.78, 0.35)
PARCHMENT_EDGE = (0.77, 0.47, 0.16)
NAVY = (0.12, 0.23, 0.54)


# ---------------------------------------------------------------- slots from Art.lua

def read_slots():
    """The slots straight from Art.lua, run under Lua (pip install lupa)."""
    import lupa
    rt = lupa.LuaRuntime()
    rt.execute("GnomishPachinko = {}")
    rt.execute(open(os.path.join(ROOT, "Art.lua"), encoding="utf-8").read())
    art = rt.eval("GnomishPachinko.Art")
    slots = []
    for name in list(art.ORDER.values()):
        d = art.SLOTS[name]
        slots.append({k: d[k] for k in ("name", "w", "h", "file", "tint", "fill", "inset", "edge", "free", "source", "group", "note") if d[k] is not None})
    return slots


# ---------------------------------------------------------------- primitives

def canvas(w, h):
    return Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))


def finish(img, w, h):
    return img.resize((w, h), Image.LANCZOS)


def rgb(c, v=1.0):
    return tuple(int(round(255 * min(1.0, x * v))) for x in c) + (255,)


def disc(size, fill, color=(1, 1, 1), highlight=(0.36, 0.34), edge_dark=0.5, spec=0.35, rim=None):
    """A shaded disc filling `fill` of the canvas. Colour multiplies a
    white shading, so (1,1,1) gives the tintable base."""
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    px = img.load()
    c = big / 2
    r = big / 2 * fill
    hx, hy = c + (highlight[0] - 0.5) * 2 * r, c + (highlight[1] - 0.5) * 2 * r
    for y in range(big):
        for x in range(big):
            d = math.hypot(x + 0.5 - c, y + 0.5 - c)
            if d > r + 1:
                continue
            a = max(0.0, min(1.0, r + 1 - d))
            hd = math.hypot(x + 0.5 - hx, y + 0.5 - hy) / (r * 1.8)
            v = 1.0 - (1.0 - edge_dark) * min(1.0, hd ** 1.1)
            s = max(0.0, 1.0 - math.hypot(x + 0.5 - hx, y + 0.5 - hy) / (r * 0.32))
            v = min(1.0, v + spec * s * s)
            if rim and d > r * (1 - rim[0]):
                v = v * rim[1]
            px[x, y] = (int(255 * min(1, v * color[0])), int(255 * min(1, v * color[1])), int(255 * min(1, v * color[2])), int(round(255 * a)))
    return img


def bar(w, h, fill=0.9, color=(1, 1, 1), caps=None):
    """A rounded bar lit from the top, the full width, `fill` of the height."""
    bw, bh = w * SS, h * SS
    img = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    top = int(bh * (1 - fill) / 2)
    d.rounded_rectangle([0, top, bw - 1, bh - 1 - top], radius=(bh - 2 * top) // 3, fill=(255, 255, 255, 255))
    px = img.load()
    for y in range(bh):
        v = 1.0 - 0.45 * max(0.0, (y - top) / max(1, bh - 1 - 2 * top)) ** 1.2
        for x in range(bw):
            if px[x, y][3] == 0:
                continue
            edge = min(x, bw - 1 - x) / (bw * 0.08)
            vv = v * (0.75 + 0.25 * min(1.0, edge))
            if caps and (x < bw * caps or x > bw * (1 - caps)):
                vv *= 0.6
            px[x, y] = (int(255 * min(1, vv * color[0])), int(255 * min(1, vv * color[1])), int(255 * min(1, vv * color[2])), px[x, y][3])
    return img


def glow(size, radius=0.7, width=0.16, color=(1, 1, 1)):
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    px = img.load()
    c = big / 2
    for y in range(big):
        for x in range(big):
            dd = math.hypot(x + 0.5 - c, y + 0.5 - c) / (big / 2)
            a = math.exp(-((dd - radius) ** 2) / (2 * width * width))
            if dd > 0.98:
                a *= max(0.0, (1.0 - dd) / 0.02)
            px[x, y] = rgb(color)[:3] + (int(round(255 * min(1.0, a))),)
    return img


def soft_glow(size, color=(1, 1, 1), sigma=0.33):
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    px = img.load()
    c = big / 2
    for y in range(big):
        for x in range(big):
            dd = math.hypot(x + 0.5 - c, y + 0.5 - c) / (big / 2)
            a = math.exp(-(dd * dd) / (2 * sigma * sigma)) * max(0.0, min(1.0, (1 - dd) / 0.1))
            px[x, y] = rgb(color)[:3] + (int(round(255 * a)),)
    return img


def burst(size, color=(1, 1, 1), spikes=12, inner=0.62):
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    px = img.load()
    c = big / 2
    for y in range(big):
        for x in range(big):
            dd = math.hypot(x + 0.5 - c, y + 0.5 - c) / (big / 2)
            if dd > 1:
                continue
            ang = math.atan2(y + 0.5 - c, x + 0.5 - c)
            sp = 0.5 + 0.5 * math.cos(ang * spikes)
            edge = inner + (0.98 - inner) * sp
            a = max(0.0, 1.0 - dd / edge) ** 0.8
            v = min(1.0, 0.75 + 0.25 * (1 - dd))
            px[x, y] = (int(255 * v * color[0]), int(255 * v * color[1]), int(255 * v * color[2]), int(round(255 * a)))
    return img


def sparkle(size, color=(1, 1, 1), arms=4, length=0.9, thick=0.08, core=0.18):
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = big / 2
    for k in range(arms):
        a = math.pi * 2 * k / arms + (math.pi / 4 if arms == 4 else 0)
        pts = [(c + math.cos(a) * c * length, c + math.sin(a) * c * length),
               (c + math.cos(a + math.pi / 2) * c * thick, c + math.sin(a + math.pi / 2) * c * thick),
               (c - math.cos(a) * c * 0.05, c - math.sin(a) * c * 0.05),
               (c - math.cos(a + math.pi / 2) * c * thick, c - math.sin(a + math.pi / 2) * c * thick)]
        d.polygon(pts, fill=rgb(color))
    img.alpha_composite(soft_glow(size, color, sigma=core))
    return img


def tint_img(img, color):
    px = img.load()
    out = img.copy()
    po = out.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            po[x, y] = (int(r * color[0]), int(g * color[1]), int(b * color[2]), a)
    return out


def compose(base, *layers):
    out = base.copy()
    for l in layers:
        if l.size != out.size:
            l = l.resize(out.size, Image.LANCZOS)
        out.alpha_composite(l)
    return out


def text_on(img, text, size_frac=0.5, color=(255, 255, 255, 255), y_shift=0.0):
    """Big text in the middle (the default font scaled up)."""
    d = ImageDraw.Draw(img)
    try:
        font = ImageFont.load_default(size=int(img.height * size_frac))
    except TypeError:
        font = ImageFont.load_default()
    box = d.textbbox((0, 0), text, font=font)
    tw, th = box[2] - box[0], box[3] - box[1]
    d.text(((img.width - tw) / 2 - box[0], (img.height - th) / 2 - box[1] + img.height * y_shift), text, font=font, fill=color)
    return img


def shards(size, fill, color):
    """A vanishing piece: six shards flung outward."""
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = big / 2
    r = c * fill
    for k in range(6):
        a = math.radians(k * 60 + 15)
        cx, cy = c + math.cos(a) * r * 0.75, c + math.sin(a) * r * 0.75
        s = r * (0.28 + 0.08 * (k % 3))
        pts = [(cx + math.cos(a + t) * s, cy + math.sin(a + t) * s) for t in (0.0, 2.1, 4.2)]
        d.polygon(pts, fill=rgb(color, 0.9 + 0.1 * (k % 2)))
    img.alpha_composite(soft_glow(size, color, sigma=0.22).resize(img.size))
    return img


def lit_piece(base_img, size, color_hi):
    """The hit state: the base brightened plus a halo."""
    halo = glow(size, radius=0.78, width=0.12, color=color_hi)
    bright = base_img.copy()
    px = bright.load()
    for y in range(bright.height):
        for x in range(bright.width):
            r, g, b, a = px[x, y]
            px[x, y] = (min(255, int(r * 0.6 + 110)), min(255, int(g * 0.6 + 110)), min(255, int(b * 0.6 + 110)), a)
    return compose(halo, bright)


def key_shape(size, fill, color):
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = big / 2
    top, bottom = c - c * fill, c + c * fill
    r = (bottom - top) * 0.24
    d.ellipse([c - r, top, c + r, top + 2 * r], outline=rgb(color), width=int(big * 0.08))
    d.rectangle([c - big * 0.05, top + 2 * r - SS, c + big * 0.05, bottom], fill=rgb(color))
    d.rectangle([c, bottom - (bottom - top) * 0.24, c + big * 0.18, bottom - (bottom - top) * 0.18], fill=rgb(color))
    d.rectangle([c, bottom - (bottom - top) * 0.1, c + big * 0.14, bottom - (bottom - top) * 0.04], fill=rgb(color))
    return img


def boss_face(size, fill, color, kind=None):
    img = disc(size, fill, color, highlight=(0.4, 0.35), edge_dark=0.5, spec=0.2)
    big = size * SS
    d = ImageDraw.Draw(img)
    c = big / 2
    r = c * fill
    for k in range(12):
        a = math.radians(k * 30)
        x, y = c + r * 0.93 * math.cos(a), c + r * 0.93 * math.sin(a)
        d.ellipse([x - r * 0.1, y - r * 0.1, x + r * 0.1, y + r * 0.1], fill=rgb(color, 0.8))
    e = r * 0.16
    dark = (35, 35, 40, 255)
    if kind == "spider":
        for ex, ey in ((0.3, 0.36), (0.7, 0.36), (0.4, 0.22), (0.6, 0.22)):
            x, y = c + (ex - 0.5) * 2 * r, c + (ey - 0.5) * 2 * r
            d.ellipse([x - e * 0.7, y - e * 0.7, x + e * 0.7, y + e * 0.7], fill=dark)
    elif kind == "golem":
        for ex in (0.3, 0.7):
            x, y = c + (ex - 0.5) * 2 * r, c - 0.26 * r
            d.rectangle([x - e, y - e * 0.8, x + e, y + e * 0.8], fill=dark)
    elif kind == "drake":
        for ex, s in ((0.3, 1), (0.7, -1)):
            x, y = c + (ex - 0.5) * 2 * r, c - 0.26 * r
            d.polygon([(x - e * s, y - e), (x + e * s, y + e * 0.2), (x - e * s, y + e)], fill=dark)
    else:
        for ex in (0.3, 0.7):
            x, y = c + (ex - 0.5) * 2 * r, c - 0.26 * r
            d.ellipse([x - e, y - e, x + e, y + e], fill=dark)
    zig = [(c + (-0.45 + 0.9 * k / 6) * r, c + (0.32 if k % 2 == 0 else 0.44) * r) for k in range(7)]
    d.line(zig, fill=dark, width=max(1, int(r * 0.08)))
    if kind == "boar":
        for s in (-1, 1):
            d.polygon([(c + s * r * 0.35, c + r * 0.4), (c + s * r * 0.5, c + r * 0.7), (c + s * r * 0.22, c + r * 0.5)], fill=(240, 240, 230, 255))
    if kind == "yeti":
        for s in (-1, 1):
            d.polygon([(c + s * r * 0.2, c + r * 0.38), (c + s * r * 0.3, c + r * 0.62), (c + s * r * 0.08, c + r * 0.42)], fill=(240, 240, 240, 255))
    return img


def egg_shape(size, fill, cracked=False, hatched=False):
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    px = img.load()
    cx, cy = big / 2, big / 2
    rx, ry = big / 2 * fill * 0.78, big / 2 * fill
    for y in range(big):
        for x in range(big):
            dy = (y + 0.5 - cy) / ry
            squeeze = 1.0 - 0.12 * max(0.0, -dy)
            dx = (x + 0.5 - cx) / (rx * squeeze)
            d = math.hypot(dx, dy)
            if d > 1.03:
                continue
            if hatched and dy < -0.05:
                continue
            a = max(0.0, min(1.0, (1.03 - d) / 0.03))
            hd = math.hypot(x + 0.5 - big * 0.4, y + 0.5 - big * 0.33) / (big * 0.9)
            v = 1.0 - 0.45 * min(1.0, hd ** 1.1)
            sp = max(0.0, 1.0 - math.hypot(x + 0.5 - big * 0.4, y + 0.5 - big * 0.3) / (big * 0.14))
            v = min(1.0, v + 0.5 * sp * sp)
            px[x, y] = (int(250 * v), int(238 * v), int(205 * v), int(round(255 * a)))
    d = ImageDraw.Draw(img)
    if cracked:
        pts = [(cx - rx * 0.5, cy - ry * 0.2), (cx - rx * 0.2, cy + ry * 0.05), (cx + rx * 0.05, cy - ry * 0.15),
               (cx + rx * 0.3, cy + ry * 0.1), (cx + rx * 0.55, cy - ry * 0.05)]
        d.line(pts, fill=(90, 70, 50, 255), width=max(1, int(big * 0.025)))
    if hatched:
        # the chick: a yellow blob with an eye, over a zigzag shell edge
        zig = [(cx - rx * 0.95 + k * rx * 1.9 / 8, cy - ry * (0.05 if k % 2 == 0 else 0.2)) for k in range(9)]
        d.polygon(zig + [(cx + rx * 0.95, cy + ry * 0.2), (cx - rx * 0.95, cy + ry * 0.2)], fill=(245, 232, 200, 255))
        d.ellipse([cx - rx * 0.5, cy - ry * 0.6, cx + rx * 0.5, cy + ry * 0.15], fill=(255, 215, 60, 255))
        d.ellipse([cx + rx * 0.1, cy - ry * 0.4, cx + rx * 0.22, cy - ry * 0.28], fill=(40, 40, 40, 255))
        d.polygon([(cx + rx * 0.3, cy - ry * 0.25), (cx + rx * 0.55, cy - ry * 0.18), (cx + rx * 0.3, cy - ry * 0.1)], fill=(255, 140, 40, 255))
    return img


def gem_shape(size, fill, color=(0.35, 0.95, 1.0)):
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = big / 2
    r = c * fill
    pts = [(c + r * math.cos(math.radians(a)), c + r * math.sin(math.radians(a))) for a in range(30, 390, 60)]
    inner = [(c + r * 0.55 * math.cos(math.radians(a)), c + r * 0.55 * math.sin(math.radians(a))) for a in range(30, 390, 60)]
    d.polygon(pts, fill=rgb(color, 0.65))
    for i in range(6):
        a0, a1 = pts[i], pts[(i + 1) % 6]
        b0, b1 = inner[i], inner[(i + 1) % 6]
        d.polygon([a0, a1, b1, b0], fill=rgb(color, 0.5 + 0.4 * ((i * 23) % 100) / 100))
    d.polygon(inner, fill=rgb(color, 1.0))
    return img


def nest_shape(size, fill, lit=False):
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = big / 2
    r = c * fill
    body = (120, 82, 40, 255) if not lit else (190, 150, 90, 255)
    d.ellipse([c - r, c - r * 0.6, c + r, c + r * 0.8], fill=body)
    d.ellipse([c - r * 0.75, c - r * 0.55, c + r * 0.75, c + r * 0.25], fill=(70, 45, 22, 255) if not lit else (150, 110, 60, 255))
    twig = (160, 120, 60, 255) if not lit else (230, 200, 130, 255)
    for k in range(9):
        a0 = k * 0.7
        d.arc([c - r, c - r * 0.6, c + r, c + r * 0.8], start=math.degrees(a0), end=math.degrees(a0) + 70, fill=twig, width=max(1, int(r * 0.06)))
    if lit:
        img = compose(glow(size, radius=0.8, width=0.1, color=(1, 0.95, 0.7)), img)
    return img


def cage_bar(w, h, color):
    img = bar(w, h, 0.9, color, caps=0.06)
    d = ImageDraw.Draw(img)
    bw, bh = img.size
    for k in range(1, 4):
        x = int(bw * k / 4)
        d.rectangle([x - SS, int(bh * 0.1), x + SS, int(bh * 0.9)], fill=(0, 0, 0, 0))
    return img


def rounded_plate(w, h, color, edge_color, border, radius=None, inner=None, rivets=False):
    bw, bh = w * SS, h * SS
    img = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rad = radius if radius is not None else min(bw, bh) // 8
    d.rounded_rectangle([0, 0, bw - 1, bh - 1], radius=rad, fill=rgb(edge_color))
    b = border * SS
    d.rounded_rectangle([b, b, bw - 1 - b, bh - 1 - b], radius=max(1, rad - b), fill=rgb(color))
    if inner is not None:
        b2 = b + inner * SS
        d.rounded_rectangle([b2, b2, bw - 1 - b2, bh - 1 - b2], radius=max(1, rad - b2), fill=rgb(color, 0.85))
    # a gloss band across the top
    px = img.load()
    for y in range(bh):
        v = 1.0 + 0.18 * max(0.0, 1 - y / (bh * 0.35))
        for x in range(bw):
            r, g, bb, a = px[x, y]
            if a:
                px[x, y] = (min(255, int(r * v)), min(255, int(g * v)), min(255, int(bb * v)), a)
    if rivets:
        rr = max(SS * 2, int(min(bw, bh) * 0.025))
        for x, y in ((b * 0.5, b * 0.5), (bw - b * 0.5, b * 0.5), (b * 0.5, bh - b * 0.5), (bw - b * 0.5, bh - b * 0.5)):
            d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=rgb(COPPER_LIGHT))
    return img


def gauge_shape(w, h, filled):
    bw, bh = w * SS, h * SS
    img = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    px = img.load()
    cx, cy = bw / 2, bh - 1
    R, r = bw / 2 - SS, bw / 2 * 0.6
    for y in range(bh):
        for x in range(bw):
            d = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
            if r <= d <= R:
                a = min(1.0, (R - d) / 2, (d - r) / 2)
                if filled:
                    t = math.atan2(cy - (y + 0.5), x + 0.5 - cx) / math.pi  # 1 left .. 0 right
                    hue = 1 - t
                    rr, gg, bb = hue_rgb(hue * 0.75)
                    px[x, y] = (int(255 * rr), int(255 * gg), int(255 * bb), int(255 * a))
                else:
                    px[x, y] = (70, 60, 80, int(255 * a))
    return img


def hue_rgb(h):
    h = h % 1.0
    r = max(0.0, min(1.0, abs(h * 6 - 3) - 1))
    g = max(0.0, min(1.0, 2 - abs(h * 6 - 2)))
    b = max(0.0, min(1.0, 2 - abs(h * 6 - 4)))
    return r, g, b


def ribbon(w, h, color, edge):
    bw, bh = w * SS, h * SS
    img = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    notch = bh * 0.3
    pts = [(0, bh * 0.1), (bw - 1, bh * 0.1), (bw - 1 - notch, bh / 2), (bw - 1, bh * 0.9), (0, bh * 0.9), (notch, bh / 2)]
    d.polygon(pts, fill=rgb(edge))
    inner = [(notch * 0.5, bh * 0.2), (bw - 1 - notch * 0.5, bh * 0.2), (bw - 1 - notch * 1.3, bh / 2), (bw - 1 - notch * 0.5, bh * 0.8), (notch * 0.5, bh * 0.8), (notch * 1.3, bh / 2)]
    d.polygon(inner, fill=rgb(color))
    return img


def backdrop(w, h, top, bottom, stars=0, seed=1):
    import random
    rnd = random.Random(seed)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 255))
    px = img.load()
    for y in range(h):
        t = y / (h - 1)
        c = tuple(int(255 * (top[i] * (1 - t) + bottom[i] * t)) for i in range(3))
        for x in range(w):
            px[x, y] = c + (255,)
    d = ImageDraw.Draw(img)
    for _ in range(stars):
        x, y = rnd.randrange(w), rnd.randrange(h)
        s = rnd.choice((1, 1, 2))
        d.ellipse([x, y, x + s, y + s], fill=(230, 235, 255, rnd.randrange(80, 200)))
    return img


def icon_disc(size, color, glyph=None):
    """A coloured disc with a plate rim: the icons."""
    img = disc(size, 0.92, color, spec=0.3)
    big = size * SS
    d = ImageDraw.Draw(img)
    c = big / 2
    r = c * 0.92
    d.ellipse([c - r, c - r, c + r, c + r], outline=(40, 25, 15, 255), width=max(2, int(big * 0.035)))
    if glyph:
        glyph(d, c, r)
    return img


def g_balls(n):
    def f(d, c, r):
        for k in range(n):
            a = math.pi * 2 * k / max(1, n) - math.pi / 2
            x, y = (c + math.cos(a) * r * 0.4, c + math.sin(a) * r * 0.4) if n > 1 else (c, c)
            d.ellipse([x - r * 0.28, y - r * 0.28, x + r * 0.28, y + r * 0.28], fill=(245, 248, 255, 255))
    return f


def g_dots(d, c, r):
    for k in range(6):
        x, y = c - r * 0.6 + k * r * 0.24, c + r * 0.4 - (k * k) * r * 0.035
        d.ellipse([x - r * 0.07, y - r * 0.07, x + r * 0.07, y + r * 0.07], fill=(255, 255, 255, 255))


def g_burst(d, c, r):
    for k in range(8):
        a = math.pi * 2 * k / 8
        d.line([(c, c), (c + math.cos(a) * r * 0.75, c + math.sin(a) * r * 0.75)], fill=(255, 250, 200, 255), width=max(2, int(r * 0.08)))
    d.ellipse([c - r * 0.25, c - r * 0.25, c + r * 0.25, c + r * 0.25], fill=(255, 255, 255, 255))


def g_flame(d, c, r):
    d.polygon([(c, c - r * 0.75), (c + r * 0.35, c - r * 0.1), (c + r * 0.15, c + r * 0.05), (c + r * 0.3, c + r * 0.5),
               (c, c + r * 0.25), (c - r * 0.3, c + r * 0.5), (c - r * 0.15, c + r * 0.05), (c - r * 0.35, c - r * 0.1)], fill=(255, 220, 90, 255))


def g_ghost(d, c, r):
    d.pieslice([c - r * 0.45, c - r * 0.65, c + r * 0.45, c + r * 0.25], 180, 360, fill=(240, 255, 240, 255))
    d.rectangle([c - r * 0.45, c - r * 0.2, c + r * 0.45, c + r * 0.45], fill=(240, 255, 240, 255))
    for ex in (-0.18, 0.18):
        d.ellipse([c + ex * r - r * 0.08, c - r * 0.35, c + ex * r + r * 0.08, c - r * 0.18], fill=(30, 60, 30, 255))


def g_pyramid(d, c, r):
    d.polygon([(c - r * 0.7, c + r * 0.45), (c + r * 0.7, c + r * 0.45), (c + r * 0.35, c - r * 0.35), (c - r * 0.35, c - r * 0.35)], fill=(255, 225, 120, 255))


def g_bolt(d, c, r):
    d.polygon([(c + r * 0.15, c - r * 0.75), (c - r * 0.35, c + r * 0.05), (c - r * 0.02, c + r * 0.05), (c - r * 0.2, c + r * 0.75),
               (c + r * 0.4, c - r * 0.1), (c + r * 0.05, c - r * 0.1)], fill=(255, 255, 220, 255))


def g_wings(d, c, r):
    g_balls(1)(d, c, r)
    for s in (-1, 1):
        d.polygon([(c + s * r * 0.3, c - r * 0.1), (c + s * r * 0.85, c - r * 0.5), (c + s * r * 0.75, c + r * 0.15)], fill=(255, 255, 255, 255))


def g_ring(d, c, r):
    d.ellipse([c - r * 0.6, c - r * 0.6, c + r * 0.6, c + r * 0.6], outline=(255, 240, 150, 255), width=max(2, int(r * 0.18)))


def g_rainbow(d, c, r):
    for k, h in enumerate((0.0, 0.12, 0.3, 0.55, 0.75)):
        rr = r * (0.75 - k * 0.1)
        col = tuple(int(255 * v) for v in hue_rgb(h)) + (255,)
        d.arc([c - rr, c - rr + r * 0.25, c + rr, c + rr + r * 0.25], 200, 340, fill=col, width=max(2, int(r * 0.1)))


def g_plus(d, c, r):
    d.ellipse([c - r * 0.35, c - r * 0.35, c + r * 0.35, c + r * 0.35], fill=(120, 240, 120, 255))
    d.rectangle([c + r * 0.25, c - r * 0.7, c + r * 0.4, c - r * 0.2], fill=(255, 255, 255, 255))
    d.rectangle([c + r * 0.08, c - r * 0.52, c + r * 0.57, c - r * 0.38], fill=(255, 255, 255, 255))


def g_two(d, c, r):
    for s in (-1, 1):
        d.ellipse([c + s * r * 0.35 - r * 0.25, c - r * 0.25, c + s * r * 0.35 + r * 0.25, c + r * 0.25], fill=(255, 150, 60, 255))
    d.line([(c - r * 0.35, c), (c + r * 0.35, c)], fill=(255, 255, 255, 255), width=max(1, int(r * 0.08)))


def g_vs(d, c, r):
    d.ellipse([c - r * 0.6, c - r * 0.2, c - r * 0.1, c + r * 0.3], fill=(120, 200, 120, 255))
    d.ellipse([c + r * 0.1, c - r * 0.2, c + r * 0.6, c + r * 0.3], fill=(230, 90, 90, 255))


def ball_img(size, fill, kind):
    base = disc(size, fill, highlight=(0.32, 0.30), edge_dark=0.45, spec=0.75)
    big = size * SS
    c = big / 2
    r = c * fill
    if kind == "ball":
        return tint_img(base, (0.92, 0.94, 1.0))
    if kind == "ball_fire":
        img = compose(soft_glow(size, (1, 0.5, 0.1), sigma=0.42), tint_img(base, (1.0, 0.55, 0.2)))
        d = ImageDraw.Draw(img)
        g_flame(d, c, r * 0.9)
        return img
    if kind == "ball_electric":
        img = compose(soft_glow(size, (0.6, 0.8, 1), sigma=0.42), tint_img(base, (0.75, 0.9, 1.0)))
        d = ImageDraw.Draw(img)
        g_bolt(d, c, r * 0.8)
        return img
    if kind == "ball_rainbow":
        img = base.copy()
        px = img.load()
        for y in range(big):
            for x in range(big):
                rr, gg, bb, a = px[x, y]
                if a:
                    h = (math.atan2(y - c, x - c) / (2 * math.pi)) % 1
                    cr, cg, cb = hue_rgb(h)
                    v = rr / 255
                    px[x, y] = (int(255 * min(1, v * (0.45 + 0.55 * cr))), int(255 * min(1, v * (0.45 + 0.55 * cg))), int(255 * min(1, v * (0.45 + 0.55 * cb))), a)
        return img
    if kind == "ball_wing":
        img = Image.new("RGBA", base.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        for s in (-1, 1):
            d.polygon([(c + s * r * 0.5, c - r * 0.1), (c + s * r * 1.35, c - r * 0.75), (c + s * r * 1.2, c + r * 0.2)], fill=(250, 250, 255, 255))
        img.alpha_composite(tint_img(disc(size, fill * 0.7, highlight=(0.32, 0.30), edge_dark=0.45, spec=0.75), (0.95, 0.96, 1.0)))
        return img
    if kind == "ball_spooky":
        img = compose(soft_glow(size, (0.5, 1, 0.6), sigma=0.42), tint_img(base, (0.7, 1.0, 0.75)))
        d = ImageDraw.Draw(img)
        for ex in (-0.22, 0.22):
            d.ellipse([c + ex * r - r * 0.12, c - r * 0.25, c + ex * r + r * 0.12, c], fill=(20, 50, 30, 255))
        return img
    return base


def splash(size_w, size_h, frame):
    bw, bh = size_w * SS, size_h * SS
    img = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx = bw / 2
    spread = 0.25 + 0.25 * frame
    n = 6 + frame * 2
    import random
    rnd = random.Random(frame)
    for k in range(n):
        a = math.pi * (0.15 + 0.7 * k / max(1, n - 1))
        dist = bh * (0.3 + spread) * (0.7 + 0.3 * rnd.random())
        x, y = cx + math.cos(a) * dist * 1.6, bh - math.sin(a) * dist
        rr = bh * (0.06 - 0.01 * frame)
        d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=(255, 255, 255, int(255 * (1 - frame * 0.2))))
    d.ellipse([cx - bw * 0.3, bh * 0.75, cx + bw * 0.3, bh * 1.05], fill=(255, 255, 255, int(200 * (1 - frame * 0.25))))
    return img


def confetti_img(size):
    import random
    rnd = random.Random(7)
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for _ in range(14):
        x, y = rnd.uniform(big * 0.1, big * 0.9), rnd.uniform(big * 0.1, big * 0.9)
        w, h = big * 0.08, big * 0.14
        a = rnd.uniform(0, math.pi)
        col = tuple(int(255 * v) for v in hue_rgb(rnd.random())) + (255,)
        pts = [(x + math.cos(a) * w - math.sin(a) * h, y + math.sin(a) * w + math.cos(a) * h),
               (x - math.cos(a) * w - math.sin(a) * h, y - math.sin(a) * w + math.cos(a) * h),
               (x - math.cos(a) * w + math.sin(a) * h, y - math.sin(a) * w - math.cos(a) * h),
               (x + math.cos(a) * w + math.sin(a) * h, y + math.sin(a) * w - math.cos(a) * h)]
        d.polygon(pts, fill=col)
    return img


def trail_img(w, h):
    bw, bh = w * SS, h * SS
    img = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    px = img.load()
    for y in range(bh):
        t = y / (bh - 1)
        cr, cg, cb = hue_rgb(t * 0.85)
        for x in range(bw):
            fade = min(1.0, (x + 1) / (bw * 0.2), (bw - x) / (bw * 0.2))
            v = 1 - abs(t - 0.5) * 0.4
            px[x, y] = (int(255 * cr), int(255 * cg), int(255 * cb), int(255 * fade * v))
    return img


def star_img(size):
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = big / 2
    pts = []
    for k in range(10):
        a = math.radians(-90 + k * 36)
        r = (big / 2 - SS) if k % 2 == 0 else (big / 2 - SS) * 0.45
        pts.append((c + r * math.cos(a), c + r * math.sin(a)))
    d.polygon(pts, fill=(255, 255, 255, 255))
    small = [(c + (q[0] - c) * 0.5, c + (q[1] - c) * 0.5 - big * 0.04) for q in pts]
    d.polygon(small, fill=(200, 200, 200, 255))
    return img


def crack_img(size):
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = big / 2
    for base in (20, 150, 265):
        x, y = c + big * 0.05 * math.cos(math.radians(base)), c + big * 0.05 * math.sin(math.radians(base))
        a = base
        for step in range(5):
            a += (-1) ** step * 28
            length = big * (0.09 + 0.03 * step)
            nx, ny = x + length * math.cos(math.radians(a)), y + length * math.sin(math.radians(a))
            d.line([(x, y), (nx, ny)], fill=(255, 255, 255, 255), width=SS * (3 - min(2, step // 2)))
            x, y = nx, ny
    return img


def rim_img(size):
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    px = img.load()
    c = big / 2
    for y in range(big):
        for x in range(big):
            dd = math.hypot(x + 0.5 - c, y + 0.5 - c) / (big / 2)
            a = 0.0
            if 0.78 <= dd <= 0.98:
                a = 1.0
                if dd < 0.81:
                    a = (dd - 0.78) / 0.03
                elif dd > 0.95:
                    a = (0.98 - dd) / 0.03
            v = 1.0 - 0.35 * ((y / big) ** 1.2)
            g = int(round(255 * v))
            px[x, y] = (g, g, g, int(round(255 * max(0.0, min(1.0, a)))))
    return img


def dot_img(size):
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    px = img.load()
    c = big / 2
    for y in range(big):
        for x in range(big):
            d = math.hypot(x + 0.5 - c, y + 0.5 - c) / (big / 2)
            a = 1.0 if d < 0.55 else max(0.0, 1.0 - (d - 0.55) / 0.35)
            px[x, y] = (255, 255, 255, int(round(255 * a)))
    return img


def pyramid_img(w, h):
    bw, bh = w * SS, h * SS
    img = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    top = int(bh * 0.25)
    d.polygon([(int(bw * 0.06), top), (bw - 1 - int(bw * 0.06), top), (bw - 1, bh - 1), (0, bh - 1)], fill=(235, 190, 70, 255))
    d.polygon([(int(bw * 0.06), top), (bw - 1 - int(bw * 0.06), top), (bw - 1 - int(bw * 0.08), top + SS * 3), (int(bw * 0.08), top + SS * 3)], fill=(255, 235, 150, 255))
    for k in range(1, 12):
        x = int(bw * k / 12)
        d.line([(x, top + SS * 3), (x, bh - 1)], fill=(170, 120, 30, 255), width=SS)
    return img


def step_pyramid_img(w, h, stage=0):
    """A sandstone step pyramid: five tiers whose step noses sit on the
    line from the base corners to the peak, under a gold capstone. Stage
    1-4 chips the steps and cracks the blocks, more at each stage."""
    import random
    bw, bh = w * SS, h * SS
    img = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    tiers, th = 5, 0.16
    sand, tread, mortar, shade = (214, 178, 108, 255), (240, 214, 150, 255), (150, 112, 60, 255), (178, 140, 80, 255)
    for i in range(tiers):
        y1 = bh * (1 - i * th)
        y0 = bh * (1 - (i + 1) * th)
        half = bw / 2 * (1 - (i + 1) * th)
        x0, x1 = bw / 2 - half, bw / 2 + half
        d.rectangle([x0, y0, x1, y1], fill=sand)
        d.rectangle([x0, y0, x1, y0 + SS * 2], fill=tread)
        d.rectangle([bw / 2, y0 + SS * 2, x1, y1], fill=shade)
        # block joints
        n = max(2, int(half * 2 / (SS * 22)))
        for k in range(1, n):
            x = x0 + (x1 - x0) * (k + (0.5 if i % 2 else 0)) / n
            if x0 < x < x1:
                d.line([(x, y0 + SS * 2), (x, y1)], fill=mortar, width=SS)
        d.line([(x0, y1 - 1), (x1, y1 - 1)], fill=mortar, width=SS)
    capy = bh * (1 - tiers * th)
    caph = bw / 2 * (1 - tiers * th)
    d.polygon([(bw / 2, 0), (bw / 2 + caph, capy), (bw / 2 - caph, capy)], fill=(250, 205, 70, 255))
    d.polygon([(bw / 2, 0), (bw / 2 + caph, capy), (bw / 2, capy)], fill=(215, 165, 40, 255))
    if stage:
        rnd = random.Random(stage * 7 + 3)
        for _ in range(stage * 7):
            # a chip out of a step's edge
            i = rnd.randrange(tiers)
            y0 = bh * (1 - (i + 1) * th)
            half = bw / 2 * (1 - (i + 1) * th)
            side = rnd.choice((-1, 1))
            cx = bw / 2 + side * (half - rnd.uniform(0, half * 0.7))
            r = SS * rnd.uniform(4, 6 + stage * 2.5)
            d.ellipse([cx - r, y0 - r * 0.6, cx + r, y0 + r * 0.9], fill=(0, 0, 0, 0))
        for _ in range(stage * 4):
            # cracks
            x = rnd.uniform(bw * 0.2, bw * 0.8)
            y = rnd.uniform(bh * 0.3, bh * 0.95)
            pts = [(x, y)]
            for _ in range(4):
                x += rnd.uniform(-SS * 9, SS * 9)
                y += rnd.uniform(-SS * 7, SS * 4)
                pts.append((x, y))
            d.line(pts, fill=(90, 62, 30, 255), width=SS * (1 + stage // 2))
        if stage >= 3:
            # the capstone loosened and tipped
            d.polygon([(bw / 2, 0), (bw / 2 + caph, capy), (bw / 2 - caph, capy)], fill=(0, 0, 0, 0))
            off = SS * 6 * (stage - 2)
            d.polygon([(bw / 2 + off, SS * 4 * (stage - 2)), (bw / 2 + caph + off, capy), (bw / 2 - caph + off * 0.6, capy)], fill=(225, 175, 55, 255))
    return img


def web_img(size, fill=0.7):
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = big / 2
    r = big * fill / 2
    col = (225, 228, 240, 235)
    w = max(1, SS)
    spokes = 8
    for k in range(spokes):
        a = k * 2 * math.pi / spokes + 0.2
        d.line([(c, c), (c + math.cos(a) * r, c + math.sin(a) * r)], fill=col, width=w)
    for ring in (0.28, 0.5, 0.72, 0.95):
        pts = []
        for k in range(spokes + 1):
            a = k * 2 * math.pi / spokes + 0.2
            rr = r * ring * (0.92 if k % 2 else 1.0)
            pts.append((c + math.cos(a) * rr, c + math.sin(a) * rr))
        d.line(pts, fill=col, width=w)
    d.ellipse([c - SS * 2, c - SS * 2, c + SS * 2, c + SS * 2], fill=col)
    return img


def platform_img(w, h):
    """A round hover platform seen from straight above."""
    bw, bh = w * SS, h * SS
    from PIL import ImageFilter
    img = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    glow = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([bw * 0.02, bh * 0.02, bw * 0.98, bh * 0.98], fill=(90, 170, 255, 150))
    img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(SS * 3)))
    d = ImageDraw.Draw(img)
    d.ellipse([bw * 0.08, bh * 0.08, bw * 0.92, bh * 0.92], fill=(205, 160, 70, 255))     # brass rim
    d.ellipse([bw * 0.15, bh * 0.15, bw * 0.85, bh * 0.85], fill=(118, 126, 138, 255))    # steel deck
    d.ellipse([bw * 0.3, bh * 0.3, bw * 0.7, bh * 0.7], outline=(160, 168, 180, 255), width=SS * 2)
    for k in range(4):
        a = k * math.pi / 4
        d.line([(bw / 2 + math.cos(a) * bw * 0.2, bh / 2 + math.sin(a) * bh * 0.2),
                (bw / 2 + math.cos(a) * bw * 0.34, bh / 2 + math.sin(a) * bh * 0.34)], fill=(95, 102, 114, 255), width=SS * 2)
        d.line([(bw / 2 - math.cos(a) * bw * 0.2, bh / 2 - math.sin(a) * bh * 0.2),
                (bw / 2 - math.cos(a) * bw * 0.34, bh / 2 - math.sin(a) * bh * 0.34)], fill=(95, 102, 114, 255), width=SS * 2)
    for k in range(12):
        a = k * 2 * math.pi / 12
        x, y = bw / 2 + math.cos(a) * bw * 0.385, bh / 2 + math.sin(a) * bh * 0.385
        r = SS * 2.2
        d.ellipse([x - r, y - r, x + r, y + r], fill=(250, 220, 140, 255))
    return img


def platform_img_side(w, h):
    bw, bh = w * SS, h * SS
    img = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    glow = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([bw * 0.12, bh * 0.45, bw * 0.88, bh * 0.98], fill=(90, 170, 255, 150))
    from PIL import ImageFilter
    img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(SS * 4)))
    d = ImageDraw.Draw(img)
    d.ellipse([bw * 0.04, bh * 0.22, bw * 0.96, bh * 0.78], fill=(150, 110, 45, 255))     # brass side
    d.ellipse([bw * 0.04, bh * 0.12, bw * 0.96, bh * 0.66], fill=(205, 160, 70, 255))     # brass rim
    d.ellipse([bw * 0.1, bh * 0.17, bw * 0.9, bh * 0.61], fill=(120, 128, 140, 255))      # steel top
    d.ellipse([bw * 0.2, bh * 0.24, bw * 0.8, bh * 0.54], outline=(160, 168, 180, 255), width=SS)
    for k in range(12):
        a = k * 2 * math.pi / 12
        x = bw / 2 + math.cos(a) * bw * 0.43
        y = bh * 0.39 + math.sin(a) * bh * 0.245
        r = SS * 1.4
        d.ellipse([x - r, y - r, x + r, y + r], fill=(250, 220, 140, 255))
    return img


def dust_img(size):
    import random
    rnd = random.Random(11)
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    for _ in range(46):
        r = rnd.uniform(0.1, 0.24) * big
        a = rnd.uniform(0, 6.283)
        dd = rnd.uniform(0, 0.28) * big
        cx, cy = big / 2 + math.cos(a) * dd, big / 2 + math.sin(a) * dd * 0.8
        blob = Image.new("RGBA", (big, big), (0, 0, 0, 0))
        ImageDraw.Draw(blob).ellipse([cx - r, cy - r, cx + r, cy + r],
                                     fill=(int(rnd.uniform(190, 230)), int(rnd.uniform(160, 195)), int(rnd.uniform(105, 135)), int(rnd.uniform(40, 80))))
        img = Image.alpha_composite(img, blob)
    from PIL import ImageFilter
    img = img.filter(ImageFilter.GaussianBlur(SS * 3))
    d = ImageDraw.Draw(img)
    for _ in range(40):
        x, y = rnd.uniform(0.15, 0.85) * big, rnd.uniform(0.2, 0.85) * big
        r = rnd.uniform(1, 2.5) * SS
        d.ellipse([x - r, y - r, x + r, y + r], fill=(150, 112, 62, 230))
    return img


def bucket_img(w, h, color=(70, 86, 110), lip=(190, 205, 230)):
    bw, bh = w * SS, h * SS
    img = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    top = int(bh * 0.18)
    inset = int(bw * 0.06)
    inner = tuple(int(v * 0.55) for v in color)
    d.polygon([(0, top), (bw - 1, top), (bw - 1 - inset, bh - 1), (inset, bh - 1)], fill=color + (255,))
    hol = int(bw * 0.07)
    d.polygon([(hol, top), (bw - 1 - hol, top), (bw - 1 - inset - hol // 2, bh - 1 - SS * 3), (inset + hol // 2, bh - 1 - SS * 3)], fill=inner + (255,))
    lip_w = int(bw * 0.08)
    d.rectangle([0, 0, lip_w, top + SS * 2], fill=lip + (255,))
    d.rectangle([bw - 1 - lip_w, 0, bw - 1, top + SS * 2], fill=lip + (255,))
    d.rectangle([0, top, bw - 1, top + SS], fill=lip + (255,))
    return img


def launcher_barrel(w, h):
    bw, bh = w * SS, h * SS
    img = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([bw * 0.2, 0, bw * 0.8, bh - 1], radius=bw * 0.1, fill=rgb(COPPER))
    d.rectangle([bw * 0.12, bh * 0.05, bw * 0.88, bh * 0.2], fill=rgb(COPPER_LIGHT))
    d.rectangle([bw * 0.12, bh * 0.8, bw * 0.88, bh * 0.95], fill=rgb(COPPER_LIGHT))
    d.rectangle([bw * 0.3, bh * 0.2, bw * 0.4, bh * 0.8], fill=rgb(COPPER_LIGHT, 0.9))
    return img


def addon_icon():
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    peg = finish(disc(30, 0.95, spec=0.25), 30, 30)
    img.alpha_composite(finish(bar(44, 14, 0.95, (0.3, 0.6, 1.0)), 44, 14), (10, 46))
    img.alpha_composite(tint_img(peg, (1.0, 0.55, 0.12)), (30, 18))
    img.alpha_composite(tint_img(peg, (0.3, 0.6, 1.0)), (4, 22))
    img.alpha_composite(tint_img(finish(disc(22, 0.95, spec=0.6), 22, 22), (0.9, 0.92, 0.98)), (20, 0))
    return img


# ---------------------------------------------------------------- the makers

def load_base(name, maker, from_base):
    """The white source a per-colour set is derived from: the painted file
    on disk with --from-base, else freshly generated (supersampled)."""
    path = os.path.join(OUT, name + ".tga")
    if from_base and os.path.exists(path):
        img = Image.open(path).convert("RGBA")
        return img.resize((img.width * SS, img.height * SS), Image.LANCZOS)
    return maker()


def make_all(slots, only, from_base):
    want = set(only) if only else None
    by = {s["name"]: s for s in slots}
    made = {}

    def put(name, img):
        if name not in by:
            return
        if want and name not in want:
            return
        s = by[name]
        out = img if img.size == (s["w"], s["h"]) else finish(img, s["w"], s["h"])
        out.save(os.path.join(OUT, name + ".tga"), format="TGA")
        made[name] = out
        print("wrote", name, out.size)

    fill_peg, fill_brick, fill_key, fill_boss = 0.7, 0.9, 0.8, 0.7
    peg_base = load_base("peg", lambda: disc(64, fill_peg, spec=0.3), from_base)
    brick_base = load_base("brick", lambda: bar(64, 32, fill_brick), from_base)
    key_base = load_base("key", lambda: key_shape(64, fill_key, (1, 1, 1)), from_base)
    boss_base = load_base("boss", lambda: boss_face(64, fill_boss, (1, 1, 1)), from_base)
    if not from_base:
        put("peg", peg_base)
        put("brick", brick_base)
        put("key", key_base)
        put("boss", boss_base)
    put("ring", glow(64))
    put("rim", rim_img(64))
    put("crack", crack_img(64))
    put("dot", dot_img(32))
    put("star", star_img(32))
    put("blast", burst(128))
    put("pyramid", step_pyramid_img(512, 128))
    for i in range(1, 5):
        put("pyramid_crumble%d" % i, step_pyramid_img(512, 128, i))
    put("pyramid_dust", dust_img(128))
    put("web", web_img(64))
    put("boss_platform", platform_img(128, 128))
    put("icon", addon_icon())

    for c, (body, hi) in COLORS.items():
        base = tint_img(peg_base, body)
        put("peg_" + c, base)
        put("peg_%s_lit" % c, lit_piece(base, 64, hi))
        put("peg_%s_gone" % c, shards(64, fill_peg, body))
        bb = tint_img(brick_base, body)
        put("brick_" + c, bb)
        put("brick_%s_lit" % c, lit_piece(bb, 64, hi).resize(bb.size) if False else compose(bb, tint_img(bb, (1.6, 1.6, 1.6))))
        put("brick_%s_gone" % c, shards(64, 0.9, body).resize(bb.size))
    bump = tint_img(peg_base, (1.0, 0.35, 0.6))
    db = ImageDraw.Draw(bump)
    c = bump.width / 2
    pts = []
    for k in range(10):
        a = math.radians(-90 + k * 36)
        r = c * fill_peg * (0.55 if k % 2 == 0 else 0.25)
        pts.append((c + r * math.cos(a), c + r * math.sin(a)))
    db.polygon(pts, fill=(255, 255, 255, 255))
    put("bumper", bump)
    blk = tint_img(peg_base, (0.42, 0.42, 0.48))
    db = ImageDraw.Draw(blk)
    for k in range(4):
        a = math.radians(45 + k * 90)
        x, y = c + math.cos(a) * c * fill_peg * 0.6, c + math.sin(a) * c * fill_peg * 0.6
        db.ellipse([x - c * 0.06, y - c * 0.06, x + c * 0.06, y + c * 0.06], fill=(150, 150, 160, 255))
    put("block", blk)
    put("rail", bar(64, 32, fill_brick, (0.42, 0.42, 0.48), caps=0.08))
    put("cage_gold", cage_bar(64, 32, (0.85, 0.68, 0.25)))
    put("cage_silver", cage_bar(64, 32, (0.72, 0.78, 0.88)))
    put("key_gold", tint_img(key_base, (1.0, 0.85, 0.3)))
    put("key_silver", tint_img(key_base, (0.8, 0.88, 1.0)))

    put("egg", egg_shape(64, 0.8))
    put("egg_cracked", egg_shape(64, 0.8, cracked=True))
    put("egg_hatched", egg_shape(64, 0.8, hatched=True))
    put("gem", gem_shape(64, 0.8))
    for bid, tintc in BOSS_TINT.items():
        if from_base:
            put("boss_" + bid, tint_img(boss_base, tintc))
        else:
            put("boss_" + bid, boss_face(64, fill_boss, tintc, kind=bid))

    for kind in ("ball", "ball_fire", "ball_electric", "ball_rainbow", "ball_wing", "ball_spooky"):
        put(kind, ball_img(64, 0.8, kind))
    put("ball_small", tint_img(disc(32, 0.9, highlight=(0.32, 0.30), edge_dark=0.45, spec=0.75), (0.92, 0.94, 1.0)))

    put("launcher_barrel", launcher_barrel(32, 64))
    hub = tint_img(disc(64, 0.95, spec=0.2), COPPER_LIGHT)
    dh = ImageDraw.Draw(hub)
    for k in range(6):
        a = math.radians(k * 60)
        x, y = hub.width / 2 + math.cos(a) * hub.width * 0.36, hub.height / 2 + math.sin(a) * hub.height * 0.36
        dh.ellipse([x - SS * 2, y - SS * 2, x + SS * 2, y + SS * 2], fill=rgb(TRIM))
    put("launcher_hub", hub)
    put("launcher_flash", burst(64, spikes=7, inner=0.4))
    put("bucket", bucket_img(128, 128, (150, 82, 40), (220, 160, 90)))
    for i in range(1, 5):
        put("bucket_splash%d" % i, splash(128, 128, i - 1))
    suck = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    tube = finish(bucket_img(128, 128, (150, 82, 40), (220, 160, 90)), 128, 128)
    for k in range(16):
        sq = 1 + 0.08 * math.sin(k / 16 * 2 * math.pi)
        f = tube.resize((int(128 * sq), int(128 / sq)), Image.LANCZOS)
        suck.alpha_composite(f, ((k % 4) * 128 + (128 - f.width) // 2, (k // 4) * 128 + (128 - f.height) // 2))
    if "bucket_suck" not in [n for n in made] and not os.path.exists(os.path.join(OUT, "bucket_suck.tga")):
        put("bucket_suck", suck)
    tube = bucket_img(128, 128, (150, 100, 40), (230, 190, 110))
    put("fever_tube", tube)
    for letter in "gnome":
        for lit in (False, True):
            img = tint_img(tube, (1.3, 1.3, 1.1)) if lit else tube.copy()
            text_on(img, letter.upper(), 0.6, (255, 240, 150, 255) if lit else (250, 200, 70, 255))
            put("fever_tube_%s%s" % (letter, "_lit" if lit else ""), img)

    power_glyph = {
        "multiball": ((0.25, 0.5, 0.9), g_balls(2)), "guide": ((0.3, 0.7, 0.4), g_dots), "blast": ((0.9, 0.5, 0.15), g_burst),
        "fireball": ((0.9, 0.3, 0.1), g_flame), "spooky": ((0.3, 0.6, 0.35), g_ghost), "pyramid": ((0.8, 0.65, 0.2), g_pyramid),
        "lightning": ((0.3, 0.45, 0.85), g_bolt), "frenzy": ((0.85, 0.7, 0.2), g_wings),
    }
    for pid, (col, gl) in power_glyph.items():
        put("power_" + pid, icon_disc(64, col, gl))
    for iid, (col, gl) in {"ring": ((0.85, 0.4, 0.15), g_ring), "rainbow": ((0.5, 0.3, 0.7), g_rainbow), "green": ((0.25, 0.6, 0.3), g_plus), "suction": ((0.6, 0.45, 0.2), g_ring)}.items():
        put("item_" + iid, icon_disc(64, col, gl))
    goal_glyph = {
        "orange": ((0.95, 0.42, 0.11), None), "egg": ((0.9, 0.85, 0.7), None), "gem": ((0.35, 0.95, 1.0), None),
        "boss": ((0.8, 0.25, 0.25), None), "duel": ((0.5, 0.4, 0.6), g_vs), "longshot": ((0.9, 0.75, 0.2), g_two),
    }
    for gid, (col, gl) in goal_glyph.items():
        put("goal_" + gid, icon_disc(32, col, gl))

    put("frame_bg", rounded_plate(512, 512, COPPER, TRIM, 32, radius=48, inner=8, rivets=True))
    put("plate", rounded_plate(256, 64, (0.22, 0.12, 0.08), COPPER_LIGHT, 16 // 2, radius=28))
    put("card", rounded_plate(512, 512, (0.13, 0.09, 0.24), PARCHMENT_EDGE, 32, radius=56, inner=6))
    for name, col, edge in (("green", (0.25, 0.78, 0.23), (0.12, 0.48, 0.11)), ("orange", (0.94, 0.54, 0.16), (0.64, 0.28, 0.1)), ("grey", (0.45, 0.42, 0.55), (0.25, 0.22, 0.32))):
        put("button_" + name, rounded_plate(256, 64, col, edge, 16 // 2, radius=30))
        put("button_%s_down" % name, rounded_plate(256, 64, tuple(v * 0.7 for v in col), edge, 16 // 2, radius=30))
    put("gauge", rounded_plate(256, 64, (0.18, 0.1, 0.07), COPPER_LIGHT, 16 // 2, radius=28))
    fillbar = bar(256, 64, 0.8, (1, 1, 1))
    px = fillbar.load()
    for y in range(fillbar.height):
        for x in range(fillbar.width):
            r, g, b, a = px[x, y]
            if a:
                cr, cg, cb = hue_rgb(x / fillbar.width * 0.85)
                v = r / 255
                px[x, y] = (int(255 * cr * v), int(255 * cg * v), int(255 * cb * v), a)
    put("gauge_fill", fillbar)
    put("fever_balloon", tint_img(disc(64, 0.8, spec=0.6), (0.75, 0.35, 0.95)))
    logo = ribbon(512, 128, NAVY, PARCHMENT)
    text_on(logo, "GNOMISH PACHINKO", 0.4, (255, 215, 80, 255))
    put("logo", logo)
    put("portrait_frame", tint_img(rim_img(128), COPPER_LIGHT))
    put("banner", ribbon(512, 64, NAVY, PARCHMENT))
    fever = ribbon(512, 128, (0.45, 0.15, 0.6), (1.0, 0.85, 0.3))
    text_on(fever, "FEVER!", 0.55, (255, 240, 150, 255))
    put("callout_fever", fever)
    put("map_node", rounded_plate(64, 64, (0.55, 0.42, 0.25), (0.3, 0.2, 0.1), 4, radius=32 * SS))
    put("map_node_done", rounded_plate(64, 64, (0.25, 0.6, 0.3), (0.12, 0.35, 0.15), 4, radius=32 * SS))
    put("map_node_locked", rounded_plate(64, 64, (0.3, 0.3, 0.34), (0.18, 0.18, 0.2), 4, radius=32 * SS))
    put("map_node_boss", rounded_plate(64, 64, (0.65, 0.25, 0.2), (0.9, 0.3, 0.3), 5, radius=32 * SS))
    for s in slots:
        if s["name"].startswith("map_bg_"):
            put(s["name"], backdrop(s["w"], s["h"], (0.1, 0.08, 0.22), (0.05, 0.04, 0.12), stars=60, seed=1))
        if s["name"].startswith("field_bg_"):
            put(s["name"], backdrop(s["w"], s["h"], (0.05, 0.06, 0.2), (0.02, 0.03, 0.1), stars=90, seed=2))
        if s["name"].startswith("field_boss_"):
            put(s["name"], backdrop(s["w"], s["h"], (0.2, 0.04, 0.06), (0.06, 0.02, 0.04), stars=30, seed=3))
    mm = tint_img(disc(64, 0.95, spec=0.3), (0.36, 0.20, 0.52))
    text_on(mm, "GP", 0.42, (255, 215, 50, 255))
    put("minimap", mm)

    for i in range(1, 5):
        put("spark%d" % i, sparkle(64, length=0.5 + 0.15 * i, thick=0.12 - 0.02 * i, core=0.22 - 0.03 * i))
    put("confetti", confetti_img(64))
    put("phoenix", compose(soft_glow(128, (1, 0.5, 0.1), sigma=0.4), sparkle(128, (1, 0.75, 0.3), arms=3, length=0.9, thick=0.25, core=0.2)))
    put("firework", burst(128, spikes=18, inner=0.3))
    put("trail", trail_img(64, 16))
    put("glow_soft", soft_glow(128))
    return made


def contact_sheet(slots, path):
    cols = 10
    cell = 96
    rows = (len(slots) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell, rows * (cell + 14)), (40, 40, 48, 255))
    d = ImageDraw.Draw(sheet)
    for i, s in enumerate(slots):
        p = os.path.join(OUT, s["name"] + ".tga")
        if not os.path.exists(p):
            continue
        img = Image.open(p).convert("RGBA")
        scale = min((cell - 8) / img.width, (cell - 8) / img.height, 1.0)
        img = img.resize((max(1, int(img.width * scale)), max(1, int(img.height * scale))), Image.LANCZOS)
        x, y = (i % cols) * cell, (i // cols) * (cell + 14)
        sheet.alpha_composite(img, (x + (cell - img.width) // 2, y + (cell - img.height) // 2))
        d.text((x + 3, y + cell), s["name"][:18], fill=(220, 220, 220, 255))
    sheet.save(path)
    print("contact sheet", path)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*")
    ap.add_argument("--from-base", action="store_true")
    ap.add_argument("--sheet")
    args = ap.parse_args()
    slots = read_slots()
    print(len(slots), "slots in Art.lua")
    make_all(slots, args.only, args.from_base)
    missing = [s["name"] for s in slots if not os.path.exists(os.path.join(OUT, s["name"] + ".tga"))]
    if missing:
        print("NO MAKER FOR:", ", ".join(missing))
        sys.exit(1)
    if args.sheet:
        contact_sheet(slots, args.sheet)
