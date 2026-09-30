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
STOREY = 2.8  # height between theme levels (rooms with "level": 1, 2, 3)

# Open plan (owner, 2026-09-30): each storey is one grand, open concourse, a
# shopping mall retrofitted as a museum. Partition walls between rooms are not
# built; a colonnade stands where they ran, the floor is one continuous stone
# concourse with each department as an inset zone in its own finish, and every
# open edge (the street front, a mezzanine's lip) is a glass balustrade. The
# authored walls stay in data/venues.json: rooms, doors and the 2D floor still
# read them.
OPEN_PLAN = True
COLUMN_EVERY = 3.5   # grid units between columns along a removed wall
COLUMN_H = 2.2
GLASS = "#CFE6EE"

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


SURROUNDS = {
    # lawn stripes, paving, tree kind
    "parkland": (("#6CC24A", "#62B843"), ("#E8DCC4", "#D8CAB0"), "tree"),
    "harbour": (("#6CC24A", "#5DB443"), ("#DCE3E6", "#C9D2D6"), "tree"),
    "dunes": (("#EBC98A", "#E2BD78"), ("#F1DDB0", "#E4CC98"), "palm"),
    "alpine": (("#EEF4F8", "#E3ECF2"), ("#D6DEE6", "#C8D2DC"), "pine"),
    "nightfall": (("#4E9A6A", "#468F61"), ("#C9CCD8", "#B8BCCB"), "pine"),
    "gardens": (("#63C24E", "#57B544"), ("#E6DCC8", "#D8CCB4"), "tree"),
    "clock_district": (("#76B85A", "#6BAE50"), ("#C8C0B2", "#B7AE9F"), "tree"),
    "palace_gardens": (("#68C650", "#5DBA46"), ("#F0E4D0", "#E2D4BC"), "tree"),
    "worlds_campus": (("#6CC24A", "#62B843"), ("#E2DAF0", "#D2C8E6"), "tree"),
}


# Hand-authored toy palettes per museum: wall colours and four floor styles
# (queue, exhibit, promo, lobby); link rooms cycle through all of them so a
# big museum reads as many distinct rooms, not one beige plan.
VENUE_PALETTES = {
    "copper_kettle": {"walls": ["#2E8BC0", "#48B5A8", "#F28C6B", "#5FA8D3", "#F2C14E"],
                      "floors": [("checker", "#EAF6FA", "#8FD0E8"), ("planks", "#E9D3A8", "#DCC296"),
                                 ("carpet", "#2E8BC0", "#F2C14E"), ("checker", "#F4EBD8", "#F28C6B")],
                      "exterior": "#EAF2F4", "accent": "#F28C6B", "dome": "#48B5A8"},
    "grand_river": {"walls": ["#C8663A", "#3F6FB0", "#6FAE5A", "#E8D8B8", "#A8324A"],
                    "floors": [("checker", "#F6F1E6", "#C8663A"), ("planks", "#E8C890", "#D8B47A"),
                               ("carpet", "#A8324A", "#E8B83A"), ("checker", "#F6F1E6", "#9FB8C8")],
                    "exterior": "#F4EEE2", "accent": "#A8324A", "dome": "#3F6FB0"},
    "sunspire": {"walls": ["#E8A43A", "#2F6FB0", "#D9643A", "#F2D58E", "#3FA6A0"],
                 "floors": [("checker", "#FFF3D6", "#2F6FB0"), ("planks", "#F2C878", "#E8B860"),
                            ("carpet", "#D9643A", "#F2C14E"), ("checker", "#FFF3D6", "#E8A43A")],
                 "exterior": "#F6E6C4", "accent": "#D9643A", "dome": "#F2C14E"},
    "cloudrest": {"walls": ["#5FA8E8", "#2F7A4A", "#8FA0AE", "#E8F2FA", "#C0392B"],
                  "floors": [("checker", "#F4FAFE", "#9FCCF0"), ("planks", "#D8B48A", "#C8A47A"),
                             ("carpet", "#2F7A4A", "#EAF4FA"), ("checker", "#F4FAFE", "#8FA0AE")],
                  "exterior": "#EEF4F8", "accent": "#3A78D8", "dome": "#9FD3F0"},
    "aurora_world": {"walls": ["#3A3A8C", "#2FA67A", "#7E5FC8", "#C9CED6", "#1F8A9A"],
                     "floors": [("checker", "#E8ECF8", "#3A3A8C"), ("planks", "#B8A4D8", "#A894C8"),
                                ("carpet", "#2FA67A", "#B58CE8"), ("checker", "#E8ECF8", "#2FA67A")],
                     "exterior": "#E4E8F2", "accent": "#7E5FC8", "dome": "#2FA67A"},
    "celestial_conservatory": {"walls": ["#4FAE6A", "#8FB8E8", "#9F7ED8", "#F2EAD8", "#2FA6A0"],
                               "floors": [("checker", "#F4FAF0", "#8BD06A"), ("planks", "#C8E0A8", "#B8D098"),
                                          ("carpet", "#9F7ED8", "#DFF4FF"), ("checker", "#F4FAF0", "#8FB8E8")],
                               "exterior": "#F2F6EE", "accent": "#9F7ED8", "dome": "#BFE6FF"},
    "ironwood_citadel": {"walls": ["#8C8C94", "#B8322A", "#5A5A66", "#D8C8A8", "#2F5A8C"],
                         "floors": [("checker", "#E8E4DC", "#8C8C94"), ("planks", "#A87E5A", "#98704E"),
                                    ("carpet", "#B8322A", "#E8B83A"), ("checker", "#E8E4DC", "#B8322A")],
                         "exterior": "#D8D4CC", "accent": "#B8322A", "dome": "#8C8C94"},
    "pelagic_crown": {"walls": ["#1FAFC1", "#F07D78", "#2E5E9C", "#F4F1FA", "#F3C969"],
                      "floors": [("checker", "#EFFAFC", "#1FAFC1"), ("planks", "#E8D8C0", "#DCC8B0"),
                                 ("carpet", "#F07D78", "#F3C969"), ("checker", "#EFFAFC", "#F07D78")],
                      "exterior": "#EEF6F8", "accent": "#F07D78", "dome": "#1FAFC1"},
    "chronos_spire": {"walls": ["#C9963A", "#6B3A22", "#2F8C8C", "#F0E6D0", "#8C2F2F"],
                      "floors": [("checker", "#F6EEDC", "#6B3A22"), ("planks", "#B87A48", "#A86A3A"),
                                 ("carpet", "#2F8C8C", "#E8C35A"), ("checker", "#F6EEDC", "#C9963A")],
                      "exterior": "#EEE4D0", "accent": "#8C2F2F", "dome": "#C9963A"},
    "empyrean_palace": {"walls": ["#E86FA0", "#9F7ED8", "#E8B83A", "#FAF0F4", "#5FA8E8"],
                        "floors": [("checker", "#FFF4F8", "#E86FA0"), ("planks", "#F2D0DC", "#E8C0D0"),
                                   ("carpet", "#9F7ED8", "#FFE08A"), ("checker", "#FFF4F8", "#9F7ED8")],
                        "exterior": "#FAF2F4", "accent": "#E86FA0", "dome": "#E8B83A"},
    "infinite_museum": {"walls": ["#7E5FC8", "#2FA6A0", "#F28C3A", "#E86FA0", "#3A78D8"],
                        "floors": [("checker", "#F6F2FE", "#7E5FC8"), ("planks", "#E8C890", "#D8B47A"),
                                   ("carpet", "#2FA6A0", "#F2C14E"), ("checker", "#F6F2FE", "#F28C3A")],
                        "exterior": "#F2EEFA", "accent": "#7E5FC8", "dome": "#F2C14E"},
}


