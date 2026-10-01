"""Generate Textures/*.tga for Gnomish Pachinko.

peg.tga / ball.tga are white shaded discs the window tints with
SetVertexColor, brick.tga a white shaded rounded bar for bricks, ring.tga
the glow a lit peg wears, dot.tga one aim-guide dot, bucket.tga the
free-ball cup, icon.tga the addon icon. Power-of-two, 32-bit TGA.

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
