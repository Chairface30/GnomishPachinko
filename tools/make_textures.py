"""Generate Textures/*.tga for Gnomish Pachinko.

peg.tga / ball.tga are white shaded discs the window tints with
SetVertexColor, brick.tga a white shaded rounded bar for bricks, ring.tga
the glow a lit peg wears, dot.tga one aim-guide dot, bucket.tga the
free-ball cup, icon.tga the addon icon. Power-of-two, 32-bit TGA.

PLACEHOLDERS (to be replaced by real art, same names and sizes):
  egg.tga     64x64   an egg (white, tinted cream in game)
  gem.tga     64x64   a cut gem (white, tinted cyan in game)
  boss.tga    64x64   a round mechanical boss face (white, tinted per boss)
  crack.tga   64x64   crack lines, transparent elsewhere (drawn over a damaged piece)
  rim.tga     64x64   a thin ring, the steel rim of a tough peg
  star.tga    32x32   a five-point star (gold when earned, gray when not)
  pyramid.tga 256x32  a wide trapezoid bar, the Pyramid power
  blast.tga   128x128 a soft radial burst, the Space Blast explosion

Run: python tools/make_textures.py   (pip install pillow)
"""
import math
import os

from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Textures")
os.makedirs(OUT, exist_ok=True)

SS = 4


def shaded_disc(size, highlight=(0.35, 0.35), edge_dark=0.55, spec=0.0):
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    px = img.load()
    c = big / 2
    r = big / 2 - SS
    hx, hy = big * highlight[0], big * highlight[1]
    for y in range(big):
        for x in range(big):
            d = math.hypot(x + 0.5 - c, y + 0.5 - c)
            if d > r + 1:
                continue
            a = max(0.0, min(1.0, r + 1 - d))
            hd = math.hypot(x + 0.5 - hx, y + 0.5 - hy) / (big * 0.9)
            v = 1.0 - (1.0 - edge_dark) * min(1.0, hd ** 1.1)
            if spec > 0:
                s = max(0.0, 1.0 - math.hypot(x + 0.5 - hx, y + 0.5 - hy) / (big * 0.16))
                v = min(1.0, v + spec * s * s)
            g = int(round(255 * v))
            px[x, y] = (g, g, g, int(round(255 * a)))
    return img.resize((size, size), Image.LANCZOS)


def shaded_brick(w, h):
    """A rounded bar lit from the top, filling the whole texture so the
    window can size it to any brick."""
    bw, bh = w * SS, h * SS
    img = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rad = bh // 3
    d.rounded_rectangle([0, 0, bw - 1, bh - 1], radius=rad, fill=(255, 255, 255, 255))
    px = img.load()
    for y in range(bh):
        # bright top edge to darker bottom, a little bevel on the ends
        v = 1.0 - 0.45 * (y / (bh - 1)) ** 1.2
        for x in range(bw):
            r_, g_, b_, a = px[x, y]
            if a == 0:
                continue
            edge = min(x, bw - 1 - x) / (bw * 0.08)
            vv = v * (0.75 + 0.25 * min(1.0, edge))
            g = int(round(255 * vv))
            px[x, y] = (g, g, g, a)
    return img.resize((w, h), Image.LANCZOS)


def glow_ring(size, radius=0.70, width=0.16):
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    px = img.load()
    c = big / 2
    for y in range(big):
        for x in range(big):
            d = math.hypot(x + 0.5 - c, y + 0.5 - c) / (big / 2)
            a = math.exp(-((d - radius) ** 2) / (2 * width * width))
            if d > 0.98:
                a *= max(0.0, (1.0 - d) / 0.02)
            px[x, y] = (255, 255, 255, int(round(255 * min(1.0, a))))
    return img.resize((size, size), Image.LANCZOS)


def soft_dot(size):
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    px = img.load()
    c = big / 2
    for y in range(big):
        for x in range(big):
            d = math.hypot(x + 0.5 - c, y + 0.5 - c) / (big / 2)
            a = 1.0 if d < 0.55 else max(0.0, 1.0 - (d - 0.55) / 0.35)
            px[x, y] = (255, 255, 255, int(round(255 * a)))
    return img.resize((size, size), Image.LANCZOS)


