#!/usr/bin/env python3
"""Author venue theme blocks into data/venues.json.

Each venue is declared as a PLAN (room rects + roles) plus a VOCABULARY (palette,
exhibit list, prop kinds). Walls, wall art, fixture waypoints and the prop
scatter are DERIVED by venue_kit and validated before anything is written — see
that module for why hand-authoring them kept producing invisible mistakes.

The plans deliberately do NOT tile a rectangle. The visible floor is a diamond,
so a room's west vertex sits at (gx - gy - h): a box that starts at gx=0 and runs
to gy=17 throws its whole bottom-left corner off the canvas. Following the
diamond instead of fighting it is what makes these venues read as different
BUILDINGS rather than the same box with new paint.

Usage:  python3 tools/author_venue.py --check    # validate, write nothing
        python3 tools/author_venue.py            # validate + write
"""

import collections
import json
import random
import sys

import venue_kit as VK

VENUES = f"{VK.__file__.rsplit('/', 2)[0]}/data/venues.json"


def OD(pairs):
    return collections.OrderedDict(pairs)


# --- role fixture blocks, derived from the room's own rect --------------------
#
# Every waypoint inside a room def is RELATIVE to that room's rect, so deriving
# them from the rect is what guarantees a counter cannot end up in the corridor
# when a plan moves.

