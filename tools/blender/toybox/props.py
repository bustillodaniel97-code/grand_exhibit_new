"""Toy-style props and exhibits for the 3D venue scene.

Each builder makes one piece in LOCAL space: its footprint is centred on the
origin, it stands on z=0 and its front faces -Y (toward the camera once
placed). FOOTPRINT gives the size it was modelled at, so the Godot side can
scale it to a spec's `size` / `len` without guessing.

Run standalone to export every piece to art3d/props and art3d/exhibits:
    blender -b --factory-startup --python tools/blender/toybox/props.py
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import toy  # noqa: E402
from toy import box, cyl, sphere, torus, ico, rod, mat, shade  # noqa: E402

TAU = math.tau

# Shared prop palette: saturated, toy-like, readable at phone size.
WOOD = "#B8783F"
WOOD_DK = "#7A4A2A"
BRASS = "#F2C14E"
CREAM = "#FFF4E0"
STONE = "#E6DCC4"
STONE_DK = "#B9AC90"
STEEL = "#9AA8B8"
LEAF = "#3FA64A"
LEAF_HI = "#6CCB5A"
TERRACOTTA = "#D0714A"
RED = "#D9413A"
TEAL = "#2FA6A0"
INK = "#2B2245"


def m(hexc, rough=0.35, **kw):
    return mat(hexc, rough, **kw)


# ============================================================ furniture
def planter():
    p = [cyl(0.2, 0.3, (0, 0, 0.15), m(TERRACOTTA), r2=0.16, bev=0.03),
         torus(0.19, 0.035, (0, 0, 0.3), m(shade(TERRACOTTA, 0.85)))]
    p.append(sphere(0.24, (0, 0, 0.5), m(LEAF), scale=(1, 1, 0.9)))
    r = random.Random(3)
    for i in range(5):
        a = i / 5 * TAU
        p.append(sphere(0.13, (math.cos(a) * 0.17, math.sin(a) * 0.17, 0.44 + r.uniform(0, 0.08)), m(LEAF)))
    p.append(sphere(0.1, (-0.05, -0.08, 0.68), m(LEAF_HI), scale=(1, 1, 0.7)))
    return p


def bench():
    p = []
    for i in range(3):
        p.append(box((1.5, 0.11, 0.05), (0, -0.12 + i * 0.12, 0.34), m(WOOD), bev=0.02))
    for i in range(2):
        p.append(box((1.5, 0.05, 0.1), (0, 0.17, 0.48 + i * 0.13), m(WOOD), bev=0.02))
    for sx in (-0.62, 0.62):
        p.append(box((0.07, 0.36, 0.32), (sx, 0, 0.16), m(WOOD_DK), bev=0.02))
        p.append(box((0.07, 0.06, 0.34), (sx, 0.19, 0.5), m(WOOD_DK), bev=0.02))
    return p


def kiosk():
    p = [cyl(0.32, 0.55, (0, 0, 0.28), m(WOOD), bev=0.03),
         cyl(0.36, 0.06, (0, 0, 0.58), m(BRASS), bev=0.02),
         cyl(0.05, 0.5, (0, 0, 0.85), m(WOOD_DK))]
    for i in range(8):  # striped canopy
        a = i / 8 * TAU
        p.append(rod((0, 0, 1.25), (math.cos(a) * 0.45, math.sin(a) * 0.45, 1.05), 0.06,
                     m(RED if i % 2 else CREAM), r2=0.02))
    p.append(sphere(0.07, (0, 0, 1.28), m(BRASS)))
    for i in range(3):  # brochures
        a = -math.pi / 2 + (i - 1) * 0.5
        p.append(box((0.14, 0.03, 0.2), (math.cos(a) * 0.3, math.sin(a) * 0.3, 0.68),
                     m(["#4E7FB5", "#FFCC33", "#C95F9E"][i]), rot=(0.2, 0, a + math.pi / 2), bev=0.01))
    return p


def shelf():
    w, d = 2.0, 0.5
    p = [box((w, d, 0.05), (0, 0, 0.03 + i * 0.36), m(WOOD), bev=0.015) for i in range(4)]
    for sx in (-w / 2 + 0.03, w / 2 - 0.03):
        p.append(box((0.06, d, 1.12), (sx, 0, 0.56), m(WOOD_DK), bev=0.02))
    r = random.Random(5)
    cols = ["#C9B896", "#E8C35A", "#8FB8DE", "#D98E73"]
    for lvl in range(3):
        x = -w / 2 + 0.12
        while x < w / 2 - 0.25:
            bw = r.uniform(0.2, 0.34)
            bh = r.uniform(0.18, 0.28)
            p.append(box((bw, d * 0.8, bh), (x + bw / 2, 0, 0.06 + lvl * 0.36 + bh / 2), m(r.choice(cols)), bev=0.02))
            x += bw + 0.05
    return p


def crate():
    p = [box((0.8, 0.6, 0.5), (0, 0, 0.25), m("#C99A5B"), bev=0.03)]
    for sx in (-0.3, 0.3):
        p.append(box((0.07, 0.62, 0.52), (sx, 0, 0.25), m(WOOD_DK), bev=0.015))
    p.append(box((0.82, 0.07, 0.07), (0, -0.3, 0.25), m(WOOD_DK), bev=0.015))
    return p


def cabinet():
    p = [box((0.5, 0.7, 1.2), (0, 0, 0.6), m(WOOD), bev=0.03)]
    for i in range(4):
        p.append(box((0.42, 0.04, 0.24), (0, -0.35, 0.17 + i * 0.28), m(shade(WOOD, 1.15)), bev=0.015))
        p.append(sphere(0.03, (0, -0.38, 0.17 + i * 0.28), m(BRASS), seg=12))
    return p


def vault_door():
    """Round vault door set in a wall, 1.6 long. Faces -Y."""
    p = [box((1.6, 0.24, 1.9), (0, 0, 0.95), m(STEEL, 0.3, metal=0.6), bev=0.05),
         cyl(0.62, 0.14, (0, -0.16, 0.9), m("#C7D0DA", 0.25, metal=0.7), rot=(math.pi / 2, 0, 0), bev=0.04),
         torus(0.5, 0.04, (0, -0.24, 0.9), m(BRASS, 0.25, metal=0.6), rot=(math.pi / 2, 0, 0)),
         cyl(0.08, 0.1, (0, -0.28, 0.9), m(BRASS, 0.25, metal=0.6), rot=(math.pi / 2, 0, 0))]
    for i in range(4):  # wheel spokes
        a = i / 4 * TAU
        p.append(rod((0, -0.29, 0.9), (math.cos(a) * 0.3, -0.29, 0.9 + math.sin(a) * 0.3), 0.025, m(BRASS, 0.25, metal=0.6)))
    for i in range(8):  # bolts
        a = i / 8 * TAU
        p.append(sphere(0.04, (math.cos(a) * 0.56, -0.24, 0.9 + math.sin(a) * 0.56), m(STEEL, 0.3, metal=0.6), seg=10))
    return p


def info_desk():
    w, d = 2.2, 0.7
    p = [box((w, d, 0.5), (0, 0, 0.25), m("#C0563E"), bev=0.05),
         box((w + 0.1, d + 0.1, 0.07), (0, 0, 0.53), m(BRASS, 0.25, metal=0.4), bev=0.025),
         box((0.9, 0.05, 0.28), (0, -d / 2 - 0.02, 0.28), m(CREAM), bev=0.02)]
    for i, ch in enumerate(range(4)):  # "INFO" as four chunky ink blocks
        p.append(box((0.13, 0.03, 0.14), (-0.3 + i * 0.2, -d / 2 - 0.05, 0.28), m(INK), bev=0.01))
    p.append(box((0.3, 0.22, 0.2), (0.6, 0.1, 0.66), m(INK), bev=0.02))  # till
    return p


def bin_():
    return [cyl(0.15, 0.4, (0, 0, 0.2), m(TEAL), r2=0.13, bev=0.02),
            cyl(0.17, 0.05, (0, 0, 0.42), m(shade(TEAL, 0.8)), bev=0.015)]


def desk():
    w, d = 1.9, 0.6
    p = [box((w, d, 0.06), (0, 0, 0.45), m(WOOD), bev=0.02)]
    for sx in (-w / 2 + 0.2, w / 2 - 0.2):
        p.append(box((0.3, d - 0.05, 0.42), (sx, 0, 0.21), m(WOOD_DK), bev=0.02))
    p.append(box((0.5, 0.05, 0.32), (0, 0.12, 0.66), m(INK), bev=0.02))
    p.append(box((0.44, 0.02, 0.26), (0, 0.095, 0.67), m("#8FD2FF", 0.1, emit=0.6)))
    p.append(box((0.05, 0.05, 0.12), (0, 0.14, 0.52), m(INK)))
    p.append(cyl(0.05, 0.1, (0.6, 0, 0.53), m(RED), bev=0.01))  # mug
    return p


def ticket_counter():
    """Queue station: ticket booth counter, 1.55 x 0.6, with a little sign."""
    w, d = 1.55, 0.6
    p = [box((w, d, 0.55), (0, 0, 0.28), m("#2F7FD1"), bev=0.05),
         box((w + 0.08, d + 0.08, 0.07), (0, 0, 0.58), m(CREAM), bev=0.025),
         box((w, 0.04, 0.12), (0, -d / 2 - 0.01, 0.42), m(BRASS, 0.25, metal=0.4), bev=0.01),
         box((0.34, 0.26, 0.22), (0.4, 0.08, 0.72), m(INK), bev=0.03),
         cyl(0.025, 0.55, (-0.55, 0.2, 0.88), m(BRASS, 0.25, metal=0.4)),
         box((0.5, 0.05, 0.26), (-0.55, 0.2, 1.2), m(RED), bev=0.03),
         box((0.36, 0.06, 0.07), (-0.55, 0.18, 1.2), m(CREAM))]
    for i in range(3):  # ticket stacks
        p.append(box((0.12, 0.08, 0.03), (-0.1 + i * 0.16, -0.05, 0.63), m(["#FFCC33", "#FF6FA8", "#7FD4E8"][i])))
    return p


def docent_stand():
    return [cyl(0.2, 0.08, (0, 0, 0.04), m(WOOD_DK), bev=0.02),
            cyl(0.06, 0.8, (0, 0, 0.44), m(BRASS, 0.25, metal=0.4)),
            box((0.46, 0.34, 0.06), (0, 0, 0.88), m(WOOD), rot=(math.radians(-25), 0, 0), bev=0.02),
            box((0.36, 0.26, 0.02), (0, -0.01, 0.91), m(CREAM), rot=(math.radians(-25), 0, 0))]


def promo_booth():
    p = desk()
    p.append(box((0.08, 0.08, 1.1), (-0.85, 0.2, 0.55), m(WOOD_DK), bev=0.02))
    p.append(box((0.7, 0.06, 0.5), (-0.85, 0.22, 1.05), m("#C95F9E"), bev=0.03))
    p.append(sphere(0.12, (-0.85, 0.18, 1.05), m("#FFCC33")))
    p.append(cyl(0.09, 0.22, (0.75, -0.1, 0.6), m(RED), r2=0.03, rot=(math.pi / 2, 0, 0)))  # megaphone
    return p


def rope_post():
    return [cyl(0.1, 0.05, (0, 0, 0.025), m(BRASS, 0.25, metal=0.5), bev=0.015),
            cyl(0.03, 0.55, (0, 0, 0.3), m(BRASS, 0.25, metal=0.5)),
            sphere(0.055, (0, 0, 0.6), m(BRASS, 0.25, metal=0.5), seg=14)]


def entrance():
    """The `facade` prop: grand doorway set into the front wall (len 2.4)."""
    p = []
    for sx in (-1.0, 1.0):
        p.append(cyl(0.16, 1.9, (sx, 0, 0.95), m(STONE), bev=0.03))
        p.append(box((0.42, 0.42, 0.14), (sx, 0, 0.07), m(STONE_DK), bev=0.03))
        p.append(box((0.42, 0.42, 0.14), (sx, 0, 1.95), m(STONE_DK), bev=0.03))
    p.append(box((2.5, 0.5, 0.3), (0, 0, 2.15), m(STONE), bev=0.05))
    p.append(toy.prism(2.7, 0.6, 0.55, (0, 0, 2.3), m(RED), bev=0.05))
    p.append(box((1.5, 0.06, 0.3), (0, -0.28, 2.15), m("#2F7FD1"), bev=0.03))  # name board
    p.append(box((1.3, 0.07, 0.08), (0, -0.3, 2.15), m(BRASS, 0.25, metal=0.4)))
    for sx in (-0.42, 0.42):  # open double doors
        p.append(box((0.08, 0.5, 1.5), (sx * 1.6, -0.22, 0.75), m("#8B4A2B"), bev=0.02))
    p.append(box((1.9, 0.4, 0.06), (0, -0.35, 0.03), m("#C0392B")))  # welcome mat
    return p


# ============================================================ exhibits
BONE = "#F6EEDA"


def skeleton():
    """Hero exhibit: standing theropod skeleton on a plinth, footprint 3.2 x 1.2."""
    b = m(BONE, 0.3)
    dark = m("#3A2E22", 0.6)
    p = [box((3.2, 1.2, 0.32), (0, 0, 0.16), m(STONE), bev=0.06),
         box((3.24, 1.24, 0.07), (0, 0, 0.3), m(BRASS, 0.25, metal=0.4), bev=0.02),
         box((0.7, 0.04, 0.16), (0, -0.62, 0.16), m(BRASS, 0.25, metal=0.4), bev=0.015)]
    spine = [(-1.55, 0.95), (-1.1, 1.18), (-0.6, 1.36), (-0.2, 1.46), (0.3, 1.5), (0.7, 1.62), (0.98, 1.9), (1.12, 2.1)]
    pts = []
    for (x0, z0), (x1, z1) in zip(spine, spine[1:]):
        n = max(2, int(math.hypot(x1 - x0, z1 - z0) / 0.1))
        for i in range(n):
            t = i / n
            pts.append((x0 + (x1 - x0) * t, z0 + (z1 - z0) * t))
    for i, (x, z) in enumerate(pts):
        u = i / len(pts)
        r = 0.035 + 0.075 * math.sin(min(1.0, u * 1.25) * math.pi * 0.95)
        p.append(sphere(r, (x, 0, z), b, seg=12))
    for x in [v / 100 for v in range(-45, 75, 13)]:  # rib cage
        z = 1.47 if x < 0.3 else 1.52
        p.append(torus(0.24, 0.028, (x, 0, z - 0.25), b, rot=(0, math.pi / 2, 0)))
    skull = (1.35, 0, 2.15)
    p.append(sphere(0.2, skull, b, scale=(1.7, 0.85, 0.95)))
    p.append(box((0.5, 0.26, 0.09), (1.45, 0, 1.98), b, rot=(0, math.radians(8), 0), bev=0.03))
    for sy in (-1, 1):
        p.append(sphere(0.055, (1.3, sy * 0.13, 2.22), dark, seg=12))
        for i in range(5):
            p.append(cyl(0.022, 0.08, (1.3 + i * 0.07, sy * 0.1, 2.02), m(CREAM), r2=0.0, rot=(math.pi, 0, 0), bev=0, verts=8))
    for sy in (-1, 1):  # legs: thigh, shin, foot
        hip, knee, ankle, toe = (-0.3, sy * 0.24, 1.35), (0.05, sy * 0.28, 0.85), (-0.3, sy * 0.28, 0.45), (0.05, sy * 0.28, 0.36)
        p += [rod(hip, knee, 0.075, b), rod(knee, ankle, 0.06, b), rod(ankle, toe, 0.05, b),
              sphere(0.1, knee, b, seg=12), sphere(0.07, ankle, b, seg=12)]
        for dx in (-0.08, 0, 0.08):
            p.append(rod(toe, (toe[0] + 0.18, sy * 0.28 + dx, 0.35), 0.025, b, r2=0.01))
        p.append(rod((0.55, sy * 0.15, 1.45), (0.7, sy * 0.2, 1.2), 0.03, b))  # tiny arms
    p.append(sphere(0.16, (-0.3, 0, 1.38), b, scale=(1.3, 1.1, 0.8)))  # pelvis
    for x in (-0.9, 0.5):  # support rods
        p.append(rod((x, 0, 0.32), (x, 0, 1.3), 0.018, m(STEEL, 0.3, metal=0.6)))
    return p


def mural():
    """Framed landscape for a wall, 2.2 long; bottom edge at z 0 (lift in engine)."""
    fr = m(shade(BRASS, 0.8), 0.3, metal=0.3)
    p = [box((2.3, 0.08, 1.3), (0, 0, 0.65), fr, bev=0.04),
         box((2.1, 0.06, 0.72), (0, -0.03, 0.83), m("#BFDCF2", 0.6)),
         box((2.1, 0.06, 0.42), (0, -0.03, 0.29), m("#7E9E78", 0.6)),
         sphere(0.16, (0.55, -0.06, 0.95), m("#F7DE93", 0.5, emit=0.3), scale=(1, 0.3, 1))]
    for i, x in enumerate((-0.7, -0.35, 0.05)):  # hills
        p.append(sphere(0.3 + i * 0.05, (x, -0.05, 0.45), m(shade("#5E8F5A", 1 + i * 0.08), 0.6), scale=(1.4, 0.2, 0.8)))
    return p


def casket():
    """Upright golden sarcophagus on a plinth, 1 x 1."""
    gold = m("#E0AE45", 0.25, metal=0.5)
    teal = m("#2F8C9A", 0.35)
    p = [box((0.9, 0.9, 0.3), (0, 0, 0.15), m(STONE), bev=0.05),
         sphere(0.3, (0, 0, 1.0), gold, scale=(1.0, 0.7, 2.2)),
         sphere(0.2, (0, -0.1, 1.55), m("#F2C88A", 0.3, metal=0.3), scale=(1, 0.8, 1.15))]
    for i in range(4):  # headdress stripes
        p.append(torus(0.21, 0.03, (0, -0.02, 1.45 - i * 0.08), teal, rot=(math.radians(10), 0, 0)))
    for sy in (-1, 1):
        p.append(sphere(0.03, (sy * 0.07, -0.28, 1.58), m(INK), seg=10))
    p.append(rod((-0.2, -0.22, 1.05), (0.2, -0.22, 1.2), 0.05, teal))  # crossed arms
    p.append(rod((0.2, -0.22, 1.05), (-0.2, -0.22, 1.2), 0.05, gold))
    for i in range(3):
        p.append(box((0.4, 0.02, 0.04), (0, -0.21, 0.7 - i * 0.12), teal))
    return p


def statue():
    """Marble figure holding a laurel aloft, 1 x 1."""
    st = m(STONE, 0.45)
    p = [box((0.8, 0.8, 0.5), (0, 0, 0.25), m(STONE_DK), bev=0.05),
         box((0.9, 0.9, 0.08), (0, 0, 0.52), m(STONE), bev=0.03),
         cyl(0.2, 0.6, (0, 0, 0.9), st, r2=0.14, bev=0.03),
         sphere(0.16, (0, 0, 1.35), st),
         sphere(0.17, (0, 0.03, 1.4), m(shade(STONE, 0.92), 0.45), scale=(1, 1, 0.85)),
         rod((0.12, 0, 1.15), (0.3, 0, 1.6), 0.05, st),
         rod((-0.12, 0, 1.15), (-0.2, -0.05, 0.9), 0.05, st),
         torus(0.12, 0.03, (0.32, 0, 1.72), m("#8BC34A", 0.4))]
    return p


def vitrine():
    """Glass case on a plinth with a glowing crystal skull, 0.7 x 1.5 (long in Y)."""
    p = [box((0.7, 1.5, 0.6), (0, 0, 0.3), m(WOOD_DK), bev=0.04),
         box((0.74, 1.54, 0.05), (0, 0, 0.62), m(BRASS, 0.25, metal=0.4), bev=0.015),
         box((0.62, 1.42, 0.62), (0, 0, 0.96), m("#CFEFFF", 0.05, alpha=0.25), bev=0.02),
         sphere(0.15, (0, 0, 0.82), m("#7FD4E8", 0.1, emit=1.2), scale=(1, 1.1, 1.1))]
    for sy in (-1, 1):
        p.append(sphere(0.035, (sy * 0.05, -0.13, 0.85), m(INK), seg=10))
    return p


def case():
    """Low glass-topped table of mineral specimens, 1.5 x 0.7."""
    p = [box((1.5, 0.7, 0.55), (0, 0, 0.28), m(WOOD_DK), bev=0.04),
         box((1.4, 0.6, 0.28), (0, 0, 0.7), m("#CFEFFF", 0.05, alpha=0.25), bev=0.02)]
    r = random.Random(9)
    for i, col in enumerate(("#7ED8F0", "#F08CC4", "#9CE8A8")):
        x = -0.45 + i * 0.45
        for _ in range(4):
            h = r.uniform(0.12, 0.22)
            p.append(cyl(0.04, h, (x + r.uniform(-0.08, 0.08), r.uniform(-0.1, 0.1), 0.56 + h / 2), m(col, 0.1, emit=0.4),
                         r2=0.0, rot=(r.uniform(-0.3, 0.3), r.uniform(-0.3, 0.3), 0), bev=0, verts=6))
    return p


# ============================================================ outdoor
def tree(seed=0):
    """Round, puffy Link's-Awakening-style tree (about 1.9 tall)."""
    r = random.Random(seed)
    leaf, leaf2 = m("#2F9A3E", 0.32), m("#237A35", 0.32)
    p = [cyl(0.15, 0.55, (0, 0, 0.27), m("#7A4A2A", 0.5), r2=0.11, bev=0.03),
         sphere(0.62, (0, 0, 1.0), leaf, scale=(1, 1, 0.9), seg=16)]
    for i in range(7):
        a = i / 7 * TAU + r.uniform(-0.3, 0.3)
        p.append(sphere(r.uniform(0.3, 0.4), (math.cos(a) * 0.45, math.sin(a) * 0.45, 0.82 + r.uniform(-0.05, 0.2)),
                        leaf2 if i % 2 else leaf, seg=14))
    p.append(sphere(0.42, (0, -0.05, 1.38), leaf, seg=16))
    p.append(sphere(0.2, (-0.15, -0.2, 1.62), m("#4DBB4A", 0.32), scale=(1, 1, 0.7)))
    return p


