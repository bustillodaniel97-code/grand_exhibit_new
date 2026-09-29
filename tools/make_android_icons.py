#!/usr/bin/env python3
"""Generate the Android launcher icons from the project's brand mark.

Run:  python3 tools/make_android_icons.py

Writes assets/android/{icon_192,icon_fg_432,icon_bg_432}.png, which
export_presets.template.cfg points at.

WHY GENERATED. Android wants three separate images of one mark: a legacy
full-bleed square, and an adaptive foreground/background PAIR that the launcher
composites and then masks to whatever shape the device uses — circle, squircle,
rounded square, teardrop. Hand-exporting three files drifts; a script does not.

THE SAFE ZONE IS THE WHOLE TRICK. An adaptive icon is 432x432, but the launcher
may mask away everything outside the central 66% circle and may additionally
zoom for parallax. Only the middle 288x288 is guaranteed visible. Art drawn to
the edges gets its corners eaten on a circular-mask launcher, which is why the
foreground here is composed inside SAFE and the background is a plain field with
nothing meaningful in it.

The mark itself matches icon.svg: a museum facade — pedimented roof over three
columns on a brass plinth.
"""

from __future__ import annotations

import os
from PIL import Image, ImageDraw

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(REPO, "assets", "android")

# Palette lifted from icon.svg so the launcher icon and the in-game boot splash
# are the same object rather than two drawings that resemble each other.
INK = (0x33, 0x31, 0x2E, 255)      # background stone
ROOF = (0xC4, 0x70, 0x3F, 255)     # terracotta pediment
COLUMN = (0xF5, 0xEF, 0xE0, 255)   # limestone columns
PLINTH = (0xB0, 0x8D, 0x3E, 255)   # brass step
# Supersample factor. PIL has no anti-aliased polygon fill, so everything is
# drawn at 4x and boxed down; the roof's diagonals look ragged otherwise.
SS = 4


def _facade(draw: ImageDraw.ImageDraw, x: float, y: float, w: float, h: float) -> None:
    """Draw the museum mark into the box (x, y, w, h), in icon.svg proportions."""
    def px(u: float) -> float:
        return x + u * w / 128.0

    def py(v: float) -> float:
        return y + v * h / 128.0

    # Pediment + body, as one silhouette (the icon.svg path).
    draw.polygon(
        [(px(24), py(92)), (px(24), py(56)), (px(64), py(30)),
         (px(104), py(56)), (px(104), py(92))],
        fill=ROOF,
    )
    # Three columns.
    for cx in (36, 59, 82):
        draw.rectangle([px(cx), py(64), px(cx + 10), py(92)], fill=COLUMN)
    # Brass step, slightly wider than the body so the facade reads as standing on
    # something rather than floating.
    draw.rounded_rectangle(
        [px(16), py(92), px(112), py(100)], radius=max(1.0, px(2) - px(0)), fill=PLINTH
    )


def _new(size: int, bg) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGBA", (size * SS, size * SS), bg)
    return img, ImageDraw.Draw(img)


def _save(img: Image.Image, size: int, name: str) -> None:
    out = img.resize((size, size), Image.LANCZOS)
    path = os.path.join(OUT_DIR, name)
    out.save(path, "PNG")
    print(f"  wrote {os.path.relpath(path, REPO)}  ({size}x{size})")


def legacy_icon(size: int = 192) -> None:
    """Full-bleed square with the corner radius baked in, for pre-adaptive launchers."""
    img, d = _new(size, (0, 0, 0, 0))
    s = size * SS
    d.rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * 24 / 128), fill=INK)
    # Inset so the facade does not touch the rounded corners.
    pad = s * 0.06
    _facade(d, pad, pad, s - 2 * pad, s - 2 * pad)
    _save(img, size, "icon_192.png")


def adaptive_background(size: int = 432) -> None:
    """Plain field. Nothing legible lives here — the mask can eat any of it."""
    img, d = _new(size, INK)
    s = size * SS
    # A barely-there vignette so the icon is not a dead flat rectangle next to
    # other launcher icons. Kept under a few percent so no mask shape reveals a
    # visible edge.
    for i in range(14):
        t = i / 14.0
        inset = s * 0.5 * t
        alpha = int(6 * (1.0 - t))
        if alpha <= 0:
            continue
        d.ellipse([inset, inset, s - inset, s - inset], fill=(255, 244, 224, alpha))
    _save(img, size, "icon_bg_432.png")


def adaptive_foreground(size: int = 432) -> None:
    """The mark, composed entirely inside the guaranteed-visible centre."""
    img, d = _new(size, (0, 0, 0, 0))
    s = size * SS
    # 66% safe zone, then a further margin so a parallax zoom cannot clip the
    # plinth. The facade ends up occupying ~58% of the canvas, which is what
    # Google's own adaptive examples use.
    safe = s * 0.66
    box = safe * 0.88
    origin = (s - box) / 2.0
    _facade(d, origin, origin, box, box)
    _save(img, size, "icon_fg_432.png")


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    print("Grand Exhibit — Android launcher icons")
    legacy_icon()
    adaptive_background()
    adaptive_foreground()
    print("done.")


if __name__ == "__main__":
    main()
