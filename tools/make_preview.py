# Builds the Workshop preview (ALifeStanceDots/preview.png) from Project A-Life's own
# icon, so the add-on reads as part of the family: same frame, glow, B42 badge, and
# the A-Life logo + wordmark, scaled down to make room for ours, marked [UNOFFICIAL].
#   python tools/make_preview.py [path/to/ProjectALifeNPCs/42.20/icon.png]
# Needs Pillow and Windows' Bahnschrift font.
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(__file__))
import make_icons as icons  # noqa: E402  (same shapes as the in-game icons)

SOURCE = sys.argv[1] if len(sys.argv) > 1 else \
    "D:/SteamLibrary/steamapps/workshop/content/108600/3803984183/mods/ProjectALifeNPCs/42.20/icon.png"
OUT = os.path.join(os.path.dirname(__file__), "..", "ALifeStanceDots", "preview.png")
FONT = "C:/Windows/Fonts/bahnschrift.ttf"

SIZE, FRAME = 512, 7
BASE, GLOW = (10, 10, 11), (36, 54, 67)
CREAM, ORANGE, MUTED = (236, 233, 222), (232, 165, 74), (150, 160, 168)
OLD_CENTRE = (256, 185)                 # where A-Life's glow sits
LOGO_BOX = (100, 60, 412, 446)          # logo + PROJECT A-LIFE, with a margin
BADGE_BOX = (412, 12, 500, 72)          # the B42 tag


def glow_at(d):
    # ponytail: fitted by eye to A-Life's radial glow; refit if their art changes
    t = max(0.0, 1.0 - d / 250.0) ** 1.6
    return tuple(round(b + (g - b) * t) for b, g in zip(BASE, GLOW))


def background(centre):
    img = Image.new("RGB", (SIZE, SIZE), BASE)
    px = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            px[x, y] = glow_at(math.hypot(x - centre[0], y - centre[1]))
    return img


def lift_logo(src):
    """The logo and wordmark as RGBA, cut off A-Life's background."""
    crop = src.crop(LOGO_BOX)
    alpha = Image.new("L", crop.size, 0)
    a, c = alpha.load(), crop.load()
    for y in range(crop.size[1]):
        for x in range(crop.size[0]):
            bg = glow_at(math.hypot(x + LOGO_BOX[0] - OLD_CENTRE[0], y + LOGO_BOX[1] - OLD_CENTRE[1]))
            diff = max(abs(p - q) for p, q in zip(c[x, y], bg))
            a[x, y] = max(0, min(255, (diff - 12) * 5))
    crop = crop.convert("RGBA")
    crop.putalpha(alpha)
    return crop


def badge_box(src):
    """Tight box around the orange B42 tag (not the background around it)."""
    px = src.load()
    hits = [(x, y) for x in range(BADGE_BOX[0], BADGE_BOX[2]) for y in range(BADGE_BOX[1], BADGE_BOX[3])
            if px[x, y][0] > 180 and px[x, y][2] < 120]
    return (min(h[0] for h in hits), min(h[1] for h in hits),
            max(h[0] for h in hits) + 1, max(h[1] for h in hits) + 1)


def spaced(draw, centre_x, y, text, font, fill, tracking):
    widths = [draw.textlength(ch, font=font) for ch in text]
    x = centre_x - (sum(widths) + tracking * (len(text) - 1)) / 2
    for ch, w in zip(text, widths):
        draw.text((x, y), ch, font=font, fill=fill)
        x += w + tracking


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_axes([weight, 75])   # Bahnschrift axes: weight, width (75 = condensed)
    return f


def main():
    src = Image.open(SOURCE).convert("RGB")
    logo = lift_logo(src)
    scale = 0.56
    logo = logo.resize((round(logo.width * scale), round(logo.height * scale)), Image.LANCZOS)
    top = 26
    centre = (SIZE // 2, top + round((OLD_CENTRE[1] - LOGO_BOX[1]) * scale))

    img = background(centre)
    img.paste(logo, ((SIZE - logo.width) // 2, top), logo)
    img.paste(src.crop(badge_box(src)), badge_box(src)[:2])
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, SIZE - 1, SIZE - 1), outline=ORANGE, width=FRAME)

    y = top + logo.height + 26
    spaced(d, SIZE / 2, y, "STANCE DOTS", font(58, 700), CREAM, 4)
    y += 74
    d.rectangle((SIZE / 2 - 34, y, SIZE / 2 + 34, y + 3), fill=ORANGE)

    # every status, left to right from danger to home
    shapes = [icons.swords(), icons.warning(), icons.dot(icons.YELLOW), icons.dot(icons.GREEN),
              icons.shield(), icons.star(), icons.house()]
    icon, gap = 46, 10
    x = (SIZE - (icon * len(shapes) + gap * (len(shapes) - 1))) // 2
    y += 20
    for shape in shapes:
        shadow = shape.resize((icon, icon), Image.LANCZOS).split()[3].filter(ImageFilter.GaussianBlur(4))
        img.paste((0, 0, 0), (x + 2, y + 3), shadow.point(lambda v: v * 0.6))
        img.paste(shape.resize((icon, icon), Image.LANCZOS), (x, y), shape.resize((icon, icon), Image.LANCZOS))
        x += icon + gap

    spaced(d, SIZE / 2, y + icon + 22, "FRIEND OR FOE, OVER THEIR HEAD", font(17, 400), MUTED, 2)
    spaced(d, SIZE / 2, SIZE - 46, "[UNOFFICIAL]", font(26, 600), ORANGE, 6)

    img.save(OUT)
    print("preview written to", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