def bush(seed=0):
    r = random.Random(seed)
    b = m("#5CC04A", 0.32)
    p = [sphere(0.3, (0, 0, 0.22), b, scale=(1, 1, 0.85), seg=16)]
    for i in range(5):
        a = i / 5 * TAU + r.uniform(-0.3, 0.3)
        p.append(sphere(r.uniform(0.15, 0.2), (math.cos(a) * 0.24, math.sin(a) * 0.24, 0.2 + r.uniform(0, 0.1)), b, seg=12))
    p.append(sphere(0.12, (-0.06, -0.1, 0.45), m("#7ED66A", 0.32), scale=(1, 1, 0.7)))
    if seed % 2:
        for i in range(4):
            a = i / 4 * TAU + 0.4
            p.append(sphere(0.045, (math.cos(a) * 0.26, math.sin(a) * 0.26 - 0.05, 0.36), m("#FF6FA8", 0.3), seg=10))
    return p


def lamp_post():
    dark = m("#2E3A4A", 0.35, metal=0.4)
    return [cyl(0.12, 0.12, (0, 0, 0.06), dark, bev=0.03),
            cyl(0.045, 1.8, (0, 0, 0.95), dark),
            sphere(0.16, (0, 0, 1.95), m("#FFF2B3", 0.2, emit=2.0), seg=16),
            cyl(0.18, 0.06, (0, 0, 2.12), dark, r2=0.05, bev=0.01)]