def toyify(hexc, sat=1.9, val=1.12):
    """Push a muted theme colour toward the saturated toy palette."""
    import colorsys
    h = hexc.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    hh, ss, vv = colorsys.rgb_to_hsv(r, g, b)
    ss = min(0.85, ss * sat + 0.08)
    vv = min(0.97, vv * val + 0.05)
    r, g, b = colorsys.hsv_to_rgb(hh, ss, vv)
    return "#%02X%02X%02X" % (round(r * 255), round(g * 255), round(b * 255))


def mix(a, b, t):
    """Blend two hex colours: t=0 is a, t=1 is b."""
    pa = [int(a.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)]
    pb = [int(b.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)]
    return "#%02X%02X%02X" % tuple(round(x + (y - x) * t) for x, y in zip(pa, pb))


def auto_style(venue, theme):
    """A STYLES entry derived from the venue's own 2D palette and surround."""
    pal = theme.get("palette", {})
    def col(key, fallback):
        v = pal.get(key, fallback)
        return v if isinstance(v, str) and v.startswith("#") else fallback
    walls = {"shell": toyify(col("panel", "#F3E2BF"), 1.2, 1.02)}
    floors = {}
    light = toyify(col("floor", "#FFF1D6"), 1.4, 1.05)
    for r in theme.get("rooms", []):
        dept = r.get("dept", r.get("merge_into", ""))
        base = col("room." + dept, "") or col("room." + r["id"], "") or col("stone", "#C9B896")
        c = toyify(base)
        walls[r["id"]] = c
        if dept:
            walls[dept] = c
        role = r.get("role", "link")
        if role == "exhibit":
            floors[r["id"]] = ("planks", toyify(base, 1.2, 1.25), toyify(base, 1.2, 1.12))
        elif role == "store":
            floors[r["id"]] = ("planks", toyify(base, 1.4, 1.2), toyify(base, 1.4, 1.08))
        elif role == "promo":
            floors[r["id"]] = ("carpet", c, toyify(col("trim", "#F2C14E")))
        elif role == "queue":
            floors[r["id"]] = ("checker", light, toyify(base, 2.2, 1.1))
        else:
            floors[r["id"]] = ("checker", light, toyify(col("stone", "#D9C4A0"), 1.3, 1.1))
    lawn, paving, tree = SURROUNDS.get(theme.get("surround", "parkland"), SURROUNDS["parkland"])
    style = {"floors": floors, "walls": walls, "exterior": toyify(col("panel", "#EFE3CC"), 1.1, 1.0),
             "trim": "#FFF7E6", "accent": toyify(col("carpet", "#D9413A"), 1.6, 1.1),
             "dome": toyify(col("trim", "#5FB8A0"), 1.5, 1.1), "lawn": lawn, "paving": paving, "tree": tree,
             "surround": theme.get("surround", "parkland")}
    vp = VENUE_PALETTES.get(venue["id"])
    if vp:
        role_floor = {"queue": 0, "exhibit": 1, "promo": 2, "lobby": 3}
        wi = 0
        for i, r in enumerate(theme.get("rooms", [])):
            role = r.get("role", "link")
            f = vp["floors"][role_floor[role]] if role in role_floor else vp["floors"][(i + 1) % len(vp["floors"])]
            if role == "store":
                f = ("planks", vp["walls"][0], shade(vp["walls"][0], 0.9))
            floors[r["id"]] = f
            c = vp["walls"][wi % len(vp["walls"])]
            wi += 1
            walls[r["id"]] = c
            if r.get("dept"):
                walls[r["dept"]] = c
        style.update({k: vp[k] for k in ("exterior", "accent", "dome")})
    return style


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
    by_id = {v["id"]: v for v in venues}

    def resolve(t):
        if "extends" not in t:
            return t
        out = dict(resolve(by_id[t["extends"]]["theme"]))
        out.update({k: v for k, v in t.items() if k != "extends"})
        return out
    v = dict(by_id[vid])
    v["theme"] = resolve(v["theme"])
    return v


