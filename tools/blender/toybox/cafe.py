"""Pop-Up Café kit (the museum's timed event area) -> art3d/cafe/<kind>.glb

    python tools/blender/toybox/cafe.py            (pip bpy)   or
    blender -b --factory-startup --python tools/blender/toybox/cafe.py

One set of models serves every museum's café. Surfaces the café theme
recolours use ROLE materials named c_* (c_floor_a, c_floor_b, c_wall, c_trim,
c_awning_a, c_awning_b, c_accent, c_sign); Godot swaps their albedo per theme
(data/cafe_event.json), the same way the chibi recolours by role. Everything
else keeps its toy colour.

Local space as in props.py: footprint centred on the origin, standing on z=0,
front facing -Y. FOOTPRINT goes to glTF extras.
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import toy  # noqa: E402
from toy import box, cyl, sphere, torus, rod, mat  # noqa: E402

TAU = math.tau
WOOD_DK = "#7A4A2A"
STEEL = "#B7C3D0"
CREAM = "#FFF4E0"
LEAF = "#3FA64A"
LEAF_HI = "#6CCB5A"
INK = "#2B2245"


def role(name, hexc, rough=0.4, emit=0.0):
    """A material whose NAME is the role the game recolours (cached by name)."""
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        b = m.node_tree.nodes.get("Principled BSDF")
        col = toy.hexcol(hexc)
        b.inputs["Base Color"].default_value = col
        b.inputs["Roughness"].default_value = rough
        if emit:
            b.inputs["Emission Color"].default_value = col
            b.inputs["Emission Strength"].default_value = emit
        m.diffuse_color = col
    return m


def R():
    return {
        "floor_a": role("c_floor_a", "#FFE7C2", 0.5),
        "floor_b": role("c_floor_b", "#F08A5D", 0.5),
        "wall": role("c_wall", "#FFF4E0", 0.55),
        "trim": role("c_trim", "#7A4A2A", 0.45),
        "awn_a": role("c_awning_a", "#E0524A", 0.45),
        "awn_b": role("c_awning_b", "#FFF4E0", 0.45),
        "accent": role("c_accent", "#2FA6A0", 0.35),
        "sign": role("c_sign", "#2B2245", 0.4),
    }


def m(hexc, rough=0.35, **kw):
    return mat(hexc, rough, **kw)


def striped_canopy(r, cx, cy, z, segs, rc, h=0.34):
    """A striped round umbrella (alternating awning roles) with a scalloped rim."""
    p = []
    for i in range(segs):
        a0 = i / segs * TAU
        a1 = (i + 1) / segs * TAU
        mat_ = rc["awn_a"] if i % 2 == 0 else rc["awn_b"]
        # One wedge: a thin cone slice approximated by a box tilted outward.
        am = (a0 + a1) * 0.5
        w = 2 * r * math.sin(math.pi / segs) * 1.08
        p.append(box((w, r * 1.02, 0.03), (cx + math.cos(am) * r * 0.5, cy + math.sin(am) * r * 0.5, z + h * 0.5),
                     mat_, rot=(math.atan2(h, r), 0, am - math.pi / 2), bev=0.01))
        p.append(sphere(r * 0.12, (cx + math.cos(am) * r, cy + math.sin(am) * r, z - 0.02), mat_, seg=10))
    p.append(sphere(0.06, (cx, cy, z + h + 0.04), m("#F2C14E", 0.25, metal=0.5), seg=10))
    return p


# ------------------------------------------------------------------ the room
def cafe_shell():
    """The café terrace, 9 x 6 inside: tiled deck, back wall with awning and a
    sign board, low side walls with hedges, an open front with steps."""
    rc = R()
    p = [box((9.6, 7.0, 0.3), (0, 0, 0.15), m("#E6DCC4", 0.6), bev=0.06)]
    t = 0.75
    for ix in range(12):
        for iy in range(8):
            x = -4.5 + t * (ix + 0.5)
            y = -3.0 + t * (iy + 0.5)
            p.append(box((t - 0.03, t - 0.03, 0.06), (x, y, 0.33), rc["floor_a"] if (ix + iy) % 2 == 0 else rc["floor_b"], bev=0.012))
    # Back wall (+Y), wainscot, door and round windows.
    p.append(box((9.6, 0.3, 2.7), (0, 3.35, 1.65), rc["wall"], bev=0.04))
    p.append(box((9.62, 0.36, 0.7), (0, 3.33, 0.65), rc["trim"], bev=0.03))
    p.append(box((1.2, 0.08, 1.9), (0, 3.18, 1.25), rc["accent"], bev=0.03))
    p.append(sphere(0.06, (0.4, 3.12, 1.25), m("#F2C14E", 0.25, metal=0.5), seg=10))
    glass = m("#BFE6F2", 0.1, alpha=0.6)
    for x in (-3.0, -1.6, 1.6, 3.0):
        p.append(cyl(0.42, 0.08, (x, 3.2, 1.9), glass, rot=(math.pi / 2, 0, 0), bev=0.01))
        p.append(torus(0.42, 0.06, (x, 3.18, 1.9), rc["trim"], rot=(math.pi / 2, 0, 0)))
    # Striped awning along the back wall.
    n = 12
    w = 9.4 / n
    for i in range(n):
        x = -4.7 + w * (i + 0.5)
        mat_ = rc["awn_a"] if i % 2 == 0 else rc["awn_b"]
        p.append(box((w + 0.01, 1.3, 0.05), (x, 2.75, 2.85), mat_, rot=(-0.42, 0, 0), bev=0.01))
        p.append(sphere(w * 0.42, (x, 2.16, 2.58), mat_, scale=(1, 0.5, 0.8), seg=12))
    # Sign board on the roofline (the game writes the café's name on it).
    p.append(box((4.2, 0.24, 0.95), (0, 3.2, 3.55), rc["sign"], bev=0.05))
    p.append(box((4.4, 0.28, 0.12), (0, 3.2, 3.05), rc["trim"], bev=0.03))
    p.append(box((4.4, 0.28, 0.12), (0, 3.2, 4.05), rc["trim"], bev=0.03))
    for x in (-2.35, 2.35):
        p.append(sphere(0.16, (x, 3.2, 3.55), m("#F2C14E", 0.25, metal=0.5), seg=12))
    # Side walls with hedges.
    for sx in (-1, 1):
        p.append(box((0.3, 6.7, 0.95), (sx * 4.65, -0.15, 0.78), rc["wall"], bev=0.04))
        p.append(box((0.36, 6.72, 0.12), (sx * 4.65, -0.15, 1.3), rc["trim"], bev=0.03))
        for j in range(7):
            y = -3.0 + j * 0.95
            p.append(sphere(0.3, (sx * 4.65, y, 1.55), m(LEAF, 0.6), scale=(0.9, 1.3, 0.8), seg=14))
            p.append(sphere(0.14, (sx * 4.6, y - 0.1, 1.72), m(LEAF_HI, 0.6), seg=10))
    # Open front: low fence either side of a wide entrance, and steps.
    for sx in (-1, 1):
        p.append(box((3.1, 0.14, 0.5), (sx * 3.05, -3.4, 0.55), rc["trim"], bev=0.03))
        for k in range(5):
            p.append(box((0.12, 0.2, 0.75), (sx * (1.6 + k * 0.72), -3.4, 0.68), rc["wall"], bev=0.03))
        p.append(cyl(0.12, 1.9, (sx * 1.45, -3.4, 1.25), rc["trim"], bev=0.02))
        p.append(sphere(0.16, (sx * 1.45, -3.4, 2.25), m("#FFE6A0", 0.3, emit=2.0), seg=12))
    p.append(box((2.8, 0.45, 0.15), (0, -3.72, 0.075), m("#E6DCC4", 0.6), bev=0.03))
    # String lights from the back corners to the entrance posts.
    bulb = m("#FFE6A0", 0.3, emit=2.5)
    for sx in (-1, 1):
        a = (sx * 4.5, 3.0, 3.0)
        b = (sx * 1.45, -3.4, 2.2)
        steps = 9
        prev = a
        for k in range(1, steps + 1):
            f = k / steps
            sag = math.sin(f * math.pi) * 0.45
            q = (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f - sag)
            p.append(rod(prev, q, 0.012, m(INK)))
            p.append(sphere(0.07, q, bulb, seg=8))
            prev = q
    return p


# ------------------------------------------------------------------ stations
def coffee_bar():
    """Counter with an espresso machine, cups and a bean jar, 2.0 x 0.8."""
    rc = R()
    p = [box((2.0, 0.7, 0.95), (0, 0, 0.475), rc["trim"], bev=0.04),
         box((2.12, 0.82, 0.08), (0, 0, 0.99), rc["accent"], bev=0.03)]
    for i in range(5):
        p.append(box((0.3, 0.03, 0.62), (-0.8 + i * 0.4, -0.36, 0.48), rc["wall"], bev=0.01))
    steel = m(STEEL, 0.2, metal=0.6)
    p.append(box((0.62, 0.42, 0.5), (-0.45, 0.1, 1.28), steel, bev=0.04))
    p.append(box((0.64, 0.44, 0.08), (-0.45, 0.1, 1.56), rc["accent"], bev=0.02))
    for x in (-0.6, -0.3):
        p.append(cyl(0.05, 0.12, (x, -0.13, 1.2), m(INK, 0.3), bev=0.01))
        p.append(rod((x, -0.13, 1.2), (x, -0.3, 1.18), 0.018, m(INK, 0.3)))
    for i, x in enumerate((0.2, 0.42, 0.64)):
        p.append(cyl(0.07, 0.12, (x, -0.1, 1.09), m("#FFFFFF", 0.3), bev=0.01))
        p.append(torus(0.04, 0.012, (x + 0.08, -0.1, 1.1), m("#FFFFFF", 0.3), rot=(math.pi / 2, 0, 0)))
    p.append(cyl(0.12, 0.3, (0.55, 0.18, 1.18), m("#DDF3FA", 0.1, alpha=0.6), bev=0.01))
    p.append(cyl(0.1, 0.18, (0.55, 0.18, 1.12), m("#5A3A22", 0.7), bev=0.0))
    p.append(cyl(0.13, 0.04, (0.55, 0.18, 1.35), rc["accent"], bev=0.01))
    return p


def pastry_case():
    """Glass display case of cakes on a coloured base, 1.6 x 0.8."""
    rc = R()
    p = [box((1.6, 0.7, 0.75), (0, 0, 0.375), rc["accent"], bev=0.04),
         box((1.64, 0.74, 0.06), (0, 0, 0.78), rc["trim"], bev=0.02),
         box((1.5, 0.62, 0.55), (0, 0, 1.08), m("#DDF3FA", 0.08, alpha=0.35), bev=0.03),
         box((1.64, 0.74, 0.06), (0, 0, 1.38), rc["trim"], bev=0.02)]
    cakes = [("#FFB3C7", "#FFFFFF"), ("#6B3F1F", "#F2C14E"), ("#FFF4E0", "#E0524A"), ("#9ED36A", "#FFFFFF")]
    for i, (body, top) in enumerate(cakes):
        x = -0.55 + i * 0.37
        p.append(cyl(0.14, 0.16, (x, 0.0, 0.9), m(body, 0.5), bev=0.03))
        p.append(cyl(0.145, 0.04, (x, 0.0, 0.99), m(top, 0.4), bev=0.015))
        p.append(sphere(0.035, (x, -0.02, 1.04), m("#D9413A", 0.2), seg=10))
    for i in range(5):
        p.append(sphere(0.06, (-0.6 + i * 0.3, -0.18, 1.2), m("#E8B865", 0.5), scale=(1.2, 1, 0.6), seg=10))
    return p


def food_cart():
    """Themed-treats cart on wheels under a striped umbrella, 1.4 x 0.9."""
    rc = R()
    p = [box((1.2, 0.7, 0.62), (0, 0, 0.62), rc["accent"], bev=0.05),
         box((1.26, 0.76, 0.06), (0, 0, 0.95), rc["trim"], bev=0.02),
         box((1.0, 0.03, 0.4), (0, -0.36, 0.62), rc["wall"], bev=0.01)]
    for sx in (-0.45, 0.45):
        p.append(cyl(0.2, 0.08, (sx, -0.38, 0.22), m(INK, 0.4), rot=(math.pi / 2, 0, 0), bev=0.02))
        p.append(cyl(0.07, 0.1, (sx, -0.4, 0.22), m("#F2C14E", 0.3), rot=(math.pi / 2, 0, 0), bev=0.01))
    p.append(rod((0.6, 0.0, 0.8), (0.95, 0.0, 0.9), 0.025, rc["trim"]))
    steel = m(STEEL, 0.2, metal=0.6)
    p.append(cyl(0.2, 0.22, (-0.25, 0.05, 1.08), steel, bev=0.02))
    p.append(sphere(0.2, (-0.25, 0.05, 1.18), steel, scale=(1, 1, 0.35), seg=14))
    for i in range(3):
        p.append(sphere(0.08, (0.15 + i * 0.16, -0.05, 1.03), m(["#F2A33A", "#FF6FA8", "#9ED36A"][i], 0.4), seg=10))
    p.append(cyl(0.025, 1.4, (0.45, 0.2, 1.65), rc["trim"], bev=0.0))
    p += striped_canopy(0.75, 0.45, 0.2, 2.2, 8, rc)
    return p


def gift_kiosk():
    """Gift booth with shelves of souvenirs and a peaked roof, 1.4 x 0.9."""
    rc = R()
    p = [box((1.4, 0.8, 0.9), (0, 0.05, 0.45), rc["trim"], bev=0.04),
         box((1.46, 0.86, 0.06), (0, 0.05, 0.93), rc["accent"], bev=0.02)]
    for sx in (-0.66, 0.66):
        p.append(box((0.1, 0.1, 1.4), (sx, 0.4, 1.6), rc["trim"], bev=0.02))
    p.append(box((1.42, 0.08, 1.25), (0, 0.42, 1.55), rc["wall"], bev=0.02))
    for z in (1.25, 1.7):
        p.append(box((1.3, 0.3, 0.05), (0, 0.28, z), rc["trim"], bev=0.01))
    goods = ["#E0524A", "#F2C14E", "#3A78D8", "#9ED36A", "#B45CF0", "#FF6FA8"]
    for i in range(5):
        p.append(box((0.16, 0.16, 0.2), (-0.5 + i * 0.25, 0.26, 1.38), m(goods[i], 0.4), bev=0.03))
        p.append(sphere(0.09, (-0.5 + i * 0.25, 0.26, 1.82), m(goods[(i + 2) % 6], 0.35), seg=12))
    for i in range(3):
        p.append(cyl(0.08, 0.2, (-0.35 + i * 0.35, -0.12, 1.06), m(goods[(i + 3) % 6], 0.35), bev=0.02))
    for i in range(6):
        x = -0.7 + 0.28 * (i + 0.5)
        mat_ = rc["awn_a"] if i % 2 == 0 else rc["awn_b"]
        p.append(box((0.29, 1.05, 0.05), (x, 0.05, 2.4), mat_, rot=(-0.35, 0, 0), bev=0.01))
    p.append(box((1.5, 0.12, 0.1), (0, 0.38, 2.6), rc["trim"], bev=0.02))
    return p


def bistro_table():
    """Round table, two stools and a striped parasol, 1.2 x 1.2."""
    rc = R()
    p = [cyl(0.36, 0.05, (0, 0, 0.62), m(CREAM, 0.3), bev=0.02),
         cyl(0.04, 0.6, (0, 0, 0.31), m(WOOD_DK)),
         cyl(0.2, 0.03, (0, 0, 0.02), m(WOOD_DK), bev=0.01),
         cyl(0.025, 1.6, (0, 0, 1.1), m(WOOD_DK), bev=0)]
    p += striped_canopy(0.8, 0.0, 0.0, 1.82, 10, rc)
    for sx in (-0.55, 0.55):
        p += [cyl(0.17, 0.06, (sx, 0, 0.42), rc["accent"], bev=0.02), cyl(0.03, 0.4, (sx, 0, 0.2), m(WOOD_DK))]
    p.append(cyl(0.05, 0.1, (0.1, -0.1, 0.7), m("#FFFFFF", 0.3)))
    p.append(sphere(0.07, (-0.12, 0.05, 0.69), m("#E8B865", 0.5), scale=(1.2, 1, 0.6), seg=10))
    return p


def menu_board():
    """A-frame chalk menu board, 0.6 x 0.4."""
    rc = R()
    board = m("#24483A", 0.7)
    p = []
    for sy, tilt in ((-0.1, 0.2), (0.1, -0.2)):
        p.append(box((0.56, 0.05, 0.9), (0, sy, 0.46), rc["trim"], rot=(tilt, 0, 0), bev=0.02))
    p.append(box((0.46, 0.02, 0.72), (0, -0.14, 0.47), board, rot=(0.2, 0, 0), bev=0.005))
    chalk = m("#FFFFFF", 0.8)
    for i in range(4):
        p.append(box((0.3 - i * 0.04, 0.01, 0.03), (0, -0.16 - 0.0, 0.66 - i * 0.12), chalk, rot=(0.2, 0, 0)))
    return p


# ------------------------------------------------------------------ outside
def cafe_stand():
    """The café's stand on the museum plaza (tap to enter), 2.4 x 1.8."""
    rc = R()
    p = [box((2.4, 1.2, 0.2), (0, 0.2, 0.1), m("#E6DCC4", 0.6), bev=0.04),
         box((2.0, 0.9, 1.1), (0, 0.35, 0.75), rc["wall"], bev=0.05),
         box((2.1, 1.0, 0.08), (0, 0.3, 1.33), rc["accent"], bev=0.03),
         box((1.4, 0.05, 0.55), (0, -0.11, 0.7), rc["trim"], bev=0.02)]
    for sx in (-0.95, 0.95):
        p.append(box((0.12, 0.12, 1.6), (sx, 0.75, 2.1), rc["trim"], bev=0.02))
    p.append(box((2.1, 0.1, 0.75), (0, 0.78, 2.35), rc["wall"], bev=0.02))
    for i in range(8):
        x = -1.1 + 0.275 * (i + 0.5)
        mat_ = rc["awn_a"] if i % 2 == 0 else rc["awn_b"]
        p.append(box((0.28, 1.1, 0.05), (x, 0.3, 2.35), mat_, rot=(-0.4, 0, 0), bev=0.01))
        p.append(sphere(0.12, (x, -0.22, 2.12), mat_, scale=(1, 0.5, 0.8), seg=10))
    p.append(box((1.7, 0.16, 0.5), (0, 0.8, 3.05), rc["sign"], bev=0.04))
    p.append(box((1.8, 0.2, 0.08), (0, 0.8, 2.78), rc["trim"], bev=0.02))
    steel = m(STEEL, 0.2, metal=0.6)
    p.append(box((0.4, 0.3, 0.35), (-0.55, 0.3, 1.55), steel, bev=0.03))
    for i in range(3):
        p.append(cyl(0.06, 0.1, (0.2 + i * 0.2, 0.0, 1.42), m("#FFFFFF", 0.3), bev=0.01))
    p.append(cyl(0.03, 1.4, (1.05, 0.8, 3.2), m(WOOD_DK), bev=0))
    p.append(box((0.5, 0.03, 0.3), (1.3, 0.8, 3.7), rc["awn_a"], bev=0.01))
    return p


KIT = {
    "cafe_shell": (cafe_shell, (9.6, 7.0)),
    "coffee_bar": (coffee_bar, (2.0, 0.8)),
    "pastry_case": (pastry_case, (1.6, 0.8)),
    "food_cart": (food_cart, (1.4, 0.9)),
    "gift_kiosk": (gift_kiosk, (1.4, 0.9)),
    "bistro_table": (bistro_table, (1.2, 1.2)),
    "menu_board": (menu_board, (0.6, 0.4)),
    "cafe_stand": (cafe_stand, (2.4, 1.8)),
}


def export_all(only=None):
    for kind, (fn, fp) in KIT.items():
        if only and kind not in only:
            continue
        toy.reset()
        o = toy.join(fn(), kind)
        o["footprint"] = list(fp)
        toy.export_glb(os.path.join(toy.ART3D, "cafe", f"{kind}.glb"), [o])


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    export_all(set(argv[0].split(",")) if argv else None)
