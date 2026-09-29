"""Artifacts and dig-site pieces for the Dig Site mini game (scenes/digsite).

    blender -b --factory-startup --python tools/blender/toybox/artifacts.py [-- shape,shape]

Every artifact SHAPE is modelled lying flat in a 1 x 1 footprint (centred on
the origin, resting on z=0, about 0.4 tall). Godot stretches it to the
artifact's footprint in cells and recolours the two paint slots, materials
named "main" and "accent", from data/dig_sites.json. So twelve museums' worth
of finds come from twenty-odd shapes, and they still read as different
objects because the silhouettes do.

Exports art3d/artifacts/<shape>.glb and art3d/digsite/<piece>.glb.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import toy  # noqa: E402
from toy import box, cyl, sphere, torus, rod, ico, mat, shade  # noqa: E402

TAU = math.tau
INK = "#2B2245"


def paints():
    return mat("#E6E6E6", 0.35, name="main"), mat("#454545", 0.45, name="accent")


# ============================================================ artifact shapes (1 x 1, flat)
def skull():
    m, a = paints()
    p = [sphere(0.3, (-0.12, 0, 0.2), m, scale=(1.1, 1.0, 0.75)),
         sphere(0.22, (0.22, 0, 0.14), m, scale=(1.3, 0.8, 0.55))]
    for sy in (-1, 1):
        p.append(sphere(0.08, (-0.02, sy * 0.15, 0.28), mat(INK, 0.5), seg=12))
        p.append(sphere(0.07, (-0.3, sy * 0.22, 0.22), a, seg=12))
    for i in range(6):
        p.append(cyl(0.025, 0.1, (0.1 + i * 0.07, 0.12 * (1 if i % 2 else -1), 0.06), mat("#FFF7E6", 0.3), r2=0.0,
                     rot=(math.pi, 0, 0), bev=0, verts=8))
    return p


def shell():
    m, a = paints()
    p = []
    for i in range(22):
        t = i / 21
        ang = t * TAU * 1.6
        r = 0.08 + 0.3 * t
        p.append(sphere(0.07 + 0.12 * t, (math.cos(ang) * r * 0.9, math.sin(ang) * r * 0.9, 0.1 + 0.05 * t),
                        m if i % 3 else a, scale=(1, 1, 0.7), seg=12))
    return p


def bug():
    m, a = paints()
    p = [sphere(0.28, (0, 0, 0.12), m, scale=(0.75, 1.3, 0.45)),
         sphere(0.13, (0, 0.34, 0.1), a, scale=(1.2, 0.8, 0.6))]
    for i in range(5):
        p.append(torus(0.15, 0.025, (0, -0.2 + i * 0.1, 0.17), a, rot=(0, 0, 0)))
    for sx in (-1, 1):
        for i in range(3):
            p.append(rod((sx * 0.15, -0.1 + i * 0.12, 0.08), (sx * 0.34, -0.14 + i * 0.14, 0.03), 0.025, a))
    return p


def claw():
    m, a = paints()
    p = []
    prev = (0, -0.4, 0.06)
    for i in range(1, 10):
        t = i / 9
        pt = (0.18 * math.sin(t * 2.2), -0.4 + 0.8 * t, 0.06 + 0.16 * math.sin(t * math.pi))
        p.append(rod(prev, pt, 0.12 - 0.1 * t, m, r2=0.12 - 0.1 * (t + 0.11)))
        p.append(sphere(0.12 - 0.1 * t, pt, m, seg=12))
        prev = pt
    p.append(sphere(0.13, (0, -0.4, 0.07), a, scale=(1, 1, 0.7)))
    return p


def gem():
    m, a = paints()
    p = [ico(0.28, (0, 0, 0.22), m, sub=1, jitter=0.02, scale=(1, 1, 0.8)),
         ico(0.1, (0.05, -0.02, 0.26), mat("#FFFFFF", 0.1, emit=0.8), sub=1)]
    p.append(sphere(0.05, (0.02, 0.03, 0.22), a, seg=10))
    return p


def bell():
    m, a = paints()
    p = [cyl(0.34, 0.45, (0, 0, 0.3), m, r2=0.18, rot=(math.pi / 2, 0, 0), bev=0.03),
         torus(0.34, 0.04, (0, -0.22, 0.3), m, rot=(math.pi / 2, 0, 0)),
         sphere(0.08, (0, -0.1, 0.18), a, seg=12),
         torus(0.08, 0.03, (0, 0.28, 0.3), a, rot=(math.pi / 2, 0, 0))]
    return p


def anchor():
    m, a = paints()
    p = [rod((0, -0.42, 0.08), (0, 0.32, 0.08), 0.06, m),
         torus(0.1, 0.035, (0, 0.42, 0.08), a),
         rod((-0.25, 0.22, 0.08), (0.25, 0.22, 0.08), 0.04, m)]
    prev = (-0.36, -0.2, 0.08)
    for i in range(1, 9):
        t = i / 8
        ang = math.pi * (1 - t)
        pt = (math.cos(ang) * 0.36, -0.42 + (1 - math.sin(ang)) * 0.22, 0.08)
        p.append(rod(prev, pt, 0.05, m))
        prev = pt
    for sx in (-1, 1):
        p.append(cyl(0.08, 0.14, (sx * 0.36, -0.2, 0.08), a, r2=0.0, rot=(0, 0, 0), bev=0, verts=10))
    return p


def jar():
    m, a = paints()
    p = [sphere(0.28, (0, 0, 0.2), m, scale=(0.9, 1.3, 0.75)),
         cyl(0.1, 0.18, (0, 0.42, 0.2), m, rot=(math.pi / 2, 0, 0), bev=0.02),
         torus(0.12, 0.03, (0, 0.5, 0.2), a, rot=(math.pi / 2, 0, 0)),
         torus(0.26, 0.025, (0, 0.05, 0.2), a, rot=(math.pi / 2, 0, 0))]
    return p


def chest():
    m, a = paints()
    p = [box((0.8, 0.6, 0.34), (0, 0, 0.17), m, bev=0.04),
         cyl(0.3, 0.8, (0, 0, 0.34), m, rot=(0, math.pi / 2, 0), bev=0.03)]
    for sx in (-0.3, 0.3):
        p.append(box((0.08, 0.64, 0.5), (sx, 0, 0.3), a, bev=0.015))
    p.append(box((0.14, 0.05, 0.14), (0, -0.31, 0.3), a, bev=0.015))
    for i in range(5):
        p.append(cyl(0.07, 0.03, (-0.2 + i * 0.1, -0.1 + (i % 2) * 0.1, 0.62), mat("#F2C14E", 0.25, metal=0.6), bev=0.01))
    return p


def bust():
    m, a = paints()
    p = [box((0.5, 0.36, 0.14), (0, 0.22, 0.07), a, bev=0.03),
         sphere(0.26, (0, -0.02, 0.24), m, scale=(1.0, 0.85, 0.9)),
         sphere(0.14, (0, -0.3, 0.2), m, scale=(0.5, 0.6, 0.5)),
         sphere(0.3, (0, 0.2, 0.2), m, scale=(1.2, 0.5, 0.6))]
    for sx in (-1, 1):
        p.append(sphere(0.035, (sx * 0.09, -0.25, 0.3), mat(INK, 0.4), seg=10))
    return p


def ring():
    m, a = paints()
    p = [torus(0.34, 0.07, (0, 0, 0.08), m)]
    for i in range(8):
        ang = i / 8 * TAU
        p.append(sphere(0.07, (math.cos(ang) * 0.34, math.sin(ang) * 0.34, 0.16), a if i % 2 else m, seg=12))
    return p


def coins():
    m, a = paints()
    r = random.Random(3)
    p = []
    for i in range(9):
        p.append(cyl(0.12, 0.04, (r.uniform(-0.28, 0.28), r.uniform(-0.28, 0.28), 0.03 + 0.04 * (i % 3)), m if i % 3 else a,
                     rot=(r.uniform(-0.3, 0.3), r.uniform(-0.3, 0.3), 0), bev=0.01))
    return p


def slab():
    m, a = paints()
    p = [box((0.9, 0.7, 0.22), (0, 0, 0.11), m, bev=0.05)]
    for i in range(3):
        p.append(box((0.6 - i * 0.12, 0.06, 0.03), (0, -0.2 + i * 0.18, 0.23), a, bev=0.01))
    for sx in (-1, 1):
        p.append(torus(0.1, 0.035, (sx * 0.38, 0, 0.16), a, rot=(math.pi / 2, 0, 0)))
    return p


def mask():
    m, a = paints()
    p = [sphere(0.4, (0, 0, 0.12), m, scale=(0.95, 1.1, 0.3))]
    for sx in (-1, 1):
        p.append(sphere(0.08, (sx * 0.14, -0.08, 0.22), mat(INK, 0.4), scale=(1.3, 0.8, 0.5), seg=12))
        p.append(box((0.06, 0.5, 0.05), (sx * 0.34, 0.05, 0.18), a, bev=0.015))
    p.append(sphere(0.06, (0, 0.08, 0.25), m, scale=(0.7, 1.4, 0.7), seg=12))
    p.append(box((0.22, 0.05, 0.04), (0, 0.26, 0.2), a, bev=0.015))
    return p


def disc():
    m, a = paints()
    p = [cyl(0.42, 0.08, (0, 0, 0.05), m, bev=0.02, verts=32),
         torus(0.38, 0.03, (0, 0, 0.1), a)]
    for i in range(12):
        ang = i / 12 * TAU
        p.append(box((0.05, 0.12, 0.03), (math.cos(ang) * 0.3, math.sin(ang) * 0.3, 0.1), a, rot=(0, 0, ang), bev=0.01))
    p.append(cyl(0.1, 0.06, (0, 0, 0.12), a, bev=0.01))
    return p


def rock():
    m, a = paints()
    r = random.Random(8)
    p = [ico(0.36, (0, 0, 0.22), m, sub=2, jitter=0.07, scale=(1, 0.95, 0.7), rnd=r)]
    for i in range(5):
        ang = i / 5 * TAU
        p.append(ico(0.07, (math.cos(ang) * 0.24, math.sin(ang) * 0.24, 0.36), a, sub=1, jitter=0.02, rnd=r))
    return p


def tool():
    m, a = paints()
    p = [rod((0, -0.45, 0.07), (0, 0.3, 0.07), 0.05, a),
         box((0.4, 0.1, 0.08), (0, 0.33, 0.07), m, bev=0.02)]
    for sx in (-0.16, 0, 0.16):
        p.append(cyl(0.035, 0.18, (sx, 0.45, 0.07), m, r2=0.0, rot=(-math.pi / 2, 0, 0), bev=0, verts=10))
    p.append(sphere(0.07, (0, -0.47, 0.07), m, seg=12))
    return p


def idol():
    m, a = paints()
    p = [box((0.36, 0.5, 0.14), (0, 0.02, 0.07), m, bev=0.04),
         sphere(0.16, (0, -0.28, 0.12), m, scale=(1, 0.9, 0.8)),
         sphere(0.04, (-0.06, -0.38, 0.18), mat(INK, 0.4), seg=10),
         sphere(0.04, (0.06, -0.38, 0.18), mat(INK, 0.4), seg=10)]
    for sx in (-1, 1):
        p.append(sphere(0.14, (sx * 0.24, 0.0, 0.1), a, scale=(0.6, 1.3, 0.4)))
    return p


def helm():
    m, a = paints()
    p = [sphere(0.34, (0, 0, 0.16), m, scale=(1.0, 1.15, 0.55)),
         torus(0.33, 0.035, (0, 0, 0.1), a),
         box((0.5, 0.06, 0.04), (0, -0.12, 0.3), mat(INK, 0.4), bev=0.01)]
    for sx in (-1, 1):
        p.append(rod((sx * 0.28, 0.1, 0.22), (sx * 0.46, 0.3, 0.2), 0.05, a, r2=0.01))
    return p


def sword():
    m, a = paints()
    p = [box((0.12, 0.62, 0.04), (0, 0.12, 0.05), m, bev=0.015),
         cyl(0.06, 0.12, (0, 0.47, 0.05), m, r2=0.0, rot=(-math.pi / 2, 0, 0), bev=0, verts=4),
         box((0.36, 0.06, 0.06), (0, -0.2, 0.05), a, bev=0.015),
         rod((0, -0.22, 0.05), (0, -0.42, 0.05), 0.035, a),
         sphere(0.05, (0, -0.44, 0.05), mat("#F2C14E", 0.25, metal=0.6), seg=10)]
    return p


def cog():
    m, a = paints()
    p = [cyl(0.3, 0.1, (0, 0, 0.06), m, bev=0.02, verts=32),
         cyl(0.1, 0.12, (0, 0, 0.07), a, bev=0.01)]
    for i in range(10):
        ang = i / 10 * TAU
        p.append(box((0.12, 0.12, 0.1), (math.cos(ang) * 0.34, math.sin(ang) * 0.34, 0.06), m, rot=(0, 0, ang), bev=0.015))
    for i in range(4):
        ang = i / 4 * TAU + 0.4
        p.append(cyl(0.05, 0.12, (math.cos(ang) * 0.19, math.sin(ang) * 0.19, 0.07), a, bev=0))
    return p


def egg():
    m, a = paints()
    p = [sphere(0.3, (0, 0, 0.24), m, scale=(0.85, 1.0, 0.8))]
    for i in range(3):
        p.append(torus(0.28 - abs(i - 1) * 0.05, 0.025, (0, -0.15 + i * 0.15, 0.24), a, rot=(math.pi / 2, 0, 0)))
    for i in range(6):
        ang = i / 6 * TAU
        p.append(sphere(0.04, (math.cos(ang) * 0.2, 0.0, 0.24 + math.sin(ang) * 0.2), mat("#FFFFFF", 0.1, emit=0.5), seg=10))
    return p


SHAPES = {k: v for k, v in dict(skull=skull, shell=shell, bug=bug, claw=claw, gem=gem, bell=bell, anchor=anchor, jar=jar,
                                chest=chest, bust=bust, ring=ring, coins=coins, slab=slab, mask=mask, disc=disc, rock=rock,
                                tool=tool, idol=idol, helm=helm, sword=sword, cog=cog, egg=egg).items()}


# ============================================================ dig-site pieces
def soil_block():
    """One 1 x 1 x 0.3 layer of soil, recoloured per site ("main")."""
    m, a = paints()
    return [box((0.98, 0.98, 0.3), (0, 0, 0.15), m, bev=0.06)]


def rock_block():
    m, a = paints()
    r = random.Random(5)
    p = [box((0.96, 0.96, 0.3), (0, 0, 0.15), m, bev=0.08)]
    for i in range(4):
        p.append(ico(0.16, (r.uniform(-0.28, 0.28), r.uniform(-0.28, 0.28), 0.3), a, sub=1, jitter=0.04, rnd=r))
    return p


def coin_find():
    gold = mat("#F2C14E", 0.25, metal=0.6)
    r = random.Random(2)
    p = []
    for i in range(6):
        p.append(cyl(0.12, 0.04, (r.uniform(-0.18, 0.18), r.uniform(-0.18, 0.18), 0.03 + 0.035 * i), gold,
                     rot=(r.uniform(-0.2, 0.2), r.uniform(-0.2, 0.2), 0), bev=0.01))
    return p


def gem_find():
    return [ico(0.16, (-0.1, 0, 0.16), mat("#3AA0E8", 0.1, emit=0.4), sub=1, jitter=0.02),
            ico(0.12, (0.12, 0.08, 0.12), mat("#E85A9A", 0.1, emit=0.4), sub=1, jitter=0.02),
            ico(0.1, (0.05, -0.14, 0.1), mat("#6FE06A", 0.1, emit=0.4), sub=1, jitter=0.02)]


def crystal_find():
    c = mat("#7FE8FF", 0.08, emit=1.2)
    p = []
    for i, (x, y, h) in enumerate(((0, 0, 0.45), (0.12, 0.06, 0.3), (-0.1, 0.08, 0.28), (0.02, -0.12, 0.25))):
        p.append(cyl(0.07, h, (x, y, h / 2), c, r2=0.0, rot=(0.15 * (i % 2), -0.15 * (i % 3 == 1), 0), bev=0, verts=6))
    return p


def survey_flag():
    return [cyl(0.02, 0.7, (0, 0, 0.35), mat("#5A3A22", 0.5), bev=0),
            box((0.26, 0.02, 0.16), (0.13, 0, 0.62), mat("#FF4F4F", 0.5), bev=0.005)]


def pit_frame():
    """Timber edging round a 7 x 9 pit, with a ladder and a tool rack."""
    wood, dk = mat("#B8783F", 0.5), mat("#7A4A2A", 0.55)
    W, H = 7.0, 9.0
    p = [box((W + 0.6, 0.3, 0.3), (0, H / 2 + 0.15, 0.15), wood, bev=0.04),
         box((W + 0.6, 0.3, 0.3), (0, -H / 2 - 0.15, 0.15), wood, bev=0.04),
         box((0.3, H, 0.3), (-W / 2 - 0.15, 0, 0.15), wood, bev=0.04),
         box((0.3, H, 0.3), (W / 2 + 0.15, 0, 0.15), wood, bev=0.04)]
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.append(cyl(0.12, 0.7, (sx * (W / 2 + 0.15), sy * (H / 2 + 0.15), 0.35), dk, bev=0.02))
            p.append(sphere(0.08, (sx * (W / 2 + 0.15), sy * (H / 2 + 0.15), 0.74), mat("#E8C35A", 0.4), seg=12))
    for sx in (-1, 1):  # rope line with pennants along the long sides
        for i in range(10):
            y = -H / 2 + i * H / 9
            p.append(cyl(0.06, 0.03, (sx * (W / 2 + 0.15), y, 0.55), mat(["#FF4F4F", "#FFD34D", "#4FB86A"][i % 3], 0.5),
                         rot=(0, math.pi / 2, 0), r2=0.0, bev=0, verts=3))
    return p


def camp():
    """Tent, crates and a lantern for the pit's surroundings."""
    canvas = mat("#EDE0C0", 0.7)
    p = [toy.prism(2.2, 1.8, 1.3, (0, 0, 0), canvas, bev=0.04),
         box((0.5, 0.05, 0.9), (0, -0.91, 0.45), mat("#7A4A2A", 0.6), bev=0.01),
         box((0.7, 0.55, 0.45), (1.6, 0.3, 0.22), mat("#C99A5B", 0.5), bev=0.03),
         box((0.55, 0.45, 0.35), (1.55, 0.35, 0.62), mat("#B8783F", 0.5), bev=0.03),
         cyl(0.03, 1.3, (-1.4, -0.6, 0.65), mat("#2E3A4A", 0.4), bev=0),
         sphere(0.12, (-1.4, -0.6, 1.3), mat("#FFE08A", 0.2, emit=2.5), seg=12)]
    return p


PIECES = dict(soil_block=soil_block, rock_block=rock_block, coin_find=coin_find, gem_find=gem_find,
              crystal_find=crystal_find, survey_flag=survey_flag, pit_frame=pit_frame, camp=camp)


def export_all(only=None):
    for folder, table in (("artifacts", SHAPES), ("digsite", PIECES)):
        for name, fn in table.items():
            if only and name not in only:
                continue
            toy.reset()
            o = toy.join(fn(), name)
            toy.export_glb(os.path.join(toy.ART3D, folder, f"{name}.glb"), [o])


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    export_all(set(argv[0].split(",")) if argv else None)