class Builder:
    def __init__(self, venue):
        self.v = venue
        self.t = venue["theme"]
        self.s = STYLES.get(venue["id"]) or auto_style(venue, self.t)
        self.rooms = self.t["rooms"]
        self.levels = sorted({int(r.get("level", 0)) for r in self.rooms})
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
        self.floor_meta = {}  # group name -> glTF extras (rect, y, lift spots) for Godot
        for lv in self.levels:
            if lv > 0:
                self.groups[self.level_group(lv)] = []
                self.groups["lift_floor_%d" % lv] = []

    # ------------------------------------------------------------ storeys
    def level_group(self, lv):
        """Theme level L >= 1 is the auto wing "floor_L" (WingSystem), whose
        geometry Godot finds as node floor_floor_L."""
        return "building" if lv <= 0 else "floor_floor_%d" % lv

    def base(self, lv):
        return FLOOR_TOP + max(0, lv) * STOREY

    def level_of(self, gx, gy):
        r = self.room_at(gx, gy)
        return int(r.get("level", 0)) if r else 0

    def add(self, group, objs):
        self.groups.setdefault(group, [])
        self.groups[group] += objs if isinstance(objs, list) else [objs]

    # ------------------------------------------------------------ helpers
    def room_at(self, gx, gy, level=None):
        for r in self.rooms:
            if level is not None and int(r.get("level", 0)) != level:
                continue
            x, y, w, h = r["rect"]
            if x <= gx <= x + w and y <= gy <= y + h:
                return r
        return None

    def inside(self, gx, gy, level=None):
        return self.room_at(gx, gy, level) is not None

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
        if self.s.get("surround") == "harbour":
            # The sea behind the building: water, a sandy strand and a jetty.
            sea0 = self.back_y() - 3.0
            self.add("grounds", box((x1 - x0, sea0 - y0, 0.1), g2b((x0 + x1) / 2, (y0 + sea0) / 2, -0.02), mat("#2E9FD8", 0.15)))
            self.add("grounds", box((x1 - x0, 1.2, 0.12), g2b((x0 + x1) / 2, sea0 + 0.6, -0.01), mat("#EBD9A8", 0.8)))
            for k in range(6):
                self.add("grounds", box((x1 - x0, 0.06, 0.02), g2b((x0 + x1) / 2, y0 + 1.5 + k * (sea0 - y0 - 2) / 6, 0.04),
                                        mat("#BFE9FF", 0.3)))
            jx = W * 0.7
            self.add("grounds", box((1.2, 5.0, 0.12), g2b(jx, sea0 - 2.4, 0.12), mat("#B8783F", 0.6), bev=0.02))
            for k in range(4):
                for sx in (-0.5, 0.5):
                    self.add("grounds", cyl(0.08, 0.6, g2b(jx + sx, sea0 - 0.6 - k * 1.3, 0.0), mat("#7A4A2A", 0.6), bev=0))
            y0 = sea0
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
        if self.s.get("surround") != "harbour":  # a harbour museum backs onto the sea
            for gx in range(-2, int(W) + 3, 2):  # behind the building
                spots.append((gx + r.uniform(-0.4, 0.4), self.back_y() - 2.2 - r.uniform(0, 2.5)))
        else:
            spots = [(gx, gy) for gx, gy in spots if gy > self.back_y() - 2.5]
        # Trees and bushes are INSTANCED in Godot (one shared mesh, many
        # transforms): baked copies were two thirds of every shell's vertices.
        # Their spots ride on the grounds node as flat [gx, gy, rot, scale, ...].
        kind = self.s.get("tree", "tree")
        self.scatter = {"trees_kind": kind, "trees": [], "bushes": []}
        for i, (gx, gy) in enumerate(spots):
            self.scatter["trees"] += [round(gx, 3), round(gy, 3), round(r.uniform(0, 6.3), 3), round(r.uniform(1.0, 1.3), 3)]
        for gx in (-1.2, W + 1.2):  # plaza lamps and hedges
            for gy in (H + 1.0, road_y - 1.4):
                self.add("grounds", self.inst("lamp_post", g2b(gx, gy)))
        doors = self.doorways()
        for i, gx in enumerate([x * 0.8 for x in range(-1, int(W / 0.8) + 2)]):
            if all(abs(gx - d) > 1.3 for d in doors):
                self.scatter["bushes"] += [round(gx, 3), round(H + 0.75, 3), round(r.uniform(0, 6.3), 3), 0.85]
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

    def concourse_tones(self):
        """Polished stone for the whole concourse: two close tones of a warm
        stone, nudged toward the museum's own exterior."""
        base = mix("#E2D7C5", self.s["exterior"], 0.2)
        return base, shade(base, 0.93)

    def concourse(self):
        """One continuous floor under every room of a storey, in 2x2 slabs on a
        grid shared by all rooms so neighbouring rooms join without a seam."""
        a, b = self.concourse_tones()
        for room in self.rooms:
            x, y, w, h = room["rect"]
            lv = int(room.get("level", 0))
            g = self.level_group(lv)
            z = self.base(lv) - 0.025
            gx = math.floor(x / 2) * 2
            while gx < x + w - 1e-6:
                gy = math.floor(y / 2) * 2
                while gy < y + h - 1e-6:
                    x0, x1 = max(x, gx), min(x + w, gx + 2)
                    y0, y1 = max(y, gy), min(y + h, gy + 2)
                    if x1 - x0 > 0.01 and y1 - y0 > 0.01:
                        tone = a if (int(gx / 2) + int(gy / 2)) % 2 else b
                        self.add(g, box((x1 - x0, y1 - y0, 0.05), g2b((x0 + x1) / 2, (y0 + y1) / 2, z),
                                        mat(tone, 0.9), bev=0.006, seg=1))
                    gy += 2
                gx += 2

    def zone_floor(self, room, inset=0.4):
        """A department's own finish, inset into the concourse with a trim border:
        a store front on the mall floor rather than a walled room."""
        x, y, w, h = room["rect"]
        lv = int(room.get("level", 0))
        g = self.level_group(lv)
        z = self.base(lv) - 0.025 + 0.012
        x, y, w, h = x + inset, y + inset, w - 2 * inset, h - 2 * inset
        if w < 0.6 or h < 0.6:
            return
        style, a, b = self.s["floors"].get(room["id"], ("checker", "#FFF1D6", "#E6D5B8"))
        self.add(g, box((w + 0.16, h + 0.16, 0.05), g2b(x + w / 2, y + h / 2, z - 0.004), mat(shade(self.s["trim"], 0.8), 0.6)))
        self.pattern(g, style, a, b, x, y, w, h, z + 0.004)

    def pattern(self, g, style, a, b, x, y, w, h, z):
        if style == "checker":
            gx = x
            i = 0
            while gx < x + w - 1e-6:
                cw = min(1.0, x + w - gx)
                gy, j = y, 0
                while gy < y + h - 1e-6:
                    ch = min(1.0, y + h - gy)
                    self.add(g, box((cw, ch, 0.05), g2b(gx + cw / 2, gy + ch / 2, z), mat(a if (i + j) % 2 else b, 0.25),
                                    bev=0.015, seg=1))
                    gy += 1.0
                    j += 1
                gx += 1.0
                i += 1
        elif style == "planks":
            n = max(1, int(round(h / 0.5)))
            ph = h / n
            for i in range(n):
                self.add(g, box((w, ph, 0.05), g2b(x + w / 2, y + i * ph + ph / 2, z), mat(a if i % 2 else b, 0.3), bev=0.012, seg=1))
        else:  # carpet with a border
            self.add(g, box((w, h, 0.05), g2b(x + w / 2, y + h / 2, z), mat(b, 0.7)))
            self.add(g, box((max(0.2, w - 0.5), max(0.2, h - 0.5), 0.05), g2b(x + w / 2, y + h / 2, z + 0.01), mat(a, 0.8)))

    def floors(self):
        if OPEN_PLAN:
            self.concourse()
            for room in self.rooms:
                if room.get("dept"):
                    self.zone_floor(room)
        for room in ([] if OPEN_PLAN else self.rooms):
            x, y, w, h = room["rect"]
            lv = int(room.get("level", 0))
            style, a, b = self.s["floors"].get(room["id"], ("checker", "#FFF1D6", "#E6D5B8"))
            self.pattern(self.level_group(lv), style, a, b, x, y, w, h, self.base(lv) - 0.025)
        dress = self.t.get("dressing", {})
        for rug in dress.get("floor", []) + dress.get("carpet", []):
            if "radius" in rug:  # round inlay (orbital rings on the floor)
                (cx, cy), rr = rug["at"], float(rug["radius"])
                lv = self.level_of(cx, cy)
                z0 = self.base(lv)
                col = rug.get("col", "#344D68")
                col = col if col.startswith("#") else "#344D68"
                line = rug.get("line", "#A9CCC7")
                line = line if line.startswith("#") else "#E0B34A"
                self.add(self.level_group(lv), cyl(rr, 0.02, g2b(cx, cy, z0 + 0.01), mat(toyify(col, 1.3, 1.2), 0.6), bev=0, verts=48))
                for k, f in enumerate((0.45, 0.72, 0.95)):
                    self.add(self.level_group(lv), torus(rr * f, 0.035, g2b(cx, cy, z0 + 0.025), mat(line, 0.4)))
                continue
            (x, y), (w, h) = rug["at"], rug["size"]
            lv = self.level_of(x + w / 2, y + h / 2)
            z0 = self.base(lv)
            self.add(self.level_group(lv), box((w, h, 0.02), g2b(x + w / 2, y + h / 2, z0 + 0.01), mat("#C0392B", 0.8)))
            self.add(self.level_group(lv), box((max(0.1, w - 0.3), max(0.1, h - 0.3), 0.02), g2b(x + w / 2, y + h / 2, z0 + 0.02), mat("#E0B34A", 0.8)))

    def wall_kind(self, seg):
        """Classify a wall against rooms on ITS OWN level: the front edge of an
        upper storey is a low parapet (so the camera sees in), not an inner wall."""
        (x, y), L = seg["at"], seg["len"]
        lv = int(seg.get("level", 0)) if self.levels != [0] else None
        if seg["axis"] == "x":
            mx = x + L / 2
            if not self.inside(mx, y + 0.3, lv):
                return "front", (0, 1)
            if not self.inside(mx, y - 0.3, lv):
                return "back", (0, -1)
        else:
            my = y + L / 2
            if not self.inside(x + 0.3, my, lv) or not self.inside(x - 0.3, my, lv):
                return "side", (1, 0) if not self.inside(x + 0.3, my, lv) else (-1, 0)
        return "inner", (0, 0)

    def walls(self):
        ext, trim = self.s["exterior"], self.s["trim"]
        self.open_segs = []
        for seg in self.t.get("walls", []):
            (x, y), L = seg["at"], seg["len"]
            lv = int(seg.get("level", 0))
            g = self.level_group(lv)
            z0 = self.base(lv)
            kind, out = self.wall_kind(seg)
            if OPEN_PLAN and kind == "inner":
                self.open_segs.append(seg)
                continue
            if OPEN_PLAN and kind == "front":
                self.glass_rail(g, seg["axis"] == "x", x, y, L, z0)
                continue
            h = {"back": H_BACK, "side": H_SIDE, "inner": H_INNER, "front": H_FRONT}[kind]
            col = self.wall_colour(seg.get("col", "@shell"))
            along_x = seg["axis"] == "x"
            cx, cy = (x + L / 2, y) if along_x else (x, y + L / 2)
            size = (L + WALL_T, WALL_T, h) if along_x else (WALL_T, L + WALL_T, h)
            z = z0 + h / 2
            if kind == "inner" or kind == "front":
                self.add(g, box(size, g2b(cx, cy, z), mat(col if kind == "inner" else ext, 0.45), bev=0.04))
            else:  # outer wall: room colour inside, stone outside
                half = WALL_T / 2
                inner = (size[0], half, h) if along_x else (half, size[1], h)
                ox, oy = out
                self.add(g, box(inner, g2b(cx - ox * half / 2, cy - oy * half / 2, z), mat(col, 0.45), bev=0.03))
                self.add(g, box(inner, g2b(cx + ox * half / 2, cy + oy * half / 2, z), mat(ext, 0.5), bev=0.03))
            cap = (size[0] + 0.06, size[1] + 0.06, 0.08)
            self.add(g, box(cap, g2b(cx, cy, z0 + h + 0.02), mat(trim, 0.35), bev=0.03))
            if kind != "front":
                base = (size[0] + 0.03, size[1] + 0.03, 0.12)
                self.add(g, box(base, g2b(cx, cy, z0 + 0.06), mat(shade(col, 0.7), 0.5), bev=0.02))

    def glass_rail(self, g, along_x, x, y, L, z0, height=0.55):
        """Glass balustrade: a stone curb, clear panels between slim posts and a
        handrail, so an open edge reads as a mall's mezzanine lip."""
        trim = self.s["trim"]
        rail = shade(self.s["exterior"], 0.62)
        cx, cy = (x + L / 2, y) if along_x else (x, y + L / 2)
        def span(length, thick, zc, hh, m):
            size = (length, thick, hh) if along_x else (thick, length, hh)
            self.add(g, box(size, g2b(cx, cy, zc), m, bev=0.01))
        span(L + 0.06, WALL_T * 0.9, z0 + 0.04, 0.08, mat(trim, 0.5))
        span(L, 0.03, z0 + 0.08 + (height - 0.12) / 2, height - 0.12, mat(GLASS, 0.1, alpha=0.3))
        span(L + 0.04, 0.07, z0 + height, 0.05, mat(rail, 0.5))
        n = max(1, int(round(L / 1.2)))
        for i in range(n + 1):
            t = x + L * i / n if along_x else y + L * i / n
            px, py = (t, y) if along_x else (x, t)
            self.add(g, box((0.05, 0.05, height), g2b(px, py, z0 + height / 2), mat(rail, 0.5)))

    def colonnade(self):
        """Columns where the partitions ran: at every wall end (flanking what
        were doorways) and every COLUMN_EVERY along it, never against the outer
        shell and never twice in the same place."""
        if not getattr(self, "open_segs", None):
            return
        ext, trim = self.s["exterior"], self.s["trim"]
        shaft = mix(ext, "#FFFFFF", 0.35)
        placed = []
        for seg in self.open_segs:
            (x, y), L = seg["at"], seg["len"]
            lv = int(seg.get("level", 0))
            lvq = lv if self.levels != [0] else None
            along_x = seg["axis"] == "x"
            n = max(1, int(math.ceil(L / COLUMN_EVERY)))
            for i in range(n + 1):
                t = L * i / n
                px, py = (x + t, y) if along_x else (x, y + t)
                if any(not self.inside(px + dx, py + dy, lvq) for dx in (-0.35, 0.35) for dy in (-0.35, 0.35)):
                    continue  # on the outer shell: the wall is the support there
                if any(abs(px - qx) < 1.1 and abs(py - qy) < 1.1 for qx, qy in placed):
                    continue
                if self.blocked(px, py):
                    continue
                placed.append((px, py))
                g = self.level_group(lv)
                z0 = self.base(lv)
                self.add(g, box((0.44, 0.44, 0.16), g2b(px, py, z0 + 0.08), mat(trim, 0.5), bev=0.03))
                self.add(g, cyl(0.16, COLUMN_H - 0.28, g2b(px, py, z0 + 0.16 + (COLUMN_H - 0.28) / 2), mat(shaft, 0.6),
                                r2=0.14, bev=0.0, verts=20))
                self.add(g, box((0.42, 0.42, 0.12), g2b(px, py, z0 + COLUMN_H - 0.06), mat(trim, 0.5), bev=0.03))

    def blocked(self, px, py, pad=0.3):
        """A column would stand in an exhibit, prop or station footprint."""
        for spec in self.t.get("props", []) + self.t.get("exhibits", []):
            at = spec.get("at")
            if not at or spec.get("layer") == "wall":
                continue
            if "size" in spec:
                sx, sy = spec["size"]
            elif "len" in spec:
                L = float(spec["len"])
                sx, sy = (L, 0.3) if spec.get("axis", "x") == "x" else (0.3, L)
            else:
                sx, sy = 0.6, 0.6
            p = 0.9 if spec.get("kind") == "vault_door" else pad
            if at[0] - p <= px <= at[0] + sx + p and at[1] - p <= py <= at[1] + sy + p:
                return True
        return False

    def feature_walls(self):
        """A wall-hung exhibit whose wall is gone keeps a freestanding feature
        wall of its own, like a gallery panel standing on the concourse; a vault
        door keeps a portal (two piers and a lintel) to hang in."""
        items = [s for s in self.t.get("exhibits", []) if s.get("layer") == "wall" or s.get("kind") in ("mural", "painting")]
        items += [s for s in self.t.get("props", []) if s.get("kind") == "vault_door"]
        for spec in items:
            ax, ay = spec["at"]
            L = float(spec.get("len", spec.get("size", [2.2, 0.1])[0]))
            along_x = spec.get("axis", "x") == "x"
            seg = self.open_seg_at(ax, ay, along_x)
            if seg is None:
                continue
            lv = int(seg.get("level", 0))
            g = self.level_group(lv)
            z0 = self.base(lv)
            col = mat(self.wall_colour(seg.get("col", "@shell")), 0.6)
            trim = mat(self.s["trim"], 0.5)
            (x, y) = seg["at"]
            def piece(t0, t1, zb, zt, m):
                c = (t0 + t1) / 2
                size = (t1 - t0, WALL_T, zt - zb) if along_x else (WALL_T, t1 - t0, zt - zb)
                loc = g2b(c, y, z0 + (zb + zt) / 2) if along_x else g2b(x, c, z0 + (zb + zt) / 2)
                self.add(g, box(size, loc, m, bev=0.03))
            t0 = ax if along_x else ay
            if spec.get("kind") == "vault_door":
                piece(t0 - 0.6, t0, 0.0, 1.7, col)
                piece(t0 + L, t0 + L + 0.6, 0.0, 1.7, col)
                piece(t0 - 0.63, t0 + L + 0.63, 1.45, 1.78, trim)
            else:
                piece(t0 - 0.25, t0 + L + 0.25, 0.0, 1.7, col)
                piece(t0 - 0.28, t0 + L + 0.28, 1.7, 1.78, trim)

    def open_seg_at(self, px, py, along_x):
        for seg in getattr(self, "open_segs", []):
            if (seg["axis"] == "x") != along_x:
                continue
            (x, y), sl = seg["at"], seg["len"]
            if along_x and abs(py - y) < 0.3 and x - 0.3 <= px <= x + sl + 0.3:
                return seg
            if not along_x and abs(px - x) < 0.3 and y - 0.3 <= py <= y + sl + 0.3:
                return seg
        return None

    def wall_dressing(self):
        for d in self.t.get("dressing", {}).get("wall", []):
            (x, y), L = d["at"], d.get("len", 0.8)
            along_x = d["axis"] == "x"
            col = d.get("col", "#8E6BB0")
            col = self.wall_colour(col) if col.startswith("@") else col
            cx, cy = (x + L / 2, y + WALL_T / 2 + 0.03) if along_x else (x + WALL_T / 2 + 0.03, y + L / 2)
            size = (L, 0.05, 0.6) if along_x else (0.05, L, 0.6)
            frame = (L + 0.1, 0.04, 0.7) if along_x else (0.04, L + 0.1, 0.7)
            lv = int(d.get("level", self.level_of(cx, cy + 0.3)))
            z0 = self.base(lv)
            self.add(self.level_group(lv), box(frame, g2b(cx, cy, z0 + 1.2), mat("#C99A3A", 0.3, metal=0.3), bev=0.02))
            self.add(self.level_group(lv), box(size, g2b(cx + (0 if along_x else 0.02), cy + (0.02 if along_x else 0), z0 + 1.2),
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
        if max(self.levels) > 0:
            top = max(self.levels)
            rs = [r["rect"] for r in self.rooms if int(r.get("level", 0)) == top]
            x0 = min(r[0] for r in rs)
            y0 = min(r[1] for r in rs)
            x1 = max(r[0] + r[2] for r in rs)
            y1 = max(r[1] + r[3] for r in rs)
            self.upper_crown([x0, y0, x1 - x0, y1 - y0], self.base(top), None)
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
    def upper_crown(self, rect=None, base=None, dome=None):
        """Pediment, name, flags and the domed pavilion on the top floor."""
        ext, trim, acc = self.s["exterior"], self.s["trim"], self.s["accent"]
        if rect is None:
            L = self.wings[-1]["layout"]
            rect, base, dome = L["rect"], L["y"], L.get("dome")
        x, y, wd, h = rect
        cx = x + wd / 2
        top = base + H_BACK
        self.add("crown", box((wd + 0.5, 0.5, 0.2), g2b(cx, y - 0.1, top + 0.1), mat(trim, 0.35), bev=0.05))
        self.add("crown", box((min(6.0, wd - 1.0), 0.4, 0.9), g2b(cx, y - 0.1, top + 0.65), mat(ext, 0.5), bev=0.05))
        self.add("crown", toy.prism(min(6.6, wd - 0.4), 0.8, 1.2, g2b(cx, y - 0.1, top + 1.1), mat(acc, 0.3), bev=0.06))
        for fx in (x + 0.3, x + wd - 0.3):
            self.add("crown", [cyl(0.05, 1.8, g2b(fx, y - 0.2, top + 0.9), mat("#2E3A4A", 0.35)),
                               box((0.6, 0.04, 0.35), g2b(fx + 0.32, y - 0.2, top + 1.6), mat(acc, 0.4), bev=0.02)])
        dx, dy = dome if dome else [cx, y - 1.3]
        db = base if dome else top + 0.3  # no pavilion floor: the dome sits on the back wall
        drum_h = 2.1
        self.add("crown", [cyl(1.25, drum_h, g2b(dx, dy, db + drum_h / 2), mat(ext, 0.5), bev=0.04),
                           torus(1.26, 0.08, g2b(dx, dy, db + drum_h), mat(trim, 0.35)),
                           cyl(0.08, 0.9, g2b(dx, dy, db + drum_h + 2.0), mat("#2E3A4A", 0.35)),
                           sphere(0.14, g2b(dx, dy, db + drum_h + 1.75), mat("#F2C14E", 0.25, metal=0.5))])
        for i in range(8):  # arched windows round the drum
            a = i / 8 * math.tau
            px, py = dx + math.cos(a) * 1.24, dy + math.sin(a) * 1.24
            self.add("crown", box((0.34, 0.06, 0.8), g2b(px, py, db + 1.1), mat("#9FD3F0", 0.15), bev=0.02,
                                  rot=(0, 0, -a + math.pi / 2)))
        self.add("dome", sphere(1.3, g2b(dx, dy, db + drum_h + 0.35), mat(self.s["dome"], 0.3, name="dome"), scale=(1, 1, 0.9)))
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
        # Authored floors come after the theme's own storeys (WingSystem order),
        # so the first one's lift rises from the top theme storey.
        prev_top = self.base(max(self.levels))
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
        # rugs: [x, y, w, h, colour] with a trim border, the room's hue on the floor
        for rx, ry, rw, rh, rc in L.get("rugs", []):
            self.add(g, box((rw + 0.24, rh + 0.24, 0.02), g2b(rx + rw / 2, ry + rh / 2, top + 0.01), mat(trim, 0.4), bev=0.01, seg=1))
            self.add(g, box((rw, rh, 0.03), g2b(rx + rw / 2, ry + rh / 2, top + 0.02), mat(rc, 0.6), bev=0.01, seg=1))
            self.add(g, box((rw - 0.5, rh - 0.5, 0.032), g2b(rx + rw / 2, ry + rh / 2, top + 0.021), mat(shade(rc, 1.18), 0.6), bev=0.01, seg=1))
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
        L = w["layout"]
        ax, ay = L["lift"]["at"]
        fx, fy, fw, fh = L["rect"]
        self.lift_geo(w["id"], ax, ay, bottom, top, fy + fh)

    def lift_geo(self, wid, ax, ay, bottom, top, front):
        """Glass elevator: brass-framed shaft from `bottom` to above `top`, a
        landing into the floor whose front edge is at grid y `front`, and a
        separate cabin Godot moves."""
        g = "lift_" + wid
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
        cab = toy.join(parts, "cabin_" + wid)
        cab.location = g2b(ax, ay, bottom)
        self.groups["cabin_" + wid] = [cab]

    # ------------------------------------------------------------ theme storeys (levels)
    def podiums(self):
        """Under every upper-storey room, the storeys beneath it as a stone block
        with a cornice at the floor line."""
        ext, trim = self.s["exterior"], self.s["trim"]
        for r in self.rooms:
            lv = int(r.get("level", 0))
            if lv <= 0:
                continue
            x, y, w, h = r["rect"]
            top = self.base(lv) - 0.05
            g = self.level_group(lv)
            self.add(g, box((w, h, top), g2b(x + w / 2, y + h / 2, top / 2), mat(ext, 0.5)))
            self.add(g, box((w + 0.12, h + 0.12, 0.12), g2b(x + w / 2, y + h / 2, top - 0.06), mat(trim, 0.35), bev=0.03))

    def find_lift(self, lv):
        """Where a lift joins storey lv-1 to lv: in a stair room if the theme has
        one, else in the lower room that meets the upper storey's front edge.
        Returns (ax, ay, enter, exit) in grid coordinates, or None."""
        lower = [r for r in self.rooms if int(r.get("level", 0)) == lv - 1]
        upper = [r for r in self.rooms if int(r.get("level", 0)) == lv]
        lower.sort(key=lambda r: (0 if "stair" in r["id"] else 1 if r.get("role") == "link" else 2, -r["rect"][2]))
        for lo in lower:
            lx, ly, lw, lh = lo["rect"]
            for up in upper:
                ux, uy, uw, uh = up["rect"]
                if abs(ly - (uy + uh)) > 0.05:
                    continue
                o0, o1 = max(lx, ux), min(lx + lw, ux + uw)
                if o1 - o0 < 1.3 or lh < 1.4 or uh < 1.3:
                    continue
                ax = (o0 + o1) / 2
                ay = ly + 0.55
                return ax, ay, (ax, ly + min(1.35, lh - 0.2)), (ax, ly - min(0.9, uh - 0.3))
        return None

    def level_lifts(self):
        for lv in self.levels:
            if lv <= 0:
                continue
            rs = [r for r in self.rooms if int(r.get("level", 0)) == lv]
            x0 = min(r["rect"][0] for r in rs)
            y0 = min(r["rect"][1] for r in rs)
            x1 = max(r["rect"][0] + r["rect"][2] for r in rs)
            y1 = max(r["rect"][1] + r["rect"][3] for r in rs)
            depts = [r.get("dept") for r in sorted(rs, key=lambda r: -r["rect"][2] * r["rect"][3]) if r.get("dept")]
            meta = {"rect": [x0, y0, x1 - x0, y1 - y0], "y": self.base(lv), "dept": depts[0] if depts else "gallery"}
            spot = self.find_lift(lv)
            if spot:
                ax, ay, enter, exit_ = spot
                self.lift_geo("floor_%d" % lv, ax, ay, self.base(lv - 1), self.base(lv), ay - 0.55)
                meta.update({"lift_at": [ax, ay], "enter": list(enter), "exit": list(exit_)})
            self.floor_meta[self.level_group(lv)] = meta

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
        self.colonnade()
        self.feature_walls()
        self.wall_dressing()
        self.upper_floors()
        self.podiums()
        self.level_lifts()
        self.crown()
        self.outdoors(road_y)
        self.grandeur(road_y)
        out = {}
        for g, objs in self.groups.items():
            if objs:
                out[g] = toy.join(objs, g)
        for g, meta in self.floor_meta.items():
            if g in out:
                for k, v in meta.items():
                    out[g][k] = v  # glTF extras -> Godot node metadata "extras"
        if "grounds" in out and getattr(self, "scatter", None):
            for k, v in self.scatter.items():
                out["grounds"][k] = v
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
