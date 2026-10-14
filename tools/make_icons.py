# Regenerates the stance icons in media/ui/ALifeStanceDots.
#   python tools/make_icons.py
# Drawn at 4x and downsampled for clean edges; dark outline so they read on any ground.
import math
import os
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "..", "ALifeStanceDots", "Contents", "mods",
                   "ALifeStanceDots", "42", "media", "ui", "ALifeStanceDots")
S = 128           # working size
EDGE = (20, 20, 20, 255)
RED, ORANGE, YELLOW = (235, 45, 35, 255), (255, 145, 20, 255), (250, 215, 40, 255)
GREEN, BLUE = (60, 220, 90, 255), (60, 140, 255, 255)


def save(img, name):
    img.resize((32, 32), Image.LANCZOS).save(os.path.join(OUT, name + ".png"))


def outlined(draw_shape, fill):
    """draw_shape(draw, colour, grow) paints the shape; grow > 0 makes the outline pass."""
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    draw_shape(d, EDGE, 9)
    draw_shape(d, fill, 0)
    return img


def dot(colour):
    return outlined(lambda d, c, g: d.ellipse((14 - g, 14 - g, 114 + g, 114 + g), fill=c), colour)


def poly(points, colour):
    def shape(d, c, g):
        cx = sum(p[0] for p in points) / len(points)
        cy = sum(p[1] for p in points) / len(points)
        grown = []
        for x, y in points:
            dx, dy = x - cx, y - cy
            n = math.hypot(dx, dy) or 1
            grown.append((x + dx / n * g, y + dy / n * g))
        d.polygon(grown, fill=c)
        if g:
            d.line(grown + [grown[0]], fill=c, width=g, joint="curve")
    return outlined(shape, colour)


def swords():
    def blade(d, c, g, flip):
        def m(x, y):
            return (S - x, y) if flip else (x, y)
        d.line([m(20, 20), m(96, 96)], fill=c, width=20 + g * 2)         # blade
        d.line([m(70, 108), m(108, 70)], fill=c, width=16 + g * 2)       # guard
        d.line([m(96, 96), m(114, 114)], fill=c, width=14 + g * 2)       # grip
        x0, x1 = (S - 122 - g, S - 104 + g) if flip else (104 - g, 122 + g)
        d.ellipse((x0, 104 - g, x1, 122 + g), fill=c)                    # pommel
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for flip in (False, True):
        blade(d, EDGE, 7, flip)
    for flip in (False, True):
        blade(d, RED, 0, flip)
    return img


def warning():
    img = poly([(64, 10), (120, 112), (8, 112)], ORANGE)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((57, 42, 71, 84), radius=6, fill=EDGE)
    d.ellipse((56, 90, 72, 106), fill=EDGE)
    return img


def shield():
    pts = [(16, 18), (64, 6), (112, 18), (108, 68)]
    pts += [(64 + 44 * math.cos(a), 68 + 54 * math.sin(a)) for a in
            [i * math.pi / 12 for i in range(0, 13)]][1:12]
    pts += [(20, 68)]
    return poly(pts, GREEN)


def star():
    pts = []
    for i in range(10):
        r = 58 if i % 2 == 0 else 24
        a = -math.pi / 2 + i * math.pi / 5
        pts.append((64 + r * math.cos(a), 68 + r * math.sin(a)))
    return poly(pts, BLUE)


def house():
    img = poly([(64, 8), (122, 60), (106, 60), (106, 118), (22, 118), (22, 60), (6, 60)], BLUE)
    ImageDraw.Draw(img).rectangle((52, 80, 76, 118), fill=EDGE)   # door
    return img


if __name__ == "__main__":
    save(swords(), "hostile")
    save(warning(), "careful")
    save(dot(YELLOW), "neutral")
    save(dot(GREEN), "friendly")
    save(shield(), "allied")
    save(star(), "companion")
    save(house(), "resident")
    # "Dots" style: one colour per status
    for name, colour in [("hostile", RED), ("careful", ORANGE), ("neutral", YELLOW), ("friendly", GREEN),
                         ("allied", (20, 140, 70, 255)), ("companion", BLUE), ("resident", (120, 220, 255, 255))]:
        save(dot(colour), "dot_" + name)
    print("icons written to", os.path.abspath(OUT))