def fountain():
    stone, water = m(STONE, 0.4), m("#43B3EE", 0.05)
    p = [cyl(1.0, 0.3, (0, 0, 0.15), stone, bev=0.05),
         cyl(0.88, 0.05, (0, 0, 0.27), water, bev=0.0),
         cyl(0.18, 0.7, (0, 0, 0.55), stone, bev=0.03),
         cyl(0.42, 0.1, (0, 0, 0.9), stone, bev=0.03),
         cyl(0.35, 0.03, (0, 0, 0.96), water, bev=0.0),
         sphere(0.1, (0, 0, 1.05), m("#BFE9FF", 0.05, alpha=0.7), scale=(1, 1, 1.6))]
    return p


def bus_stop():
    glass = m("#CFEFFF", 0.05, alpha=0.35)
    frame = m("#2F7FD1", 0.3)
    p = [box((1.8, 0.7, 0.06), (0, 0.1, 1.55), frame, bev=0.03),
         box((1.7, 0.04, 1.3), (0, 0.4, 0.8), glass),
         box((1.4, 0.3, 0.06), (0, 0.2, 0.42), m(WOOD), bev=0.02)]
    for sx in (-0.85, 0.85):
        p.append(box((0.06, 0.06, 1.55), (sx, 0.4, 0.78), frame, bev=0.015))
    p.append(cyl(0.04, 2.0, (1.1, -0.1, 1.0), m("#2E3A4A", 0.35)))
    p.append(cyl(0.2, 0.05, (1.1, -0.1, 2.0), m("#FFCC33", 0.3), rot=(math.pi / 2, 0, 0), bev=0.01))
    return p