def queue_block(rect):
    w, h = rect[2], rect[3]
    windows = max(3, min(5, int((w - 1.6) // 1.7)))
    step = round((w - 2.6) / max(1, windows - 1), 2)
    return OD([
        ("windows", windows), ("first_gx", 1.3), ("gx_step", step),
        ("counter_gy", round(h * 0.24, 2)), ("slots", 6), ("slot_lead", 1.0),
        ("slot_gap", 0.55), ("lane_offset", 0.62),
        ("counter_size", [1.7, 0.6]), ("counter_h", 21.0),
    ])


def store_block(rect):
    w, h = rect[2], rect[3]
    return OD([
        ("home", [1.4, round(h - 0.6, 2)]), ("home_step", 0.7),
        ("drop", [round(w - 1.8, 2), round(h - 0.8, 2)]),
        ("pile", [round(w - 1.3, 2), round(h - 0.7, 2)]),
    ])


def lobby_block(rect, rng):
    w, h = rect[2], rect[3]
    # The door faces the street, which the surround always puts off the venue's
    # SOUTH-EAST corner, so it hangs off the lobby's east end.
    door = [round(w - 2.1, 2), round(h - 0.7, 2)]
    linger = []
    for i in range(9):
        linger.append([round(door[0] - 5.0 + rng.uniform(0.0, 4.6), 2),
                       round(0.7 + rng.uniform(0.0, max(0.6, h - 1.6)), 2)])
    return OD([
        ("door", door),
        ("marketer", [round(w - 3.7, 2), round(h - 0.8, 2)]),
        ("linger", linger),
        ("crowd", OD([("origin", [round(w - 6.8, 2), round(h - 1.9, 2)]),
                      ("cols", 5), ("col_step", 0.95), ("row_step", 0.8),
                      ("row_shear", 0.5)])),
    ])


def stations(rect, n=2):
    w, h = rect[2], rect[3]
    if n == 1:
        return [[round(w * 0.5, 2), round(h * 0.5, 2)]]
    return [[round(w * 0.16, 2), round(h * 0.45, 2)],
            [round(w * 0.78, 2), round(h * 0.55, 2)]]


# --- exhibit builders ---------------------------------------------------------
#
# Field names per kind are the ones exhibits.gd actually reads; a typo here draws
# a default-looking object rather than erroring, which is why they live in one
# place instead of being retyped per venue.

def views(n=4, rng=None):
    rng = rng or random
    out = []
    for i in range(n):
        a = (i / max(1, n)) * 6.28318
        out.append([round(-1.6 + 3.2 * ((i * 0.37) % 1.0), 2),
                    round(0.3 + 0.9 * ((i * 0.61) % 1.0), 2)])
    return out


def barrier(ax, ay, span, pal="@rope"):
    return OD([("from", [round(ax, 2), round(ay, 2)]),
               ("to", [round(ax + span, 2), round(ay, 2)]),
               ("posts", max(3, int(span) + 1)), ("rope", pal),
               ("post", "@shell"), ("knob", "@trim")])


def exhibit(kind, eid, at, size, cols, rng, roped=True):
    ax, ay = at
    w, h = size
    anchor = [round(ax + w * 0.5, 2), round(ay + h * 0.5, 2)]
    e = OD([("id", eid), ("kind", kind), ("anchor", anchor),
            ("at", [round(ax, 2), round(ay, 2)]),
            ("size", [round(w, 2), round(h, 2)])])
    if kind == "skeleton":
        e.update(OD([("plinth_h", 14.0), ("plinth", "@stone"), ("lip", cols["lip"]),
                     ("bone", cols["light"]), ("edge", cols["dark"])]))
    elif kind == "casket":
        e.update(OD([("plinth_h", 12.0), ("plinth", "@stone"), ("body", cols["body"]),
                     ("trim", cols["accent"]), ("edge", cols["dark"])]))
    elif kind == "statue":
        e.update(OD([("plinth_h", 15.0), ("plinth", "@stone"),
                     ("stone", cols["light"]), ("edge", cols["dark"])]))
    elif kind == "vitrine":
        e.update(OD([("plinth_h", 11.0), ("glass_h", 30.0), ("base", "@stone"),
                     ("art", cols["accent"])]))
    elif kind == "case":
        e.update(OD([("plinth_h", 10.0), ("base", "@stone"),
                     ("specimens", cols["specimens"])]))
    elif kind == "tank":
        e.update(OD([("plinth_h", 9.0), ("height", 40.0), ("frame", cols["dark"]),
                     ("water", cols["water"]), ("weed", cols["weed"]),
                     ("fauna", cols["fauna"]), ("fauna_count", 5)]))
    elif kind == "touch_pool":
        e.update(OD([("rim", "@stone"), ("rim_h", 9.0), ("water", cols["water"]),
                     ("sand", cols["lip"]), ("life", cols["fauna"]), ("life_count", 5)]))
    elif kind == "plinth":
        e.update(OD([("height", 16.0), ("col", "@stone"), ("lip", cols["lip"])]))
    if roped and kind not in ("hanging", "hung_skeleton", "mural"):
        e["barrier"] = barrier(ax - 0.2, ay + h + 0.5, w + 0.4)
    e["views"] = views(4, rng)
    return e


def hanging(eid, anchor, span_px, cols, ceiling=52.0):
    """A piece suspended over a tile.

    Two traps in this kind's spec, both of which draw something rather than
    erroring loudly: `wings` is a BOOLEAN flag (whether to draw the spread), not
    a colour, and `span`/`drop`/`ceiling` are in PIXELS while every other kind's
    `size` is in tiles. A tile-valued span makes the piece a few pixels wide.
    """
    at = [round(anchor[0], 2), round(anchor[1], 2)]
    return OD([("id", eid), ("kind", "hanging"), ("anchor", at), ("at", at),
               ("span", span_px), ("ceiling", ceiling), ("drop", 16.0),
               ("wings", True),
               ("body", cols["body"]), ("edge", cols["dark"]), ("wire", "#5A5A6E"),
               ("views", [[-1.4, 1.0], [0.4, 1.2], [1.6, 0.8]])])


def mural(eid, at, length, cols):
    return OD([("id", eid), ("kind", "mural"), ("layer", "wall"),
               ("anchor", [round(at[0] + length * 0.5, 2), round(at[1], 2)]),
               ("at", [round(at[0], 2), round(at[1], 2)]),
               ("len", length), ("axis", "x"), ("y0", 16.0), ("y1", 44.0),
               ("frame", "@trim|d28"), ("sky", cols["sky"]), ("land", cols["land"]),
               ("horizon", 27.0), ("motif", cols["motif"]),
               ("motif_at", [round(length * 0.6, 2), 0.0]), ("motif_dy", 35.0),
               ("motif_r", 5.0),
               ("views", [[-2.2, 0.9], [0.0, 0.9], [2.2, 1.0]])])


# --- theme assembly -----------------------------------------------------------

def build(spec):
    rng = random.Random(spec["seed"])
    rooms = []
    for r in spec["plan"]:
        rect = r["rect"]
        room = OD([("id", r["id"])])
        if r.get("dept"):
            room["dept"] = r["dept"]
        if r.get("name"):
            room["name"] = r["name"]
        room["role"] = r["role"]
        room["rect"] = rect
        room["floor_mix"] = r.get("floor_mix", 0.42)
        # Storey. Emitted only when the venue actually uses one, so a flat
        # venue's JSON is unchanged and diffs stay readable.
        if r.get("level"):
            room["level"] = int(r["level"])
        if r.get("rise_to") is not None and r.get("rise_to") != r.get("level", 0):
            room["rise_to"] = int(r["rise_to"])
        if r["role"] == "link":
            room["merge_into"] = r["merge_into"]
            rooms.append(room)
            continue
        if r["role"] != "lobby":
            room["plaque"] = VK.plaque_at(r["role"], rect)
        if r["role"] == "queue":
            room["queue"] = queue_block(rect)
        elif r["role"] == "store":
            room["store"] = store_block(rect)
        elif r["role"] == "lobby":
            room.update(lobby_block(rect, rng))
        else:
            room["stations"] = stations(rect)
        rooms.append(room)

    def colour_of(room):
        dept = room.get("dept")
        return f"@room.{dept}" if dept else "@shell"

    walls = VK.derive_walls(rooms, colour_of)

    exhibits = list(spec.get("exhibits", []))
    props = list(spec.get("props", []))

    # Keep the scatter off anything already placed by hand.
    blocked = [(e["anchor"][0], e["anchor"][1]) for e in exhibits if "anchor" in e]
    blocked += [(p["at"][0], p["at"][1]) for p in props]
    scatter_rooms = [r for r in rooms if r.get("role") != "lobby"]
    props += VK.scatter_weighted(scatter_rooms, rng, spec["prop_vocab"], blocked,
                                 spec.get("prop_density", 0.17))
    # And the forecourt. A plan that follows the diamond leaves paved notches
    # beside the building; bare, they read as a car park.
    props += VK.terrace_props(rooms, rng, spec.get("terrace_vocab",
                              ["bench", "planter", "plinth"]),
                              spec.get("terrace_count", 9))

    art_keys = spec["art_cols"]
    dressing = OD([
        ("carpet", spec.get("carpet", [])),
        ("floor", spec.get("floor_dressing", [])),
        ("wall", VK.derive_wall_art(rooms, rng, art_keys, 0.72)),
        ("ceiling", spec.get("ceiling", [])),
    ])

    theme = OD([
        ("surround", spec["surround"]),
        ("palette", spec["palette"]),
        ("rooms", rooms),
        ("shell", OD([("inset", 0.35), ("col", "@shell|d15")])),
        ("walls", walls),
        ("exhibits", exhibits),
        ("props", props),
        ("dressing", dressing),
    ])
    return theme


def rugs(rooms_spec, rng, trim="@trim|d20"):
    """A floor rug centred in each named room, sized off its rect."""
    out = []
    for r in rooms_spec:
        rect = r["rect"]
        if rect[2] < 4 or rect[3] < 3 or r["role"] in ("lobby", "link"):
            continue
        out.append(OD([
            ("kind", "rug"),
            ("at", [round(rect[0] + rect[2] * 0.22, 2),
                    round(rect[1] + rect[3] * 0.25, 2)]),
            ("size", [round(rect[2] * 0.52, 2), round(rect[3] * 0.44, 2)]),
            ("col", f"@roomfloor.{r['id']}|d12"), ("border", trim),
        ]))
    return out


# --- the venues ---------------------------------------------------------------
#
# Each plan hugs the diamond instead of tiling a rectangle, and each has a
# genuinely different SILHOUETTE rather than the same box repainted:
#
#   sunspire   stepped terraces, the mass descending east then south
#   cloudrest  twin wings with a span between them, notched north and south
#   aurora     a cross: central rotunda with four arms off it

SUNSPIRE = {
    "id": "sunspire", "seed": 41, "surround": "dunes",
    "palette": OD([
        ("floor", "#FDF0D5"), ("shell", "#8C5A2B"), ("carpet", "#E8622F"),
        ("rope", "#C2410C"), ("trim", "#FFD166"), ("panel", "#FFFBF0"),
        ("panel_soft", "#FFF0DC"), ("stone", "#E0C79A"),
        ("partition", "#A2653A"),
        ("room.gallery", "#F4A93C"), ("room.archive", "#3FBFB5"),
        ("room.promotions", "#E56BB0"), ("room.ticket", "#6C8CE8"),
    ]),
    "plan": [
        {"id": "gallery", "dept": "gallery", "name": "SUN COURT",
         "role": "exhibit", "rect": [0, 1, 9, 8], "floor_mix": 0.40},
        {"id": "archive", "dept": "archive", "name": "THE TREASURY",
         "role": "store", "rect": [9, 5, 5, 4], "floor_mix": 0.44},
        {"id": "ticket", "dept": "ticket", "name": "TICKET HALL",
         "role": "queue", "rect": [2, 9, 7, 4], "floor_mix": 0.42},
        {"id": "promotions", "dept": "promotions", "name": "PROMOTIONS",
         "role": "promo", "rect": [9, 9, 5, 4], "floor_mix": 0.44},
        {"id": "lobby", "role": "lobby", "rect": [5, 13, 8, 3]},
    ],
    "prop_count": 20,
    "art_cols": ["#C2410C", "#3FBFB5", "#E56BB0", "#6C8CE8", "#F4A93C"],
    "terrace_vocab": ["planter", "planter", "bench"],
    "terrace_count": 10,
}

CLOUDREST = {
    "id": "cloudrest", "seed": 57, "surround": "alpine",
    "palette": OD([
        ("floor", "#EAF2F8"), ("shell", "#3F5468"), ("carpet", "#2E86AB"),
        ("rope", "#1B6B93"), ("trim", "#C9D9E8"), ("panel", "#FFFFFF"),
        ("panel_soft", "#E4EDF5"), ("stone", "#A9BACB"),
        ("partition", "#6E8296"),
        ("room.gallery", "#A9C9DE"), ("room.archive", "#7FCB8C"),
        ("room.promotions", "#C58CF0"), ("room.ticket", "#F2A65A"),
    ]),
    "plan": [
        {"id": "gallery", "dept": "gallery", "name": "THE AVIARY",
         "role": "exhibit", "rect": [0, 2, 6, 8], "floor_mix": 0.40},
        {"id": "span", "role": "link", "rect": [6, 5, 3, 3], "merge_into": "gallery",
         "level": 0, "rise_to": 1},
        {"id": "archive", "dept": "archive", "name": "THE EYRIE",
         "role": "store", "rect": [9, 4, 5, 5], "floor_mix": 0.44, "level": 1},
        {"id": "promotions", "dept": "promotions", "name": "PATRONAGE",
         "role": "promo", "rect": [9, 9, 5, 4], "floor_mix": 0.44, "level": 1},
        {"id": "ticket", "dept": "ticket", "name": "GATEHOUSE",
         "role": "queue", "rect": [2, 10, 7, 4], "floor_mix": 0.42},
        {"id": "lobby", "role": "lobby", "rect": [5, 14, 8, 3]},
    ],
    "prop_count": 20,
    "art_cols": ["#7A5C3E", "#7FCB8C", "#C58CF0", "#F2A65A", "#59C3E8"],
    "terrace_vocab": ["planter", "planter", "bench"],
    "terrace_count": 10,
}

AURORA = {
    "id": "aurora_world", "seed": 73, "surround": "nightfall",
    "palette": OD([
        ("floor", "#3A3170"), ("shell", "#241C4A"), ("carpet", "#7C4DFF"),
        ("rope", "#B388FF"), ("trim", "#7CF5D4"), ("panel", "#F3F0FF"),
        ("panel_soft", "#E7E1FF"), ("stone", "#6B5FA8"),
        ("partition", "#B9AEEA"),
        ("room.gallery", "#8B6BFF"), ("room.archive", "#22D3EE"),
        ("room.promotions", "#F472B6"), ("room.ticket", "#FBBF24"),
    ]),
    "plan": [
        {"id": "northwing", "role": "link", "rect": [4, 1, 6, 3],
         "merge_into": "gallery"},
        {"id": "gallery", "dept": "gallery", "name": "THE ROTUNDA",
         "role": "exhibit", "rect": [3, 4, 8, 6], "floor_mix": 0.38},
        {"id": "promotions", "dept": "promotions", "name": "PATRONS WING",
         "role": "promo", "rect": [0, 6, 3, 5], "floor_mix": 0.44},
        {"id": "archive", "dept": "archive", "name": "THE VAULT",
         "role": "store", "rect": [11, 5, 4, 5], "floor_mix": 0.44},
        {"id": "ticket", "dept": "ticket", "name": "ADMISSIONS",
         "role": "queue", "rect": [3, 10, 9, 4], "floor_mix": 0.42},
        {"id": "lobby", "role": "lobby", "rect": [6, 14, 8, 3]},
    ],
    "prop_count": 22,
    "art_cols": ["#22D3EE", "#F472B6", "#FBBF24", "#7CF5D4", "#8B6BFF"],
    "terrace_vocab": ["planter", "planter", "bench", "banner"],
    "terrace_count": 11,
}

PROP_VOCAB = {
    "exhibit": ["planter", "planter", "planter", "bench"],
    "store": ["shelf", "crate", "rack", "trolley", "cabinet"],
    "promo": ["desk", "kiosk", "banner", "rack"],
    "queue": ["planter", "bin", "kiosk"],
    "link": ["planter", "bench"],
    "any": ["planter", "bench", "bin"],
}


def sunspire_art(rng):
    cols = {"light": "#F7E6C4", "dark": "#7A5522", "lip": "#C9A96B",
            "body": "#D2A047", "accent": "#3FBFB5",
            "specimens": ["#3FBFB5", "#E56BB0", "#FFD166"]}
    return [
        exhibit("statue", "colossus", (1.6, 2.4), (1.6, 1.2), cols, rng),
        exhibit("vitrine", "sunmask", (5.2, 2.2), (1.4, 1.0), cols, rng),
        exhibit("case", "scarabs", (2.0, 5.2), (2.2, 1.0), cols, rng),
        exhibit("plinth", "obelisk", (6.4, 5.6), (1.0, 1.0), cols, rng),
        mural("frieze", (3.2, 1.0), 2.4,
              {"sky": "#F6D89A", "land": "#C98A3E", "motif": "#FFF3D0"}),
        # Outdoors, on the forecourt: a real museum puts a piece where you meet
        # it before you have paid, and it is what makes the frontage inviting.
        exhibit("statue", "lion", (3.0, 13.6), (1.2, 1.0), cols, rng),
    ]


def cloudrest_art(rng):
    cols = {"light": "#F2F7FB", "dark": "#4A3524", "lip": "#B9C8D6",
            "body": "#7A5C3E", "accent": "#7FCB8C",
            "specimens": ["#59C3E8", "#7FCB8C", "#F2A65A"]}
    return [
        hanging("condor", (2.6, 4.2), 54.0, cols),
        hanging("kestrel", (4.2, 7.4), 40.0, cols),
        exhibit("case", "clutch", (0.9, 5.4), (1.8, 1.0),
                dict(cols, dark="#3A4A5A"), rng),
        exhibit("vitrine", "plumage", (3.4, 8.6), (1.4, 1.0),
                dict(cols, dark="#3A4A5A"), rng),
        mural("summit", (1.2, 2.0), 2.4,
              {"sky": "#BFDCF2", "land": "#7F93A6", "motif": "#FFFFFF"}),
        exhibit("statue", "cairn", (4.0, 14.6), (1.2, 1.0),
                dict(cols, dark="#3A4A5A"), rng),
    ]


def aurora_art(rng):
    cols = {"light": "#E9E4FF", "dark": "#2A2158", "lip": "#8A7BC8",
            "body": "#5B4BA8", "accent": "#7CF5D4",
            "specimens": ["#22D3EE", "#F472B6", "#FBBF24"]}
    return [
        exhibit("plinth", "orrery", (6.2, 6.2), (1.4, 1.4), cols, rng),
        exhibit("vitrine", "meteorite", (4.0, 5.2), (1.4, 1.0), cols, rng),
        exhibit("statue", "voyager", (8.6, 5.4), (1.4, 1.2), cols, rng),
        exhibit("case", "moonrock", (4.2, 8.4), (2.0, 1.0), cols, rng),
        hanging("armillary", (7.4, 8.6), 58.0, cols, ceiling=58.0),
        mural("nebula", (4.6, 4.0), 2.6,
              {"sky": "#2B2160", "land": "#4A3E96", "motif": "#7CF5D4"}),
        exhibit("statue", "monolith", (4.4, 14.6), (1.2, 1.0), cols, rng),
    ]


def finish(spec, art_fn, carpet_at, bunting):
    rng = random.Random(spec["seed"] + 7)
    spec = dict(spec)
    spec["prop_vocab"] = PROP_VOCAB
    spec["exhibits"] = art_fn(rng)
    spec["floor_dressing"] = rugs(spec["plan"], rng)
    spec["carpet"] = [OD([("kind", "patch"), ("at", carpet_at[0]),
                          ("size", carpet_at[1]), ("col", "@carpet")])]
    spec["ceiling"] = bunting
    return spec


def bunt(frm, to, cols):
    return OD([("kind", "bunting"), ("from", frm), ("to", to),
               ("height", 46.0), ("sag", 9.0), ("flags", 5), ("cols", cols)])


SPECS = [
    finish(SUNSPIRE, sunspire_art, ([8.6, 13.0], [1.6, 3.0]), [
        bunt([2.4, 9.2], [5.0, 9.2], ["@room.ticket", "@trim", "#E8622F", "#3FBFB5", "#F4A93C"]),
        bunt([5.4, 9.2], [8.4, 9.2], ["@trim", "#E56BB0", "@room.gallery", "#6C8CE8", "#E8622F"]),
    ]),
    finish(CLOUDREST, cloudrest_art, ([8.6, 14.0], [1.6, 3.0]), [
        bunt([2.4, 10.2], [5.2, 10.2], ["@room.ticket", "@trim", "#59C3E8", "#7FCB8C", "#C58CF0"]),
        bunt([5.6, 10.2], [8.6, 10.2], ["#F2A65A", "@trim", "#59C3E8", "#FFFFFF", "#7FCB8C"]),
    ]),
    finish(AURORA, aurora_art, ([9.6, 14.0], [1.6, 3.0]), [
        bunt([3.4, 10.2], [6.6, 10.2], ["@trim", "#22D3EE", "#F472B6", "#FBBF24", "#8B6BFF"]),
        bunt([7.0, 10.2], [11.4, 10.2], ["#22D3EE", "@trim", "#FBBF24", "#F472B6", "#7CF5D4"]),
    ]),
]


def main():
    check_only = "--check" in sys.argv
    with open(VENUES) as f:
        doc = json.load(f, object_pairs_hook=collections.OrderedDict)
    by_id = {v["id"]: v for v in doc["venues"]}

    warnings = []
    for spec in SPECS:
        theme = build(spec)
        warns, _ = VK.validate(spec["id"], theme)
        warnings += warns
        b = VK.bounds(theme["rooms"])
        clipped = sum(VK.clip_fraction(r["rect"]) * r["rect"][2] * r["rect"][3]
                      for r in theme["rooms"])
        area = sum(r["rect"][2] * r["rect"][3] for r in theme["rooms"])
        print(f"{spec['id']:<14} rooms={len(theme['rooms'])} "
              f"walls={len(theme['walls'])} exh={len(theme['exhibits'])} "
              f"props={len(theme['props'])} "
              f"dress={sum(len(v) for v in theme['dressing'].values())} "
              f"bounds={tuple(b)} clip={clipped / area:.1%} "
              f"surround={theme['surround']}")
        if spec["id"] not in by_id:
            raise SystemExit(f"venue id '{spec['id']}' not in venues.json")
        by_id[spec["id"]]["theme"] = theme

    for w in warnings:
        print("  warn:", w)

    if check_only:
        print("\n--check: nothing written")
        return 0
    with open(VENUES, "w") as f:
        json.dump(doc, f, indent=2)
    print(f"\nwrote {VENUES}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
