#!/usr/bin/env python3
"""Builds AppIcon.icns from the sitting sprite.

The cat is scaled by whole numbers only so the pixel art stays crisp at every
icon size, and sits on the rounded-square slab macOS expects.
"""

import os
import subprocess
import tempfile
from PIL import Image, ImageDraw

SIZES = [16, 32, 64, 128, 256, 512, 1024]
ICONSET = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
           ("128x128", 128), ("128x128@2x", 256), ("256x256", 256),
           ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)]


def slab(size):
    """Rounded square with a soft top-lit gradient."""
    ss = 4                                   # supersample the background only
    img = Image.new("RGBA", (size * ss, size * ss), (0, 0, 0, 0))
    grad = Image.new("RGBA", (1, size * ss))
    for y in range(size * ss):
        t = y / (size * ss - 1)
        grad.putpixel((0, y), (int(64 - 30 * t), int(66 - 31 * t), int(84 - 38 * t), 255))
    grad = grad.resize((size * ss, size * ss))

    mask = Image.new("L", (size * ss, size * ss), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [size * ss * 0.045, size * ss * 0.045, size * ss * 0.955, size * ss * 0.955],
        radius=size * ss * 0.225, fill=255)
    img.paste(grad, (0, 0), mask)

    # hairline top highlight, the way Apple's own icons catch light
    edge = Image.new("RGBA", (size * ss, size * ss), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle(
        [size * ss * 0.045, size * ss * 0.045, size * ss * 0.955, size * ss * 0.955],
        radius=size * ss * 0.225, outline=(255, 255, 255, 40), width=max(1, size * ss // 160))
    img.alpha_composite(edge)
    return img.resize((size, size), Image.LANCZOS)


def compose(cat, size):
    bg = slab(size)
    target = size * 0.66
    factor = max(1, int(target / max(cat.width, cat.height)))
    art = cat.resize((cat.width * factor, cat.height * factor), Image.NEAREST)
    if art.width > size * 0.92:              # a whole-number scale overshot; step back
        factor = max(1, factor - 1)
        art = cat.resize((cat.width * factor, cat.height * factor), Image.NEAREST)
    bg.alpha_composite(art, ((size - art.width) // 2, int(size * 0.53 - art.height / 2)))
    return bg


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    sheet = Image.open(os.path.join(root, "Sources", "PetApp", "Resources", "Sprites", "sit.png"))
    cat = sheet.crop((0, 0, 40, 32)).crop(sheet.crop((0, 0, 40, 32)).getbbox())

    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, "AppIcon.iconset")
        os.makedirs(iconset)
        for label, px in ICONSET:
            compose(cat, px).save(os.path.join(iconset, f"icon_{label}.png"))
        out = os.path.join(root, "AppIcon.icns")
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", out], check=True)
        print("wrote", out)


if __name__ == "__main__":
    main()
