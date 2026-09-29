"""Build a venue's 3D shell (grounds, plinth, floors, walls, crown) from data/venues.json.

    blender -b --factory-startup --python tools/blender/toybox/venue.py -- whispering_pines [--preview]

Exports art3d/venues/<id>/shell.glb. With --preview it also places every prop,
exhibit and station the way the Godot scene does, and renders
docs/visual-overhaul/<id>_blender_preview.png from the game camera.

The layout is the venue's authored data, unchanged; only the look is new. Room
colours come from STYLES below (one saturated colour per department, as in
IBT), not from the muted 2D palette.
"""
import json
import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import toy  # noqa: E402
import props  # noqa: E402
from toy import box, cyl, sphere, torus, mat, shade, g2b  # noqa: E402

PLINTH_TOP = 0.12
FLOOR_TOP = 0.17
WALL_T = 0.16
H_BACK, H_SIDE, H_INNER, H_FRONT = 2.4, 1.5, 1.05, 0.34

STYLES = {
    "whispering_pines": {
        "floors": {
            "archive": ("planks", "#7FB3D1", "#6CA2C2"),
            "gallery": ("planks", "#E3AD66", "#D69E56"),
            "ticket": ("checker", "#FFF1D6", "#E9875C"),
            "reception_court": ("checker", "#FFF1D6", "#E9875C"),
            "promotions": ("carpet", "#9E6CCB", "#F2C14E"),
            "lobby": ("checker", "#FFF6E6", "#D9C4A0"),
        },
        "walls": {"archive": "#4E93CF", "gallery": "#6FBF6A", "ticket": "#F0875A",
                  "promotions": "#A874D6", "shell": "#F3E2BF"},
        "exterior": "#EFE3CC", "trim": "#FFF7E6", "accent": "#D9413A", "dome": "#5FB8A0",
        "lawn": ("#6CC24A", "#62B843"), "paving": ("#E8DCC4", "#D8CAB0"),
    },
}


def load_wings(vid):
    """Authored wings with a 3D layout (data/wings.json), in floor order."""
    path = os.path.join(toy.ROOT, "data", "wings.json")
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    return [w for w in data.get("venues", {}).get(vid, []) if "layout" in w]


def load_venue(vid):
    with open(os.path.join(toy.ROOT, "data", "venues.json"), encoding="utf-8") as f:
        data = json.load(f)
    venues = data["venues"] if isinstance(data, dict) and "venues" in data else data
    return next(v for v in venues if v["id"] == vid)