def bucket(w, h):
    big_w, big_h = w * SS, h * SS
    img = Image.new("RGBA", (big_w, big_h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    top = int(big_h * 0.18)
    inset = int(big_w * 0.06)
    body = (70, 86, 110, 255)
    inner = (38, 46, 60, 255)
    rim = (190, 205, 230, 255)
    d.polygon([(0, top), (big_w - 1, top), (big_w - 1 - inset, big_h - 1), (inset, big_h - 1)], fill=body)
    hol = int(big_w * 0.07)
    d.polygon([(hol, top), (big_w - 1 - hol, top), (big_w - 1 - inset - hol // 2, big_h - 1 - SS * 3),
               (inset + hol // 2, big_h - 1 - SS * 3)], fill=inner)
    lip_w = int(big_w * 0.08)
    d.rectangle([0, 0, lip_w, top + SS * 2], fill=rim)
    d.rectangle([big_w - 1 - lip_w, 0, big_w - 1, top + SS * 2], fill=rim)
    d.rectangle([0, top, big_w - 1, top + SS], fill=rim)
    return img.resize((w, h), Image.LANCZOS)


def tint(img, rgb):
    r, g, b = rgb
    out = img.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            v, _, _, a = px[x, y]
            px[x, y] = (int(v * r), int(v * g), int(v * b), a)
    return out


def icon():
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    peg = shaded_disc(30, spec=0.25)
    img.alpha_composite(tint(shaded_brick(44, 14), (0.3, 0.6, 1.0)), (10, 46))
    img.alpha_composite(tint(peg, (1.0, 0.55, 0.12)), (30, 18))
    img.alpha_composite(tint(peg, (0.3, 0.6, 1.0)), (4, 22))
    ball = shaded_disc(22, spec=0.6)
    img.alpha_composite(tint(ball, (0.9, 0.92, 0.98)), (20, 0))
    return img


def egg(size):
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    px = img.load()
    cx, cy = big / 2, big / 2
    rx, ry = big * 0.36, big * 0.46
    for y in range(big):
        for x in range(big):
            # a slightly pointed top: narrower above the middle
            dy = (y + 0.5 - cy) / ry
            squeeze = 1.0 - 0.12 * max(0.0, -dy)
            dx = (x + 0.5 - cx) / (rx * squeeze)
            d = math.hypot(dx, dy)
            if d > 1.03:
                continue
            a = max(0.0, min(1.0, (1.03 - d) / 0.03))
            hd = math.hypot(x + 0.5 - big * 0.4, y + 0.5 - big * 0.33) / (big * 0.9)
            v = 1.0 - 0.45 * min(1.0, hd ** 1.1)
            sp = max(0.0, 1.0 - math.hypot(x + 0.5 - big * 0.4, y + 0.5 - big * 0.3) / (big * 0.14))
            v = min(1.0, v + 0.5 * sp * sp)
            g = int(round(255 * v))
            px[x, y] = (g, g, g, int(round(255 * a)))
    return img.resize((size, size), Image.LANCZOS)


def gem(size):
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = big / 2
    r = big / 2 - SS
    # a hexagonal cut stone with a brighter table in the middle
    pts = [(c + r * math.cos(math.radians(a)), c + r * math.sin(math.radians(a))) for a in range(30, 390, 60)]
    inner = [(c + r * 0.55 * math.cos(math.radians(a)), c + r * 0.55 * math.sin(math.radians(a))) for a in range(30, 390, 60)]
    d.polygon(pts, fill=(170, 170, 170, 255))
    for i in range(6):
        a0, a1 = pts[i], pts[(i + 1) % 6]
        b0, b1 = inner[i], inner[(i + 1) % 6]
        shade = 120 + (i * 23) % 100
        d.polygon([a0, a1, b1, b0], fill=(shade, shade, shade, 255))
    d.polygon(inner, fill=(245, 245, 245, 255))
    return img.resize((size, size), Image.LANCZOS)


def boss(size):
    img = shaded_disc(size, highlight=(0.4, 0.35), edge_dark=0.5, spec=0.2)
    big = size * SS
    face = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(face)
    c = big / 2
    # gear teeth round the rim
    for k in range(12):
        a = math.radians(k * 30)
        x, y = c + c * 0.93 * math.cos(a), c + c * 0.93 * math.sin(a)
        d.ellipse([x - big * 0.07, y - big * 0.07, x + big * 0.07, y + big * 0.07], fill=(200, 200, 200, 255))
    face = face.resize((size, size), Image.LANCZOS)
    img.alpha_composite(face)
    # two dark eyes and a jagged mouth
    d2 = ImageDraw.Draw(img)
    e = size * 0.09
    d2.ellipse([size * 0.3 - e, size * 0.38 - e, size * 0.3 + e, size * 0.38 + e], fill=(40, 40, 40, 255))
    d2.ellipse([size * 0.7 - e, size * 0.38 - e, size * 0.7 + e, size * 0.38 + e], fill=(40, 40, 40, 255))
    zig = []
    for k in range(7):
        zig.append((size * (0.28 + 0.44 * k / 6), size * (0.66 if k % 2 == 0 else 0.72)))
    d2.line(zig, fill=(40, 40, 40, 255), width=max(1, size // 24))
    return img


def crack(size):
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = big / 2
    w = max(1, SS)
    # three jagged cracks from near the centre outward
    for base in (20, 150, 265):
        x, y = c + big * 0.05 * math.cos(math.radians(base)), c + big * 0.05 * math.sin(math.radians(base))
        a = base
        for step in range(5):
            a += (-1) ** step * 28
            length = big * (0.09 + 0.03 * step)
            nx, ny = x + length * math.cos(math.radians(a)), y + length * math.sin(math.radians(a))
            d.line([(x, y), (nx, ny)], fill=(255, 255, 255, 255), width=w * (3 - min(2, step // 2)))
            x, y = nx, ny
    return img.resize((size, size), Image.LANCZOS)


def rim(size):
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
    return img.resize((size, size), Image.LANCZOS)


def star(size):
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
    return img.resize((size, size), Image.LANCZOS)


def pyramid(w, h):
    bw, bh = w * SS, h * SS
    img = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    top = int(bh * 0.25)
    d.polygon([(int(bw * 0.06), top), (bw - 1 - int(bw * 0.06), top), (bw - 1, bh - 1), (0, bh - 1)], fill=(235, 190, 70, 255))
    d.polygon([(int(bw * 0.06), top), (bw - 1 - int(bw * 0.06), top), (bw - 1 - int(bw * 0.08), top + SS * 3),
               (int(bw * 0.08), top + SS * 3)], fill=(255, 235, 150, 255))
    # brick seams
    for k in range(1, 12):
        x = int(bw * k / 12)
        d.line([(x, top + SS * 3), (x, bh - 1)], fill=(170, 120, 30, 255), width=SS)
    return img.resize((w, h), Image.LANCZOS)


def blast(size):
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
            spikes = 0.5 + 0.5 * math.cos(ang * 12)
            edge = 0.62 + 0.3 * spikes
            a = max(0.0, 1.0 - dd / edge) ** 0.8
            v = min(1.0, 0.75 + 0.25 * (1 - dd))
            g = int(round(255 * v))
            px[x, y] = (g, g, g, int(round(255 * a)))
    return img.resize((size, size), Image.LANCZOS)


def save(img, name):
    path = os.path.join(OUT, name)
    img.save(path, format="TGA")
    print("wrote", path, img.size)


if __name__ == "__main__":
    save(shaded_disc(64, spec=0.3), "peg.tga")
    save(shaded_disc(64, highlight=(0.32, 0.30), edge_dark=0.45, spec=0.75), "ball.tga")
    save(shaded_brick(64, 32), "brick.tga")
    save(glow_ring(64), "ring.tga")
    save(soft_dot(32), "dot.tga")
    save(bucket(128, 32), "bucket.tga")
    save(icon(), "icon.tga")
    # placeholders until the real art arrives
    save(egg(64), "egg.tga")
    save(gem(64), "gem.tga")
    save(boss(64), "boss.tga")
    save(crack(64), "crack.tga")
    save(rim(64), "rim.tga")
    save(star(32), "star.tga")
    save(pyramid(256, 32), "pyramid.tga")
    save(blast(128), "blast.tga")