# ============================================================ registry
# kind -> (builder, footprint (x, y) it was modelled at, export folder)
PROPS = {
    "planter": (planter, (0.5, 0.5), "props"),
    "bench": (bench, (1.5, 0.4), "props"),
    "kiosk": (kiosk, (0.7, 0.7), "props"),
    "shelf": (shelf, (2.0, 0.5), "props"),
    "crate": (crate, (0.8, 0.6), "props"),
    "cabinet": (cabinet, (0.5, 0.7), "props"),
    "vault_door": (vault_door, (1.6, 0.24), "props"),
    "info_desk": (info_desk, (2.2, 0.7), "props"),
    "bin": (bin_, (0.3, 0.3), "props"),
    "desk": (desk, (1.9, 0.6), "props"),
    "facade": (entrance, (2.4, 0.5), "props"),
    "ticket_counter": (ticket_counter, (1.55, 0.6), "props"),
    "docent_stand": (docent_stand, (0.5, 0.4), "props"),
    "promo_booth": (promo_booth, (1.9, 0.6), "props"),
    "rope_post": (rope_post, (0.2, 0.2), "props"),
    "skeleton": (skeleton, (3.2, 1.2), "exhibits"),
    "mural": (mural, (2.2, 0.08), "exhibits"),
    "casket": (casket, (1.0, 1.0), "exhibits"),
    "statue": (statue, (1.0, 1.0), "exhibits"),
    "vitrine": (vitrine, (0.7, 1.5), "exhibits"),
    "case": (case, (1.5, 0.7), "exhibits"),
    "tree": (tree, (1.5, 1.5), "outdoor"),
    "bush": (bush, (0.7, 0.7), "outdoor"),
    "lamp_post": (lamp_post, (0.3, 0.3), "outdoor"),
    "fountain": (fountain, (2.0, 2.0), "outdoor"),
    "bus_stop": (bus_stop, (1.8, 0.8), "outdoor"),
}


def build(kind, name=None):
    """Build one piece at the origin and return it as a single joined object."""
    fn = PROPS[kind][0]
    return toy.join(fn(), name or kind)


def export_all():
    for kind, (_, fp, folder) in PROPS.items():
        toy.reset()
        o = build(kind)
        o["footprint"] = list(fp)  # glTF extras -> Godot node metadata
        toy.export_glb(os.path.join(toy.ART3D, folder, f"{kind}.glb"), [o])


if __name__ == "__main__":
    export_all()