class Builder:
    def __init__(self, venue):
        self.v = venue
        self.t = venue["theme"]
        self.s = STYLES.get(venue["id"], STYLES["whispering_pines"])
        self.rooms = self.t["rooms"]
        self.rnd = random.Random(7)
        xs = [r["rect"][0] + r["rect"][2] for r in self.rooms]
        ys = [r["rect"][1] + r["rect"][3] for r in self.rooms]
        self.W, self.H = max(xs), max(ys)
        self.groups = {"grounds": [], "building": [], "crown": [], "dome": [],
                       "grand_2": [], "grand_3": [], "grand_4": []}
        self.wings = load_wings(venue["id"])
        for w in self.wings:
            self.groups["floor_" + w["id"]] = []
            self.groups["lift_" + w["id"]] = []

    def add(self, group, objs):
        self.groups.setdefault(group, [])
        self.groups[group] += objs if isinstance(objs, list) else [objs]

    # ------------------------------------------------------------ helpers
    def room_at(self, gx, gy):
        for r in self.rooms:
            x, y, w, h = r["rect"]
            if x <= gx <= x + w and y <= gy <= y + h:
                return r
        return None

    def inside(self, gx, gy):
        return self.room_at(gx, gy) is not None

    def wall_colour(self, ref):
        key = ref.lstrip("@").split("|")[0]
        key = key.replace("room.", "")
        return self.s["walls"].get(key, self.s["walls"]["shell"])

    def inst(self, kind, loc, rz=0.0, s=1.0, seed=None):
        fn = props.PROPS[kind][0]
        parts = fn(seed) if seed is not None else fn()
        o = toy.join(parts, kind)
        o.rotation_euler = (0, 0, rz)
        o.scale = (s, s, s)
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        o.location = loc  # kept as a transform so callers can still scale about the piece
        return o

    # ------------------------------------------------------------ grounds
    def grounds(self):
        W, H = self.W, self.H
        x0, x1, y0, y1 = -8.0, W + 8.0, self.back_y() - 7.0, H + 11.0
        lawn = self.s["lawn"]
        band = 1.5  # mown stripes running across the view
        y = y0
        i = 0
        while y < y1:
            yb = min(y1, y + band)
            self.add("grounds", box((x1 - x0, yb - y, 0.1), g2b((x0 + x1) / 2, (y + yb) / 2, -0.05),
                                    mat(lawn[i % 2], 0.6)))
            y, i = yb, i + 1
        road_y = H + 5.2
        self.add("grounds", [
            box((x1 - x0, 3.0, 0.06), g2b((x0 + x1) / 2, road_y + 1.5, 0.0), mat("#5B6573", 0.55)),
            box((x1 - x0, 0.9, 0.14), g2b((x0 + x1) / 2, road_y - 0.45, 0.0), mat("#D9D2C3", 0.5), bev=0.03),
            box((x1 - x0, 0.9, 0.14), g2b((x0 + x1) / 2, road_y + 3.45, 0.0), mat("#D9D2C3", 0.5), bev=0.03),
        ])
        x = x0 + 0.5
        while x < x1:
            self.add("grounds", box((0.8, 0.1, 0.02), g2b(x + 0.4, road_y + 1.5, 0.04), mat("#FFF4D6", 0.5)))
            x += 1.6
        # Entrance plaza: paving from the steps down to the pavement.
        px0, px1 = -1.0, W + 1.0
        py0, py1 = H + 0.35, road_y - 0.9
        pv = self.s["paving"]
        for gx in range(int(px0), int(px1)):
            for gy in range(int(py0), int(math.ceil(py1))):
                h = min(1.0, py1 - gy)
                self.add("grounds", box((1, h, 0.08), g2b(gx + 0.5, gy + h / 2, 0.0),
                                        mat(pv[(gx + gy) % 2], 0.5), bev=0.02, seg=1))
        return road_y

    def outdoors(self, road_y):
        W, H = self.W, self.H
        r = random.Random(11)
        spots = []
        for gy in range(int(self.back_y()) - 5, int(H) + 3, 2):  # flanks
            spots += [(-2.2 - r.uniform(0, 3.5), gy + r.uniform(-0.4, 0.4)), (W + 2.2 + r.uniform(0, 3.5), gy + r.uniform(-0.4, 0.4))]
        for gx in range(-2, int(W) + 3, 2):  # behind the building
            spots.append((gx + r.uniform(-0.4, 0.4), self.back_y() - 2.2 - r.uniform(0, 2.5)))
        for i, (gx, gy) in enumerate(spots):
            self.add("grounds", self.inst("tree", g2b(gx, gy), r.uniform(0, 6.3), r.uniform(1.0, 1.3), seed=i % 4))
        for gx in (-1.2, W + 1.2):  # plaza lamps and hedges
            for gy in (H + 1.0, road_y - 1.4):
                self.add("grounds", self.inst("lamp_post", g2b(gx, gy)))
        doors = self.doorways()
        for i, gx in enumerate([x * 0.8 for x in range(-1, int(W / 0.8) + 2)]):
            if all(abs(gx - d) > 1.3 for d in doors):
                self.add("grounds", self.inst("bush", g2b(gx, H + 0.75), r.uniform(0, 6.3), 0.85, seed=i))
        self.add("grounds", self.inst("fountain", g2b(W - 3.0, H + 2.4)))
        self.add("grounds", self.inst("bus_stop", g2b(1.5, road_y - 0.55)))

    def back_y(self):
        """Grid y of the building's rearmost edge, upper floors included."""
        return min([0.0] + [w["layout"]["rect"][1] for w in self.wings])

    def doorways(self):
        """Grid x of every opening in the building's front edge (entrance and exits)."""
        xs = [self.door_x()]
        for r in self.rooms:
            if r.get("role") == "lobby" and "exit" in r:
                xs.append(r["rect"][0] + r["exit"][0])
        return xs

    def door_x(self):
        for p in self.t.get("props", []):
            if p["kind"] == "facade":
                return p["at"][0] + p.get("len", 2.4) / 2
        return self.W / 2

    # ------------------------------------------------------------ building
    def plinth(self):
        inset = self.t.get("shell", {}).get("inset", 0.35)
        W, H = self.W, self.H
        self.add("building", box((W + 2 * inset, H + 2 * inset, PLINTH_TOP + 0.06),
                                 g2b(W / 2, H / 2, (PLINTH_TOP - 0.06) / 2), mat(self.s["exterior"], 0.5), bev=0.05))
        dx = self.door_x()
        for i in range(2):  # entrance steps
            self.add("building", box((3.0 - i * 0.4, 0.35, PLINTH_TOP - i * 0.05), g2b(dx, H + inset + 0.17 + (1 - i) * 0.3,
                                     (PLINTH_TOP - i * 0.05) / 2), mat(self.s["trim"], 0.45), bev=0.03))

    def floors(self):
        for room in self.rooms:
            x, y, w, h = room["rect"]
            style, a, b = self.s["floors"].get(room["id"], ("checker", "#FFF1D6", "#E6D5B8"))
            z = FLOOR_TOP - 0.025
            if style == "checker":
                for gx in range(int(x), int(x + w)):
                    for gy in range(int(y), int(y + h)):
                        self.add("building", box((1, 1, 0.05), g2b(gx + 0.5, gy + 0.5, z), mat(a if (gx + gy) % 2 else b, 0.25),
                                                 bev=0.015, seg=1))
            elif style == "planks":
                n = int(round(h / 0.5))
                for i in range(n):
                    self.add("building", box((w, 0.5, 0.05), g2b(x + w / 2, y + i * 0.5 + 0.25, z),
                                             mat(a if i % 2 else b, 0.3), bev=0.012, seg=1))
            else:  # carpet with a border
                self.add("building", box((w, h, 0.05), g2b(x + w / 2, y + h / 2, z), mat(b, 0.7)))
                self.add("building", box((w - 0.5, h - 0.5, 0.05), g2b(x + w / 2, y + h / 2, z + 0.01), mat(a, 0.8)))
        dress = self.t.get("dressing", {})
        for rug in dress.get("floor", []) + dress.get("carpet", []):
            (x, y), (w, h) = rug["at"], rug["size"]
            self.add("building", box((w, h, 0.02), g2b(x + w / 2, y + h / 2, FLOOR_TOP + 0.01), mat("#C0392B", 0.8)))
            self.add("building", box((w - 0.3, h - 0.3, 0.02), g2b(x + w / 2, y + h / 2, FLOOR_TOP + 0.02), mat("#E0B34A", 0.8)))

    def wall_kind(self, seg):
        (x, y), L = seg["at"], seg["len"]
        if seg["axis"] == "x":
            mx = x + L / 2
            if not self.inside(mx, y + 0.3):
                return "front", (0, 1)
            if not self.inside(mx, y - 0.3):
                return "back", (0, -1)
        else:
            my = y + L / 2
            if not self.inside(x + 0.3, my) or not self.inside(x - 0.3, my):
                return "side", (1, 0) if not self.inside(x + 0.3, my) else (-1, 0)
        return "inner", (0, 0)

    def walls(self):
        ext, trim = self.s["exterior"], self.s["trim"]
        for seg in self.t.get("walls", []):
            (x, y), L = seg["at"], seg["len"]
            kind, out = self.wall_kind(seg)
            h = {"back": H_BACK, "side": H_SIDE, "inner": H_INNER, "front": H_FRONT}[kind]
            col = self.wall_colour(seg.get("col", "@shell"))
            along_x = seg["axis"] == "x"
            cx, cy = (x + L / 2, y) if along_x else (x, y + L / 2)
            size = (L + WALL_T, WALL_T, h) if along_x else (WALL_T, L + WALL_T, h)
            z = FLOOR_TOP + h / 2
            if kind == "inner" or kind == "front":
                self.add("building", box(size, g2b(cx, cy, z), mat(col if kind == "inner" else ext, 0.45), bev=0.04))
            else:  # outer wall: room colour inside, stone outside
                half = WALL_T / 2
                inner = (size[0], half, h) if along_x else (half, size[1], h)
                ox, oy = out
                self.add("building", box(inner, g2b(cx - ox * half / 2, cy - oy * half / 2, z), mat(col, 0.45), bev=0.03))
                self.add("building", box(inner, g2b(cx + ox * half / 2, cy + oy * half / 2, z), mat(ext, 0.5), bev=0.03))
            cap = (size[0] + 0.06, size[1] + 0.06, 0.08)
            self.add("building", box(cap, g2b(cx, cy, FLOOR_TOP + h + 0.02), mat(trim, 0.35), bev=0.03))
            if kind != "front":
                base = (size[0] + 0.03, size[1] + 0.03, 0.12)
                self.add("building", box(base, g2b(cx, cy, FLOOR_TOP + 0.06), mat(shade(col, 0.7), 0.5), bev=0.02))

    def wall_dressing(self):
        for d in self.t.get("dressing", {}).get("wall", []):
            (x, y), L = d["at"], d.get("len", 0.8)
            along_x = d["axis"] == "x"
            col = d.get("col", "#8E6BB0")
            col = self.wall_colour(col) if col.startswith("@") else col
            cx, cy = (x + L / 2, y + WALL_T / 2 + 0.03) if along_x else (x + WALL_T / 2 + 0.03, y + L / 2)
            size = (L, 0.05, 0.6) if along_x else (0.05, L, 0.6)
            frame = (L + 0.1, 0.04, 0.7) if along_x else (0.04, L + 0.1, 0.7)
            self.add("building", box(frame, g2b(cx, cy, FLOOR_TOP + 1.2), mat("#C99A3A", 0.3, metal=0.3), bev=0.02))
            self.add("building", box(size, g2b(cx + (0 if along_x else 0.02), cy + (0.02 if along_x else 0), FLOOR_TOP + 1.2),
                                     mat(col, 0.5)))

    def crown(self):
        """Grand silhouette on the back wall: cornice, pediment, dome, flags, name.

        With upper floors the crown rides the TOP floor's back wall instead: a
        pediment on the ground floor's back wall would stand in front of the
        second floor and hide it from the camera."""
        W = self.W
        ext, trim, acc = self.s["exterior"], self.s["trim"], self.s["accent"]
        top = FLOOR_TOP + H_BACK
        self.add("crown", box((W + 0.5, 0.5, 0.2), g2b(W / 2, -0.1, top + 0.1), mat(trim, 0.35), bev=0.05))
        if self.wings:
            self.upper_crown()
            return
        gal = next((r for r in self.rooms if r.get("role") == "exhibit"), self.rooms[0])
        cx = gal["rect"][0] + gal["rect"][2] / 2
        self.add("crown", box((6.0, 0.4, 0.9), g2b(cx, -0.1, top + 0.65), mat(ext, 0.5), bev=0.05))
        ped = toy.prism(6.6, 0.8, 1.2, g2b(cx, -0.1, top + 1.1), mat(acc, 0.3), bev=0.06)
        ped.rotation_euler = (0, 0, 0)
        self.add("crown", ped)
        for i in range(6):  # pilasters under the pediment
            self.add("crown", cyl(0.14, 0.9, g2b(cx - 2.5 + i, 0.12, top + 0.65), mat(trim, 0.4), bev=0.02))
        self.add("crown", [cyl(1.25, 0.7, g2b(cx, -1.2, top + 1.2), mat(ext, 0.5), bev=0.04),
                           cyl(0.08, 0.9, g2b(cx, -1.2, top + 3.0), mat("#2E3A4A", 0.35)),
                           sphere(0.14, g2b(cx, -1.2, top + 2.72), mat("#F2C14E", 0.25, metal=0.5))])
        self.add("dome", sphere(1.3, g2b(cx, -1.2, top + 1.55), mat(self.s["dome"], 0.3, name="dome"), scale=(1, 1, 0.9)))
        for fx in (0.3, W - 0.3):  # corner flags
            self.add("crown", [cyl(0.05, 1.8, g2b(fx, -0.2, top + 0.9), mat("#2E3A4A", 0.35)),
                               box((0.6, 0.04, 0.35), g2b(fx + 0.32, -0.2, top + 1.6), mat(acc, 0.4), bev=0.02)])
        name = self.v.get("name", self.v["id"]).upper()
        bpy.ops.object.text_add(location=g2b(cx, 0.35, top + 0.62))
        txt = bpy.context.active_object
        txt.data.body = name
        txt.data.align_x = "CENTER"
        txt.data.align_y = "CENTER"
        txt.data.size = 0.36
        txt.data.extrude = 0.03
        txt.rotation_euler = (math.pi / 2, 0, 0)
        bpy.ops.object.convert(target="MESH")
        toy.set_mat(txt, mat("#5A3A1A", 0.4))
        self.add("crown", txt)

    # ------------------------------------------------------------ upper floors
    def upper_crown(self):
        """Pediment, name, flags and the domed pavilion on the top floor."""
        ext, trim, acc = self.s["exterior"], self.s["trim"], self.s["accent"]
        w = self.wings[-1]
        L = w["layout"]
        x, y, wd, h = L["rect"]
        base = L["y"]
        cx = x + wd / 2
        top = base + H_BACK
        self.add("crown", box((wd + 0.5, 0.5, 0.2), g2b(cx, y - 0.1, top + 0.1), mat(trim, 0.35), bev=0.05))
        self.add("crown", box((min(6.0, wd - 1.0), 0.4, 0.9), g2b(cx, y - 0.1, top + 0.65), mat(ext, 0.5), bev=0.05))
        self.add("crown", toy.prism(min(6.6, wd - 0.4), 0.8, 1.2, g2b(cx, y - 0.1, top + 1.1), mat(acc, 0.3), bev=0.06))
        for fx in (x + 0.3, x + wd - 0.3):
            self.add("crown", [cyl(0.05, 1.8, g2b(fx, y - 0.2, top + 0.9), mat("#2E3A4A", 0.35)),
                               box((0.6, 0.04, 0.35), g2b(fx + 0.32, y - 0.2, top + 1.6), mat(acc, 0.4), bev=0.02)])
        dx, dy = L.get("dome", [cx, y + 1.5])
        drum_h = 2.1
        self.add("crown", [cyl(1.25, drum_h, g2b(dx, dy, base + drum_h / 2), mat(ext, 0.5), bev=0.04),
                           torus(1.26, 0.08, g2b(dx, dy, base + drum_h), mat(trim, 0.35)),
                           cyl(0.08, 0.9, g2b(dx, dy, base + drum_h + 2.0), mat("#2E3A4A", 0.35)),
                           sphere(0.14, g2b(dx, dy, base + drum_h + 1.75), mat("#F2C14E", 0.25, metal=0.5))])
        for i in range(8):  # arched windows round the drum
            a = i / 8 * math.tau
            px, py = dx + math.cos(a) * 1.24, dy + math.sin(a) * 1.24
            self.add("crown", box((0.34, 0.06, 0.8), g2b(px, py, base + 1.1), mat("#9FD3F0", 0.15), bev=0.02,
                                  rot=(0, 0, -a + math.pi / 2)))
        self.add("dome", sphere(1.3, g2b(dx, dy, base + drum_h + 0.35), mat(self.s["dome"], 0.3, name="dome"), scale=(1, 1, 0.9)))
        self.name_sign(cx, y + 0.35, top + 0.62)

    def name_sign(self, cx, gy, z):
        name = self.v.get("name", self.v["id"]).upper()
        bpy.ops.object.text_add(location=g2b(cx, gy, z))
        txt = bpy.context.active_object
        txt.data.body = name
        txt.data.align_x = "CENTER"
        txt.data.align_y = "CENTER"
        txt.data.size = 0.36
        txt.data.extrude = 0.03
        txt.rotation_euler = (math.pi / 2, 0, 0)
        bpy.ops.object.convert(target="MESH")
        toy.set_mat(txt, mat("#5A3A1A", 0.4))
        self.add("crown", txt)

    def upper_floors(self):
        prev_top = FLOOR_TOP
        for w in self.wings:
            self.upper_floor(w, prev_top)
            prev_top = w["layout"]["y"]

    def upper_floor(self, w, below):
        """One terraced storey: podium with windows, patterned floor, walls,
        a balustrade with a gap where the lift lands, and the lift itself."""
        g = "floor_" + w["id"]
        L = w["layout"]
        x, y, wd, h = L["rect"]
        top = L["y"]
        ext, trim = self.s["exterior"], self.s["trim"]
        wall = L.get("wall", self.s["walls"]["shell"])
        # podium: the storeys underneath, seen as a stone block with windows
        self.add(g, box((wd, h, top - 0.05), g2b(x + wd / 2, y + h / 2, (top - 0.05) / 2), mat(ext, 0.5), bev=0.05))
        self.add(g, box((wd + 0.16, h + 0.16, 0.14), g2b(x + wd / 2, y + h / 2, top - 0.12), mat(trim, 0.35), bev=0.04))
        storeys = max(1, int(round(top / 2.9)))
        for sx in (x - 0.03, x + wd + 0.03):  # windows on the exposed sides
            for k in range(storeys):
                zc = k * 2.9 + 1.5
                for j in range(int(h // 1.6)):
                    gy = y + 0.8 + j * 1.6
                    self.add(g, box((0.06, 0.6, 0.9), g2b(sx, gy, zc), mat("#9FD3F0", 0.15), bev=0.02))
                    self.add(g, box((0.08, 0.72, 0.08), g2b(sx, gy, zc - 0.5), mat(trim, 0.35), bev=0.02))
        style, a, b = L.get("floor", ["planks", "#EFC27E", "#E2B06A"])
        z = top - 0.025
        if style == "checker":
            for gx in range(int(x), int(x + wd)):
                for gy in range(int(y), int(y + h)):
                    self.add(g, box((1, 1, 0.05), g2b(gx + 0.5, gy + 0.5, z), mat(a if (gx + gy) % 2 else b, 0.25), bev=0.015, seg=1))
        else:
            n = int(round(h / 0.5))
            for i in range(n):
                self.add(g, box((wd, 0.5, 0.05), g2b(x + wd / 2, y + i * 0.5 + 0.25, z), mat(a if i % 2 else b, 0.3), bev=0.012, seg=1))
        # walls: tall back, medium sides (room colour inside, stone outside)
        def wall_seg(cx, cy, sx, sy, hh, inner_col, out):
            half = WALL_T / 2
            if sx > sy:
                self.add(g, box((sx, half, hh), g2b(cx, cy - out * half / 2, top + hh / 2), mat(inner_col, 0.45), bev=0.03))
                self.add(g, box((sx, half, hh), g2b(cx, cy + out * half / 2, top + hh / 2), mat(ext, 0.5), bev=0.03))
            else:
                self.add(g, box((half, sy, hh), g2b(cx - out * half / 2, cy, top + hh / 2), mat(inner_col, 0.45), bev=0.03))
                self.add(g, box((half, sy, hh), g2b(cx + out * half / 2, cy, top + hh / 2), mat(ext, 0.5), bev=0.03))
            self.add(g, box((sx + 0.06, sy + 0.06, 0.08), g2b(cx, cy, top + hh + 0.02), mat(trim, 0.35), bev=0.03))
        wall_seg(x + wd / 2, y, wd + WALL_T, WALL_T, H_BACK, wall, -1)
        wall_seg(x, y + h / 2, WALL_T, h, H_SIDE, wall, -1)
        wall_seg(x + wd, y + h / 2, WALL_T, h, H_SIDE, wall, 1)
        # front balustrade, open where the lift lands
        lift = L.get("lift")
        gap = (lift["at"][0] - 0.65, lift["at"][0] + 0.65) if lift else (1e9, 1e9)
        fy = y + h
        segs = [(x, gap[0]), (gap[1], x + wd)] if lift and x < gap[0] < x + wd else [(x, x + wd)]
        for s0, s1 in segs:
            if s1 - s0 < 0.1:
                continue
            self.add(g, box((s1 - s0, WALL_T * 0.7, 0.12), g2b((s0 + s1) / 2, fy, top + 0.06), mat(trim, 0.4), bev=0.02))
            self.add(g, box((s1 - s0, WALL_T * 0.8, 0.08), g2b((s0 + s1) / 2, fy, top + 0.62), mat(trim, 0.35), bev=0.02))
            px = s0 + 0.15
            while px < s1 - 0.1:
                self.add(g, cyl(0.045, 0.5, g2b(px, fy, top + 0.35), mat(ext, 0.45), r2=0.035, bev=0.01, verts=10))
                px += 0.3
        if lift:
            self.lift(w, below, top)

    def lift(self, w, bottom, top):
        """Glass elevator: brass-framed shaft from `bottom` to above `top`, a
        landing into the floor, and a separate cabin Godot moves."""
        g = "lift_" + w["id"]
        L = w["layout"]
        ax, ay = L["lift"]["at"]
        brass = mat("#E0B34A", 0.25, metal=0.6)
        glass = mat("#BFE6FF", 0.05, alpha=0.28)
        hgt = top - bottom + 2.1
        for sx in (-0.55, 0.55):
            for sy in (-0.5, 0.5):
                self.add(g, cyl(0.05, hgt, g2b(ax + sx, ay + sy, bottom + hgt / 2), brass, bev=0))
            self.add(g, box((0.04, 1.0, hgt - 0.2), g2b(ax + sx, ay, bottom + hgt / 2), glass))
        self.add(g, box((1.26, 1.16, 0.12), g2b(ax, ay, bottom + hgt), mat(self.s["trim"], 0.35), bev=0.03))
        self.add(g, sphere(0.22, g2b(ax, ay, bottom + hgt + 0.1), mat(self.s["accent"], 0.3), scale=(1, 1, 0.6)))
        self.add(g, box((1.2, 1.1, 0.06), g2b(ax, ay, bottom + 0.03), mat("#2E3A4A", 0.4), bev=0.02))
        # landing between the shaft and the floor's front edge
        fx, fy, fw, fh = L["rect"]
        front = fy + fh
        near = ay - 0.5
        y0, y1 = sorted((near, front - 0.4))
        self.add(g, box((1.1, max(0.2, y1 - y0 + 0.4), 0.06), g2b(ax, (y0 + y1) / 2, top - 0.03), mat(self.s["trim"], 0.4), bev=0.02))
        # the cabin, built round its own origin so Godot can slide it up and down
        parts = [box((1.0, 0.9, 0.08), (0, 0, 0.04), mat("#2E3A4A", 0.4), bev=0.02),
                 box((1.0, 0.9, 0.08), (0, 0, 1.36), brass, bev=0.02),
                 sphere(0.09, (0, 0, 1.46), mat("#FFF2B0", 0.2, emit=2.0), seg=12)]
        for sx in (-0.47, 0.47):
            parts.append(box((0.04, 0.86, 1.24), (sx, 0, 0.7), glass))
            for sy in (-0.43, 0.43):
                parts.append(cyl(0.035, 1.3, (sx, sy, 0.7), brass, bev=0))
        cab = toy.join(parts, "cabin_" + w["id"])
        cab.location = g2b(ax, ay, bottom)
        self.groups["cabin_" + w["id"]] = [cab]

    # ------------------------------------------------------------ grandeur (exterior dressing by tier)
    def grandeur(self, road_y):
        W, H = self.W, self.H
        dx = self.door_x()
        # II  Restored: banners and topiaries
        for bx in (dx - 2.3, dx + 2.3):
            self.add("grand_2", self.inst("banner", g2b(bx, H + 1.35)))
        for bx in (0.35, W - 0.35):
            self.add("grand_2", self.inst("banner", g2b(bx, H + 0.55)))
        for bx in (dx - 1.5, dx + 1.5):
            self.add("grand_2", self.inst("topiary", g2b(bx, H + 1.25)))
        # III Grand: red carpet to the pavement, velvet ropes, spotlights
        c0, c1 = H + 0.95, road_y - 0.95
        self.add("grand_3", box((1.7, c1 - c0, 0.03), g2b(dx, (c0 + c1) / 2, 0.095), mat("#E0B34A", 0.4)))
        self.add("grand_3", box((1.4, c1 - c0, 0.035), g2b(dx, (c0 + c1) / 2, 0.1), mat("#B81E2E", 0.7)))
        gy = c0 + 0.4
        while gy < c1:
            for side in (-1, 1):
                self.add("grand_3", self.inst("rope_post", g2b(dx + side * 1.05, gy)))
            gy += 1.1
        for bx in (0.8, W - 0.8, dx - 3.2, dx + 3.2):
            self.add("grand_3", self.inst("spotlight", g2b(bx, H + 0.62)))
        # IV Magnificent: gilded statues in the square (the dome turns gold in Godot)
        for bx in (dx - 3.6, dx + 3.6):
            self.add("grand_4", self.inst("gold_statue", g2b(bx, H + 2.7)))

    # ------------------------------------------------------------ props (preview only)
    def place_props(self):
        """Mirror of scenes/venue3d placement rules, for the Blender preview."""
        placed = []
        for spec in self.t.get("props", []) + self.t.get("exhibits", []):
            kind = spec["kind"]
            if kind not in props.PROPS:
                continue
            placed.append(self._place(kind, spec))
        for room in self.rooms:
            ox, oy = room["rect"][0], room["rect"][1]
            if room.get("role") == "exhibit":
                for sx, sy in room.get("stations", []):
                    placed.append(self._place("docent_stand", {"at": [ox + sx, oy + sy]}))
            q = room.get("queue")
            if q:
                for st in q.get("stations", []):
                    base = next((r for r in self.rooms if r["id"] == st.get("room")), room)["rect"]
                    ax, ay = base[0] + st["at"][0], base[1] + st["at"][1]
                    fx, fy = st.get("front", [1, 0])
                    placed.append(self._place("ticket_counter", {"at": [ax + fx * 0.15, ay + fy * 0.15], "front": [fx, fy]}))
        return placed

    def _place(self, kind, spec):
        fpx, fpy = props.PROPS[kind][1]
        at = spec["at"]
        if "size" in spec:
            sx, sy = spec["size"]
        elif "len" in spec or kind == "bench":
            L = spec.get("len", 1.5)
            sx, sy = (0.4, L) if spec.get("axis", "x") == "y" else (L, 0.4)
        else:
            sx = sy = None
        if kind == "mural":
            L = spec.get("len", 2.2)
            o = self.inst(kind, g2b(at[0] + L / 2, at[1] + WALL_T / 2 + 0.05, FLOOR_TOP + 0.55))
            return o
        if kind in ("vault_door",):
            L = spec.get("len", 1.6)
            vertical = spec.get("axis", "x") == "y"
            c = (at[0], at[1] + L / 2) if vertical else (at[0] + L / 2, at[1])
            return self.inst(kind, g2b(c[0], c[1], FLOOR_TOP), math.pi / 2 if vertical else 0.0)
        if kind == "facade":
            L = spec.get("len", 2.4)
            return self.inst(kind, g2b(at[0] + L / 2, at[1], FLOOR_TOP))
        if sx is None:
            rz = 0.0
            f = spec.get("front")
            if f:  # turn the model's front (-Y, i.e. grid +gy) to face `front`
                rz = math.atan2(f[0], f[1])
            return self.inst(kind, g2b(at[0], at[1], FLOOR_TOP), rz)
        rotate = (fpx >= fpy) != (sx >= sy)
        o = self.inst(kind, g2b(at[0] + sx / 2, at[1] + sy / 2, FLOOR_TOP), math.pi / 2 if rotate else 0.0)
        long_s, short_s = max(sx, sy), min(sx, sy)
        long_m, short_m = max(fpx, fpy), min(fpx, fpy)
        k = long_s / long_m
        o.scale = (k, max(0.6, min(1.4, short_s / short_m)), 1.0) if not rotate else (max(0.6, min(1.4, short_s / short_m)), k, 1.0)
        return o

    # ------------------------------------------------------------ run
    def build(self):
        road_y = self.grounds()
        self.plinth()
        self.floors()
        self.walls()
        self.wall_dressing()
        self.upper_floors()
        self.crown()
        self.outdoors(road_y)
        self.grandeur(road_y)
        out = {}
        for g, objs in self.groups.items():
            if objs:
                out[g] = toy.join(objs, g)
        return out


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    vid = argv[0] if argv else "whispering_pines"
    venue = load_venue(vid)
    toy.reset()
    b = Builder(venue)
    groups = b.build()
    folder = os.path.join(toy.ART3D, "venues", vid)
    toy.export_glb(os.path.join(folder, "shell.glb"), list(groups.values()))
    if "--preview" in argv:
        b.place_props()
        toy.preview(os.path.join(toy.ROOT, "docs", "visual-overhaul", f"{vid}_blender_preview.png"), target=g2b(b.W / 2, b.H / 2 + 2.5), dist=34, tilt_deg=38,
                    lens=35, res=(1080, 1920), fstop=0.0)


if __name__ == "__main__":
    main()
