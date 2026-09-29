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
import os
import random
import sys

import venue_kit as VK

REPO = os.environ.get(
    "GRAND_EXHIBIT_REPO",
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
VENUES = os.path.join(REPO, "data", "venues.json")
MILESTONES = os.path.join(REPO, "data", "quests_milestones.json")


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
    slots = 6
    counter_gy = round(h * 0.35, 2)
    slot_lead = 1.0
    # Fit the complete queue into this venue's authored room. A fixed 0.55 gap
    # happened to fit the original five-tile hall and spilled out of every
    # later four-tile hall, making different plans visually dishonest.
    slot_gap = round((h - counter_gy - slot_lead - 0.22) / (slots - 1), 2)
    return OD([
        ("windows", windows), ("first_gx", 1.3), ("gx_step", step),
        ("counter_gy", counter_gy),
        ("porter_lane_gy", round(max(0.18, counter_gy - 1.18), 2)),
        ("slots", slots), ("slot_lead", slot_lead),
        ("slot_gap", slot_gap), ("lane_offset", 0.62),
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
        e.update(OD([("height", 16.0), ("col", "#9A7245"), ("lip", cols["lip"])]))
    elif kind == "orrery":
        e.update(OD([("plinth_h", 14.0), ("base", "@stone"),
                     ("metal", cols["dark"]), ("orbit", cols["light"]),
                     ("sun", cols["accent"])]))
    elif kind == "armor":
        e.update(OD([("plinth_h", 15.0), ("base", "@stone"),
                     ("metal", cols["light"]), ("cloth", cols["body"]),
                     ("trim", cols["accent"])]))
    elif kind == "coral":
        e.update(OD([("rim_h", 11.0), ("rim", "@stone"),
                     ("water", cols["water"]), ("branches", cols["fauna"])]))
    elif kind == "clockwork":
        e.update(OD([("plinth_h", 12.0), ("base", "@stone"),
                     ("body", cols["body"]), ("metal", cols["accent"]),
                     ("face", cols["light"])]))
    elif kind == "throne":
        e.update(OD([("plinth_h", 14.0), ("base", "@stone"),
                     ("body", cols["body"]), ("cushion", cols["dark"]),
                     ("trim", cols["accent"])]))
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


def suspended_skeleton(eid, anchor, cols, span=56.0, ceiling=58.0):
    """A ceiling-mounted marine/flying skeleton with real browse points."""
    at = [round(anchor[0], 2), round(anchor[1], 2)]
    return OD([("id", eid), ("kind", "hung_skeleton"), ("anchor", at), ("at", at),
               ("span", span), ("ceiling", ceiling), ("drop", 16.0),
               ("arch", 9.0), ("ribs", 7), ("rib_len", 15.0),
               ("bone", cols["light"]), ("edge", cols["dark"]),
               ("wire", "#5A5A6E"),
               ("views", [[-1.6, 1.0], [0.0, 1.2], [1.6, 0.9]])])


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
    stairs_to_orient = []
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
        if r.get("prop_density") is not None:
            room["prop_density"] = r["prop_density"]
        # Storey. Emitted only when the venue actually uses one, so a flat
        # venue's JSON is unchanged and diffs stay readable.
        if r.get("level"):
            room["level"] = int(r["level"])
        if r.get("rise_to") is not None and r.get("rise_to") != r.get("level", 0):
            room["rise_to"] = int(r["rise_to"])
            if r.get("stair_axis") in ("x", "y"):
                room["stair_axis"] = r["stair_axis"]
            if r.get("rise_reverse"):
                room["rise_reverse"] = True
            stairs_to_orient.append(room)
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

    # Which way each flight climbs, now that every room is known. Authored values
    # win; anything the plan cannot answer is left to the renderer's fallback and
    # reported, because a wrong stair axis is invisible until you watch someone
    # gain height sideways.
    for room in stairs_to_orient:
        if "stair_axis" in room:
            continue
        facing = VK.stair_orientation(rooms, room)
        if facing is None:
            print("  warn: %s: stair '%s' does not run between its two storeys on "
                  "one axis — using the renderer fallback"
                  % (spec["id"], room["id"]))
            continue
        room["stair_axis"] = facing[0]
        if facing[1]:
            room["rise_reverse"] = True

    def colour_of(room):
        dept = room.get("dept")
        return f"@room.{dept}" if dept else "@shell"

    walls = VK.derive_walls(rooms, colour_of)

    exhibits = list(spec.get("exhibits", []))
    props = list(spec.get("props", []))
    # Browse offsets are authored around each exhibit, but moving/resizing a
    # gallery can put an otherwise good offset a few centimetres through its
    # new wall. Clamp the resulting world point to the room, then store the
    # corrected offset. This keeps layout iteration safe without hand-retuning
    # dozens of visitor spots every time the architecture changes.
    gallery = next((r for r in rooms if r.get("role") == "exhibit"), None)
    if gallery:
        gx, gy, gw, gh = gallery["rect"]
        inset = 0.25
        for piece in exhibits:
            if not piece.get("views"):
                continue
            anchor = piece.get("anchor", piece.get("at"))
            if not anchor:
                continue
            fixed = []
            for ox, oy in piece["views"]:
                wx = min(max(anchor[0] + ox, gx + inset), gx + gw - inset)
                wy = min(max(anchor[1] + oy, gy + inset), gy + gh - inset)
                fixed.append([round(wx - anchor[0], 2), round(wy - anchor[1], 2)])
            piece["views"] = fixed

    # Keep the scatter off anything already placed by hand.
    blocked = [(e["anchor"][0], e["anchor"][1]) for e in exhibits if "anchor" in e]
    blocked += [(p["at"][0], p["at"][1]) for p in props]
    # Never scatter furniture onto a STAIRCASE. A room with rise_to != level is a
    # flight of steps, and the scatter had been dressing them like floors — a row
    # of benches straight down the grand ascent, reading as a wall across the
    # middle of the building. Applies to every venue that has a storey.
    scatter_rooms = [r for r in rooms
                     if r.get("role") != "lobby"
                     and int(r.get("rise_to", r.get("level", 0)))
                     == int(r.get("level", 0))]
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
        *([("layout_spread", spec["layout_spread"])] if "layout_spread" in spec else []),
        *([("camera_zoom", spec["camera_zoom"])] if "camera_zoom" in spec else []),
        *([("camera_offset", spec["camera_offset"])] if "camera_offset" in spec else []),
        *([("decor_anchors", spec["decor_anchors"])] if "decor_anchors" in spec else []),
        ("surround", spec["surround"]),
        ("palette", spec["palette"]),
        ("rooms", rooms),
        # The plinth. `inset` is how far the paved slab stands proud of each room,
        # so it is also the width of the OUTDOOR TERRACE around the building. At
        # 0.35 there was barely a kerb: the walls met the city ground directly, and
        # the space beside the museum read as bare lot. A wider apron gives the
        # outdoor seating somewhere to be and takes pressure off the indoor lounges.
        ("shell", OD([("inset", spec.get("shell_inset", 0.35)),
                      ("col", "@shell|d15")])),
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


def outdoor_exhibit(kind, eid, at, size, cols, rng):
    """A frontage landmark, not a browse destination.

    Normal exhibits get visitor view spots. A forecourt sculpture must not, or
    the gallery FSM sends patrons through walls and out of the paid building.
    """
    out = exhibit(kind, eid, at, size, cols, rng, roped=False)
    out.pop("views", None)
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
        # A ziggurat, not another four-room slab. Admissions occupies the broad
        # ground terrace; the treasury and patrons climb to the middle terrace;
        # the collection is the small crown. Link rooms are the visible stairs
        # between them, and `rise_to` makes the renderer draw those stairs.
        {"id": "gallery", "dept": "gallery", "name": "SUN COURT",
         "role": "exhibit", "rect": [4, 1, 7, 6], "floor_mix": 0.38, "level": 2},
        {"id": "sun_stair", "role": "link", "rect": [5, 7, 5, 2],
         "merge_into": "gallery", "level": 1, "rise_to": 2},
        {"id": "archive", "dept": "archive", "name": "THE TREASURY",
         "role": "store", "rect": [0, 7, 5, 5], "floor_mix": 0.44, "level": 1},
        {"id": "promotions", "dept": "promotions", "name": "PATRONS TERRACE",
         "role": "promo", "rect": [10, 7, 5, 5], "floor_mix": 0.44, "level": 1},
        {"id": "processional", "role": "link", "rect": [5, 9, 5, 3],
         "merge_into": "ticket", "level": 0, "rise_to": 1},
        {"id": "ticket", "dept": "ticket", "name": "LOWER GATE",
         "role": "queue", "rect": [2, 12, 11, 4], "floor_mix": 0.42},
        {"id": "lobby", "role": "lobby", "rect": [5, 16, 8, 3]},
    ],
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
        # Two cliff-top wings joined by a bridge. The public collection is in
        # the west tower, operations in the east tower, while admissions stays
        # down in the gatehouse. The open notch between them is intentional.
        {"id": "gallery", "dept": "gallery", "name": "THE AVIARY",
         "role": "exhibit", "rect": [-1, 1, 6, 9], "floor_mix": 0.40, "level": 1},
        {"id": "span", "role": "link", "rect": [5, 4, 5, 2], "merge_into": "gallery",
         "level": 1},
        {"id": "archive", "dept": "archive", "name": "THE EYRIE",
         "role": "store", "rect": [10, 1, 5, 6], "floor_mix": 0.44, "level": 1},
        {"id": "promotions", "dept": "promotions", "name": "PATRONAGE",
         "role": "promo", "rect": [10, 7, 5, 4], "floor_mix": 0.44, "level": 1},
        {"id": "switchback", "role": "link", "rect": [5, 8, 5, 3],
         "merge_into": "ticket", "level": 0, "rise_to": 1,
         # Enter from admissions on the south, climb north, then turn onto
         # either raised wing. The turn is on the top landing, not in the ramp.
         "stair_axis": "y", "rise_reverse": True},
        {"id": "ticket", "dept": "ticket", "name": "GATEHOUSE",
         "role": "queue", "rect": [3, 11, 9, 4], "floor_mix": 0.42},
        {"id": "lobby", "role": "lobby", "rect": [6, 15, 7, 3]},
    ],
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
        # A raised central rotunda with four low arms. Unlike the linear venues,
        # visitors enter one side of a hub and the departments radiate from it.
        {"id": "northwing", "role": "link", "rect": [5, 0, 5, 4],
         "merge_into": "gallery", "level": 0, "rise_to": 1,
         "stair_axis": "y"},
        {"id": "gallery", "dept": "gallery", "name": "THE ROTUNDA",
         "role": "exhibit", "rect": [4, 4, 7, 7], "floor_mix": 0.36, "level": 1},
        {"id": "promotions", "dept": "promotions", "name": "PATRONS WING",
         "role": "promo", "rect": [-1, 5, 5, 5], "floor_mix": 0.44},
        {"id": "archive", "dept": "archive", "name": "THE VAULT",
         "role": "store", "rect": [11, 5, 5, 5], "floor_mix": 0.44},
        {"id": "south_stair", "role": "link", "rect": [6, 11, 4, 2],
         "merge_into": "ticket", "level": 0, "rise_to": 1},
        {"id": "ticket", "dept": "ticket", "name": "ADMISSIONS",
         "role": "queue", "rect": [3, 13, 10, 4], "floor_mix": 0.42},
        {"id": "lobby", "role": "lobby", "rect": [6, 17, 7, 3]},
    ],
    "art_cols": ["#22D3EE", "#F472B6", "#FBBF24", "#7CF5D4", "#8B6BFF"],
    "terrace_vocab": ["planter", "planter", "bench", "banner"],
    "terrace_count": 11,
}

# --- second collection: levels 7–12 -----------------------------------------
#
# These are not repaint jobs. Their plans deliberately change circulation and
# massing while layout_spread grows the physical grid and camera_zoom frames it.
# The product stays portrait-readable, but every successive venue has more real
# walking area and a more ambitious silhouette than the one before it.

CELESTIAL = {
    "id": "celestial_conservatory", "seed": 89, "surround": "nightfall",
    "layout_spread": 1.24, "camera_zoom": 0.76,
    "palette": OD([
        ("floor", "#E8F7F4"), ("shell", "#173F4C"), ("carpet", "#36D6C4"),
        ("rope", "#1E9E93"), ("trim", "#F7D774"), ("panel", "#F8FFFE"),
        ("panel_soft", "#DDF5F2"), ("stone", "#83AAA9"), ("partition", "#4D7B7D"),
        ("room.gallery", "#55D6BE"), ("room.archive", "#4676C9"),
        ("room.promotions", "#E688B8"), ("room.ticket", "#E7A94B"),
    ]),
    "plan": [
        {"id": "gallery", "dept": "gallery", "name": "ORBITAL GLASSHOUSE",
         "role": "exhibit", "rect": [3, 0, 9, 7], "floor_mix": 0.35, "level": 1},
        {"id": "west_arc", "role": "link", "rect": [0, 4, 3, 4],
         "merge_into": "gallery", "level": 0, "rise_to": 1,
         # Moonlit Salon is south; the high landing turns east into the gallery.
         "stair_axis": "y", "rise_reverse": True},
        {"id": "archive", "dept": "archive", "name": "STAR VAULT",
         "role": "store", "rect": [12, 3, 4, 6], "floor_mix": 0.42, "level": 1},
        {"id": "promotions", "dept": "promotions", "name": "MOONLIT SALON",
         "role": "promo", "rect": [0, 8, 6, 5], "floor_mix": 0.40},
        {"id": "east_arc", "role": "link", "rect": [6, 7, 6, 3],
         "merge_into": "gallery", "level": 0, "rise_to": 1},
        {"id": "ticket", "dept": "ticket", "name": "CONSTELLATION GATE",
         "role": "queue", "rect": [6, 10, 9, 5], "floor_mix": 0.40},
        {"id": "lobby", "role": "lobby", "rect": [8, 15, 7, 4]},
    ],
    "terrace_count": 12,
    "art_cols": ["#55D6BE", "#4676C9", "#E688B8", "#E7A94B", "#F7D774"],
    "terrace_vocab": ["planter", "bench", "banner"],
}

IRONWOOD = {
    "id": "ironwood_citadel", "seed": 107, "surround": "alpine",
    "layout_spread": 1.30, "camera_zoom": 0.55,
    "palette": OD([
        ("floor", "#E8E0D1"), ("shell", "#342F2B"), ("carpet", "#A64132"),
        ("rope", "#7D2B24"), ("trim", "#D5AD55"), ("panel", "#FFF9EE"),
        ("panel_soft", "#E9DDCB"), ("stone", "#918578"), ("partition", "#65594F"),
        ("room.gallery", "#B05F45"), ("room.archive", "#536B59"),
        ("room.promotions", "#7A689E"), ("room.ticket", "#C59448"),
    ]),
    "plan": [
        {"id": "gallery", "dept": "gallery", "name": "GREAT ARMORY",
         "role": "exhibit", "rect": [4, 0, 8, 7], "floor_mix": 0.36, "level": 2},
        {"id": "west_tower", "dept": "promotions", "name": "BANQUET KEEP",
         "role": "promo", "rect": [-1, 3, 5, 7], "floor_mix": 0.42, "level": 1},
        {"id": "east_tower", "dept": "archive", "name": "IRON TREASURY",
         "role": "store", "rect": [12, 3, 5, 7], "floor_mix": 0.42, "level": 1},
        {"id": "court_stair", "role": "link", "rect": [4, 7, 8, 3],
         "merge_into": "gallery", "level": 1, "rise_to": 2},
        {"id": "lower_court", "role": "link", "rect": [4, 10, 8, 3],
         "merge_into": "ticket", "level": 0, "rise_to": 1},
        {"id": "ticket", "dept": "ticket", "name": "FORTRESS GATE",
         "role": "queue", "rect": [2, 13, 12, 5], "floor_mix": 0.40},
        {"id": "lobby", "role": "lobby", "rect": [8, 18, 8, 4]},
    ],
    "terrace_count": 13,
    "art_cols": ["#B05F45", "#536B59", "#7A689E", "#C59448", "#D5AD55"],
    "terrace_vocab": ["bench", "planter", "statue"],
}

PELAGIC = {
    "id": "pelagic_crown", "seed": 131, "surround": "harbour",
    "layout_spread": 1.36, "camera_zoom": 0.48,
    # Preserve the readable scale but lift the palace enough to show its whole
    # harbour lobby; this was 19% clipped at the default centred framing.
    "camera_offset": [0, -55],
    "palette": OD([
        ("floor", "#D9F2F2"), ("shell", "#123B52"), ("carpet", "#18AFC1"),
        ("rope", "#087C91"), ("trim", "#F3C969"), ("panel", "#F5FFFF"),
        ("panel_soft", "#D3EEF3"), ("stone", "#739EAD"), ("partition", "#3B7083"),
        ("room.gallery", "#23C4C8"), ("room.archive", "#385FA8"),
        ("room.promotions", "#F07D78"), ("room.ticket", "#DDAA43"),
    ]),
    "plan": [
        {"id": "gallery", "dept": "gallery", "name": "ABYSSAL THRONE",
         "role": "exhibit", "rect": [4, 0, 8, 8], "floor_mix": 0.34, "level": 2},
        {"id": "west_fin", "dept": "promotions", "name": "CORAL FEAST",
         "role": "promo", "rect": [-2, 5, 6, 7], "floor_mix": 0.40, "level": 1},
        {"id": "east_fin", "dept": "archive", "name": "PEARL HOLD",
         "role": "store", "rect": [12, 5, 6, 7], "floor_mix": 0.40, "level": 1},
        {"id": "tide_bridge", "role": "link", "rect": [4, 8, 8, 4],
         "merge_into": "gallery", "level": 1, "rise_to": 2},
        {"id": "reef_walk", "role": "link", "rect": [3, 12, 10, 3],
         "merge_into": "ticket", "level": 0, "rise_to": 1},
        {"id": "ticket", "dept": "ticket", "name": "NAUTILUS PORT",
         "role": "queue", "rect": [1, 15, 14, 5], "floor_mix": 0.40},
        {"id": "lobby", "role": "lobby", "rect": [10, 20, 9, 4]},
    ],
    "terrace_count": 14,
    "art_cols": ["#23C4C8", "#385FA8", "#F07D78", "#DDAA43", "#F3C969"],
    "terrace_vocab": ["planter", "planter", "bench", "statue"],
}

CHRONOS = {
    "id": "chronos_spire", "seed": 157, "surround": "parkland",
    "layout_spread": 1.42, "camera_zoom": 0.48,
    # The tall plan used to lose 88% of its lobby below the viewport. Panning
    # the authored overview upward retains the cast's readable scale and keeps
    # the full entrance visible; player pan still starts at zero on top of this.
    "camera_offset": [0, -230],
    "palette": OD([
        ("floor", "#F0E9D8"), ("shell", "#343A4A"), ("carpet", "#BE6A32"),
        ("rope", "#884523"), ("trim", "#E5C15F"), ("panel", "#FFFCF2"),
        ("panel_soft", "#E8DFCA"), ("stone", "#8E929C"), ("partition", "#606576"),
        ("room.gallery", "#D79445"), ("room.archive", "#4F758B"),
        ("room.promotions", "#9B6AA8"), ("room.ticket", "#5B8C68"),
    ]),
    "plan": [
        {"id": "gallery", "dept": "gallery", "name": "HALL OF AGES",
         "role": "exhibit", "rect": [4, 0, 8, 7], "floor_mix": 0.34, "level": 3},
        {"id": "upper_stair", "role": "link", "rect": [5, 7, 6, 3],
         "merge_into": "gallery", "level": 2, "rise_to": 3},
        {"id": "archive", "dept": "archive", "name": "CLOCKWORK VAULT",
         "role": "store", "rect": [0, 8, 5, 7], "floor_mix": 0.40, "level": 2},
        {"id": "promotions", "dept": "promotions", "name": "CENTURY CLUB",
         "role": "promo", "rect": [11, 8, 5, 7], "floor_mix": 0.40, "level": 2},
        {"id": "middle_stair", "role": "link", "rect": [5, 10, 6, 5],
         "merge_into": "ticket", "level": 1, "rise_to": 2},
        {"id": "ticket", "dept": "ticket", "name": "PENDULUM HALL",
         "role": "queue", "rect": [2, 15, 12, 5], "floor_mix": 0.40, "level": 1},
        {"id": "lower_stair", "role": "link", "rect": [6, 20, 7, 3],
         "merge_into": "ticket", "level": 0, "rise_to": 1,
         "stair_axis": "y", "rise_reverse": True},
        {"id": "lobby", "role": "lobby", "rect": [12, 23, 8, 4]},
    ],
    "terrace_count": 15,
    "art_cols": ["#D79445", "#4F758B", "#9B6AA8", "#5B8C68", "#E5C15F"],
    "terrace_vocab": ["bench", "planter", "statue", "banner"],
}

EMPYREAN = {
    "id": "empyrean_palace", "seed": 181, "surround": "dunes",
    "layout_spread": 1.49, "camera_zoom": 0.48,
    # Four storeys fill the portrait frame. The centred camera put the approach
    # 57% and lobby 100% off-screen; compose the default overview around the
    # complete building rather than shrinking visitors into confetti.
    "camera_offset": [0, -480],
    "palette": OD([
        ("floor", "#F8EEDC"), ("shell", "#5C426E"), ("carpet", "#D35F8D"),
        ("rope", "#9F3F6C"), ("trim", "#FFE08A"), ("panel", "#FFF9F2"),
        ("panel_soft", "#F1DCE8"), ("stone", "#B99EBB"), ("partition", "#826A8C"),
        ("room.gallery", "#CF89D8"), ("room.archive", "#5E8BC7"),
        ("room.promotions", "#E98773"), ("room.ticket", "#D9AD4F"),
    ]),
    "plan": [
        {"id": "gallery", "dept": "gallery", "name": "CELESTIAL COURT",
         "role": "exhibit", "rect": [4, 0, 9, 8], "floor_mix": 0.32, "level": 3},
        {"id": "west_palace", "dept": "promotions", "name": "ROYAL SALON",
         "role": "promo", "rect": [-2, 4, 6, 9], "floor_mix": 0.38, "level": 2},
        {"id": "east_palace", "dept": "archive", "name": "CROWN TREASURY",
         "role": "store", "rect": [13, 4, 6, 9], "floor_mix": 0.38, "level": 2},
        {"id": "grand_stair", "role": "link", "rect": [4, 8, 9, 5],
         "merge_into": "gallery", "level": 2, "rise_to": 3},
        {"id": "state_walk", "role": "link", "rect": [3, 13, 11, 4],
         "merge_into": "ticket", "level": 1, "rise_to": 2},
        {"id": "ticket", "dept": "ticket", "name": "IMPERIAL GATE",
         "role": "queue", "rect": [1, 17, 15, 6], "floor_mix": 0.38, "level": 1},
        {"id": "approach", "role": "link", "rect": [7, 23, 8, 3],
         "merge_into": "ticket", "level": 0, "rise_to": 1,
         "stair_axis": "y", "rise_reverse": True},
        {"id": "lobby", "role": "lobby", "rect": [15, 26, 9, 4]},
    ],
    "terrace_count": 16,
    "art_cols": ["#CF89D8", "#5E8BC7", "#E98773", "#D9AD4F", "#FFE08A"],
    "terrace_vocab": ["statue", "planter", "bench", "banner"],
}

INFINITE = {
    "id": "infinite_museum", "seed": 211, "surround": "nightfall",
    # No layout_spread. The 1.0->1.56 spread ramp across venues 7-12 was a
    # mistake and this venue is where it broke: spread inflates WALKING AREA
    # without adding anything to look at, authoring compensated by winding
    # camera_zoom down to 0.24, and the renderer's readable floor (0.48) then
    # refused that compensation. Measured result was a 1872x2146 building in a
    # 1500x2666 frame: 296px cut off the left, 269px off the bottom, and ~790px
    # of dead sky above. You never saw the whole silhouette, so it never read as
    # a building at all.
    #
    # Grandeur comes from MASSING, STOREYS and COMPOSITION instead. At zoom 0.88
    # the ink is 900x840 -- 1.47x sunspire's area, framed exactly like it
    # (width ratio 1.10, height 0.58, 287px of headroom, nothing clipped).
    "camera_zoom": 0.84,
    # White marble, deep indigo night, crimson and gold: the grand-museum
    # frontage, and the only late palette built on those. INFINITE used to be
    # the one venue with a DARK floor (#27274E) under a DARK shell (#111326) --
    # two darks a tenth apart in luminance, so rooms could not separate from the
    # building they stood in. Every other late venue puts a near-white floor
    # under a dark shell; this now does too.
    #
    # The four room accents are separated by VALUE as well as hue (gold 0.68,
    # verdigris 0.55, wine 0.42, deep teal 0.30) so the rooms stay distinguishable
    # without relying on colour vision -- and room identity is carried by the
    # plaque and the massing regardless, with hue only reinforcing it.
    "palette": OD([
        ("floor", "#EFF0F5"), ("shell", "#39406B"), ("carpet", "#8E2038"),
        ("rope", "#6E1828"), ("trim", "#E8C15C"), ("panel", "#FFFFFF"),
        ("panel_soft", "#E4E7F0"), ("stone", "#C9C4B6"), ("partition", "#6A6E86"),
        # `shell` is lighter here than in the other night venues on purpose. It
        # paints the exterior of every LINK room, and this plan has five of them
        # carrying the tallest towers in the game -- at #1B1F3B those walls went
        # near-black and read as a hole punched through the middle-right of the
        # building rather than as stone at night.
        # Deliberately DEEP, because these land on the WALLS at close to full
        # strength while each room's FLOOR is `accent.lerp(cream, floor_mix)` --
        # note the direction: a HIGHER floor_mix is a PALER floor. So the museum
        # gets deep coloured walls over pale marble floors, and the great hall is
        # the palest of them at 0.62. Authoring these at mid-tone instead made the
        # patrons' range read as bubblegum pink.
        ("room.gallery", "#C9A244"), ("room.archive", "#3A6A88"),
        ("room.promotions", "#7E3557"), ("room.ticket", "#4F7A5C"),
    ]),
    "plan": [
        # OPEN PLAN. The gallery is not a room at the end of the building -- the
        # gallery IS the building's central hall, and every other department opens
        # directly off it.
        #
        # This is the one structural thing all eleven earlier venues get wrong.
        # They are LINEAR STACKS: lobby, then the gate in front of that, then a
        # stair, then wings, and the collection last, at the far terminus. The
        # player walks a spine and arrives at the thing they came to see only
        # after passing through everything else. No museum is laid out that way
        # and it gives the floor nothing to explore -- each tier reads as a band
        # stacked in front of the previous one, which is also most of why the late
        # venues look boxy.
        #
        # Here: you come in at the gate, climb once, and stand in the collection.
        # The patrons' hall is open on your left, the vault raised on your right,
        # the atrium beyond. Nothing is behind anything else and every department
        # is reachable without passing through another.
        #
        # Every row of the envelope is still CONTIGUOUS -- an interior gap reads as
        # "assets scattered", while a step on the PERIMETER is just silhouette.
        # Height goes at the SIDES of the hub, never on the entry axis. The vault
        # is a TOWER climbed off the hall's east flank, and the atrium is raised
        # behind it, so the venue carries four storeys while the way in is still
        # just gate -> stair -> collection.
        #
        # FIVE storeys, which the roster test used to demand of this venue, cannot
        # be built this way. Every extra storey needs its own stair, and a stair
        # spanning the axis is another band in front of the last one -- the exact
        # shape being removed here. Four is the most this plan carries while
        # staying open, and the upper storeys are optional exploration off the hub
        # rather than a toll on the way to the collection.
        {"id": "north_court", "role": "link", "rect": [4, 0, 6, 3],
         "merge_into": "gallery", "level": 2},
        {"id": "atrium_stair", "role": "link", "rect": [4, 3, 6, 2],
         "merge_into": "gallery", "level": 1, "rise_to": 2},
        {"id": "gallery", "dept": "gallery", "name": "THE GREAT GALLERY",
         "role": "exhibit", "rect": [3, 5, 7, 7], "floor_mix": 0.62, "level": 1},
        {"id": "promotions", "dept": "promotions", "name": "HALL OF PATRONS",
         "role": "promo", "rect": [-2, 5, 5, 8], "floor_mix": 0.48, "level": 1},
        {"id": "vault_low", "role": "link", "rect": [10, 5, 2, 3],
         "merge_into": "archive", "level": 1, "rise_to": 2,
         # A deliberate two-flight L: west/east into the level-2 landing...
         "stair_axis": "x"},
        {"id": "vault_high", "role": "link", "rect": [10, 8, 2, 3],
         "merge_into": "archive", "level": 2, "rise_to": 3,
         # ...then north/south to the archive's level-3 threshold.
         "stair_axis": "y"},
        {"id": "archive", "dept": "archive", "name": "THE GREAT VAULT",
         "role": "store", "rect": [12, 5, 5, 6], "floor_mix": 0.46, "level": 3},
        # GROUND-LEVEL AMENITY. The storey masses hold the galleries up, and the
        # ground beside them was dead space -- a slate podium with nothing on it,
        # which is what read as "empty" even after the building itself was fixed.
        # These two rooms put the museum's rest areas exactly there: seating and
        # cafe tables in the shadow of the vault, and a second lounge off the gate.
        # It costs no new footprint, because both sit INSIDE the existing envelope.
        {"id": "east_lounge", "role": "link", "rect": [10, 11, 7, 3],
         "merge_into": "ticket", "floor_mix": 0.46, "prop_density": 0.34},
        {"id": "grand_stair", "role": "link", "rect": [3, 12, 7, 2],
         "merge_into": "ticket", "level": 0, "rise_to": 1},
        {"id": "west_lounge", "role": "link", "rect": [3, 14, 3, 4],
         "merge_into": "ticket", "floor_mix": 0.46, "prop_density": 0.34},
        # The gate and lobby step EAST as they come forward. Not decoration: the
        # projection shears x by -gy, so a room's west vertex lands at
        # (gx - gy - h). Held at the gallery's gx the lobby's west vertex would
        # sit at -18 -- 150px off the left edge, a quarter of the entrance
        # invisible. Stepped east it lands at -10.
        {"id": "ticket", "dept": "ticket", "name": "GATE OF WORLDS",
         "role": "queue", "rect": [6, 14, 11, 4], "floor_mix": 0.50},
        {"id": "lobby", "role": "lobby", "rect": [10, 18, 8, 3]},
    ],
    # Authored rather than derived. finish_late's generator alternates gallery
    # and lobby and reuses a column index, which for 20 slots produced FIVE
    # distinct points and stacked the rest on top of each other.  These 20 are
    # placed around the court colonnade, the two ranges and the forecourt, in
    # the order the player buys them, so the museum dresses outward from its
    # centre.
    # Every point satisfies Iso.gx_window(gy, DECOR_EDGE_INSET) and clears the
    # authored exhibits -- checked by tests/venue/test_geometry.gd, because the
    # projection shears x by -gy and a point that looks central in the plan can
    # sit off the left edge four tiles further back.
    "decor_anchors": [
        # The great gallery first, so the player's first purchases dress the room
        # they actually stand in, then outward to the wings and the frontage.
        [3.70, 5.50], [9.50, 5.50], [9.50, 7.80], [7.90, 10.60],
        [5.00, 10.70], [3.70, 11.60], [6.60, 11.60], [9.40, 11.60],
        [4.40, 2.40], [7.00, 2.40], [9.40, 2.40],
        [-1.40, 6.20], [-1.40, 8.60], [-0.70, 11.20], [1.60, 12.50],
        [12.60, 6.20], [16.20, 7.60], [12.60, 10.20],
        [8.40, 15.20], [15.40, 17.20],
    ],
    "props": [
        OD([("kind", "cafe_table"), ("at", [11.40, 12.20]), ("col", "#9A7245"),
            ("stool", "@room.archive")]),
        OD([("kind", "cafe_table"), ("at", [13.20, 12.20]), ("col", "#9A7245"),
            ("stool", "@room.archive")]),
        OD([("kind", "cafe_table"), ("at", [15.00, 12.60]), ("col", "#9A7245"),
            ("stool", "@carpet")]),
        OD([("kind", "cafe_table"), ("at", [12.40, 13.40]), ("col", "#9A7245"),
            ("stool", "@carpet")]),
        OD([("kind", "cafe_table"), ("at", [14.20, 13.40]), ("col", "#9A7245"),
            ("stool", "@room.archive")]),
        OD([("kind", "cafe_table"), ("at", [4.40, 15.00]), ("col", "#9A7245"),
            ("stool", "@room.archive")]),
        OD([("kind", "cafe_table"), ("at", [5.40, 16.20]), ("col", "#9A7245"),
            ("stool", "@carpet")]),
        # Both along their room's wall, not across it: the east lounge's north edge
        # runs x, its east edge runs y.
        OD([("kind", "bench"), ("at", [10.60, 13.50]), ("len", 1.8), ("axis", "x")]),
        OD([("kind", "bench"), ("at", [16.35, 11.60]), ("len", 1.6), ("axis", "y")]),
        OD([("kind", "bin"), ("at", [10.40, 11.60])]),
    ],
    # Outdoor lounge. The apron is where the museum's terrace seating goes, so it
    # is both wider and more densely furnished than the default kerb, and cafe
    # tables are in its vocabulary rather than only benches and planters.
    "shell_inset": 1.15,
    "terrace_count": 22,
    # 279 tiles at the shared 0.17/tile put 56 props on this floor, most of them
    # the same planter. Thinner, and with the planters outnumbered.
    "prop_density": 0.10,
    "prop_vocab": {
        "exhibit": ["planter", "bench", "planter", "banner"],
        "store": ["shelf", "crate", "cabinet", "rack", "trolley"],
        "promo": ["desk", "kiosk", "rack", "banner"],
        "queue": ["bin", "kiosk", "planter"],
        # The court carries the colonnade and three monuments already, so it
        # stays sparse — and mixed, because an all-bench court read as a waiting
        # room rather than a peristyle.
        # The lounges and the atrium are all `link` rooms, so this is the amenity
        # vocabulary. cafe_table had been implemented in exhibits.gd since the
        # beginning and was absent from venue_kit's KINDS, so no venue could ever
        # ask for one -- the same dead-painter gap `skeleton` was in.
        "link": ["bench", "cafe_table", "planter"],
        "any": ["bench", "planter", "bin"],
    },
    "art_cols": ["#C9A244", "#3A6A88", "#7E3557", "#4F7A5C", "#E8C15C"],
    "terrace_vocab": ["bench", "cafe_table", "planter", "bench", "statue",
                      "cafe_table", "banner"],
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
        exhibit("statue", "colossus", (4.4, 2.3), (1.6, 1.2), cols, rng),
        exhibit("vitrine", "sunmask", (7.2, 2.2), (1.4, 1.0), cols, rng),
        exhibit("case", "scarabs", (4.6, 4.9), (2.2, 1.0), cols, rng),
        exhibit("plinth", "obelisk", (8.6, 5.2), (1.0, 1.0), cols, rng),
        mural("frieze", (5.8, 1.0), 2.4,
              {"sky": "#F6D89A", "land": "#C98A3E", "motif": "#FFF3D0"}),
        # Outdoors, on the forecourt: a real museum puts a piece where you meet
        # it before you have paid, and it is what makes the frontage inviting.
        outdoor_exhibit("statue", "lion", (4.4, 18.3), (1.2, 1.0), cols, rng),
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
        exhibit("vitrine", "plumage", (3.1, 7.8), (1.4, 1.0),
                dict(cols, dark="#3A4A5A"), rng),
        mural("summit", (1.2, 2.0), 2.4,
              {"sky": "#BFDCF2", "land": "#7F93A6", "motif": "#FFFFFF"}),
        outdoor_exhibit("statue", "cairn", (4.4, 16.8), (1.2, 1.0),
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
        mural("nebula", (5.4, 4.0), 2.6,
              {"sky": "#2B2160", "land": "#4A3E96", "motif": "#7CF5D4"}),
        outdoor_exhibit("statue", "monolith", (5.0, 18.4), (1.2, 1.0), cols, rng),
    ]

def column(eid, at, height=46.0, width=0.5, col="#9A7245", lip="@trim|d18"):
    """A pier. `plinth` already extrudes a box with a lip at any height, so a tall
    narrow one is a column — no new painter needed. Sized just under WALL_H (52)
    so it reads as carrying the storey above rather than poking through it."""
    return OD([("id", eid), ("kind", "plinth"),
               ("anchor", [round(at[0] + width * 0.5, 2), round(at[1] + width * 0.5, 2)]),
               ("at", [round(at[0], 2), round(at[1], 2)]),
               ("size", [width, width]), ("height", height),
               ("col", col), ("lip", lip)])


def colonnade(prefix, xs, ys, height=46.0):
    """Rows of piers down both flanks of a court."""
    out = []
    for i, x in enumerate(xs):
        for j, y in enumerate(ys):
            out.append(column(f"{prefix}_{i}{j}", (x, y), height))
    return out


def infinite_art(rng):
    """The finale collection: one piece from each realm the museum has claimed.

    Venues 7-11 all share `late_art` -- the same seven pieces at the same
    fractional offsets into whatever the gallery rect happens to be, recoloured
    per venue. It is why the late museums feel like one building repainted six
    times. This set is placed against THIS plan by hand, the way sunspire,
    cloudrest and aurora are, and it is the only one that asks for `skeleton` or
    `casket`: both painters have always existed and no venue had ever used
    either, while a mounted skeleton is the single most museum-legible object in
    the whole vocabulary.

    Court and forecourt pieces are `outdoor_exhibit`, so they carry no browse
    spots. That is deliberate and not an oversight -- a view spot outside the
    gallery sends the browsing FSM walking out of the paid building.
    """
    cols = {"light": "#F4F1E6", "dark": "#2A2438", "lip": "#C9A94E",
            "body": "#8E7A4A", "accent": "#E8C15C",
            "specimens": ["#3A6A88", "#A04C74", "#E8C15C"],
            "water": "#2C5570", "weed": "#4E7A5C",
            "fauna": ["#E8C15C", "#A04C74", "#EFF0F5"]}
    return [
        # The central hall. The skeleton sits on the entrance axis, so the first
        # thing in frame when you top the grand stair is the biggest piece here --
        # not a corridor with the collection somewhere past the end of it.
        exhibit("skeleton", "leviathan", (4.4, 5.9), (2.8, 1.3), cols, rng),
        exhibit("vitrine", "first_light", (8.0, 6.0), (1.4, 1.0), cols, rng),
        exhibit("statue", "colossus_of_ages", (3.8, 8.6), (1.5, 1.2), cols, rng),
        exhibit("plinth", "the_last_key", (6.0, 8.7), (1.1, 1.1), cols, rng),
        exhibit("case", "hall_of_wonders", (7.6, 8.7), (2.2, 1.0), cols, rng),
        hanging("orrery_of_worlds", (6.6, 7.6), 66.0, cols, ceiling=64.0),
        mural("panorama_of_ages", (4.2, 5.0), 3.0,
              {"sky": "#3A6A88", "land": "#8E7A4A", "motif": "#E8C15C"}),
        outdoor_exhibit("statue", "the_founder", (4.2, 11.0), (1.4, 1.1), cols, rng),
        # The atrium beyond the hall -- open to it, not a room past it.
        outdoor_exhibit("casket", "sarcophagus_of_kings", (4.9, 1.0), (1.8, 1.1),
                        cols, rng),
        outdoor_exhibit("plinth", "meridian_stone", (7.6, 1.0), (1.2, 1.2),
                        cols, rng),
        # The frontage, met before you have paid -- sunspire's lion rule. Both
        # sit east of gx 7.2 because at gy 19.3 the visible window starts there.
        outdoor_exhibit("statue", "sentinel_west", (11.4, 19.3), (1.2, 1.0), cols, rng),
        outdoor_exhibit("statue", "sentinel_east", (15.0, 19.3), (1.2, 1.0), cols, rng),
    ] + [
        # Piers down the hall's west aisle, flanking the atrium, and framing the
        # mouth of the grand stair -- the three places that read as architecture
        # rather than as furniture.
        column("aisle_pier_0", (3.15, 6.4)), column("aisle_pier_1", (3.15, 7.8)),
        column("aisle_pier_2", (3.15, 10.6)),
        column("atrium_pier_w", (4.15, 1.3)), column("atrium_pier_e", (9.20, 1.3)),
        column("stair_pier_w", (3.20, 12.3)), column("stair_pier_e", (9.20, 12.3)),
    ]


def celestial_art(rng):
    """A glasshouse collection built around living worlds and orbital motion."""
    cols = {"light": "#DDF5F2", "dark": "#173F4C", "lip": "#83AAA9",
            "body": "#4676C9", "accent": "#F7D774",
            "specimens": ["#55D6BE", "#E688B8", "#F7D774"],
            "water": "#3B9FC2", "weed": "#55B987",
            "fauna": ["#F7D774", "#E688B8", "#DDF5F2"]}
    return [
        # Rings, glass and a suspended sail make this room read vertically and
        # transparently; it must not inherit Aurora's row of generic plinths.
        exhibit("orrery", "grand_alignment", (5.2, 1.3), (1.6, 1.2), cols, rng),
        exhibit("tank", "living_biosphere", (8.5, 1.2), (2.0, 1.1), cols, rng),
        exhibit("vitrine", "moonseed", (4.5, 4.7), (1.4, 1.0), cols, rng),
        exhibit("plinth", "eclipse_lens", (6.8, 4.8), (1.1, 1.1), cols, rng),
        exhibit("case", "meteor_garden", (8.8, 4.7), (2.1, 1.0), cols, rng),
        hanging("solar_sail", (9.8, 3.6), 58.0, cols, ceiling=62.0),
        mural("lunar_horizon", (5.8, 0.0), 3.0,
              {"sky": "#173F4C", "land": "#4676C9", "motif": "#F7D774"}),
        outdoor_exhibit("statue", "comet_marker", (7.0, 18.2),
                        (1.3, 1.0), cols, rng),
    ]


def ironwood_art(rng):
    """A fortress armory: guarded steel, tombs and a suspended war beast."""
    cols = {"light": "#C5C8C5", "dark": "#342F2B", "lip": "#918578",
            "body": "#7D2B24", "accent": "#D5AD55",
            "specimens": ["#D5AD55", "#536B59", "#B05F45"]}
    return [
        exhibit("armor", "iron_guard_west", (5.0, 1.3), (1.3, 1.1), cols, rng),
        exhibit("armor", "iron_guard_east", (9.7, 1.3), (1.3, 1.1), cols, rng),
        exhibit("skeleton", "warhorse", (4.5, 3.4), (2.5, 1.2), cols, rng),
        exhibit("casket", "founder_tomb", (7.2, 4.7), (1.7, 1.0), cols, rng),
        exhibit("case", "siege_relics", (9.3, 4.7), (1.9, 1.0), cols, rng),
        hanging("iron_wyvern", (8.2, 3.4), 56.0, cols, ceiling=60.0),
        mural("banners_of_the_keep", (6.0, 0.0), 2.6,
              {"sky": "#65594F", "land": "#7D2B24", "motif": "#D5AD55"}),
        outdoor_exhibit("statue", "gate_champion", (7.0, 21.2),
                        (1.3, 1.0), cols, rng),
    ]


def pelagic_art(rng):
    """An aquarium court composed around a whale and two living reef wings."""
    cols = {"light": "#E8F4EA", "dark": "#123B52", "lip": "#739EAD",
            "body": "#385FA8", "accent": "#F3C969",
            "specimens": ["#F07D78", "#F3C969", "#D9F2F2"],
            "water": "#18AFC1", "weed": "#318C74",
            "fauna": ["#F07D78", "#F3C969", "#CF89D8"]}
    return [
        # The hanging skeleton is the room's long horizontal axis; tanks and
        # coral banks mirror one another below it like palace side chapels.
        suspended_skeleton("crown_whale", (8.1, 2.8), cols,
                           span=62.0, ceiling=64.0),
        exhibit("tank", "sunlit_reef", (4.6, 1.2), (1.8, 1.1), cols, rng),
        exhibit("tank", "midnight_reef", (9.6, 1.2), (1.8, 1.1),
                dict(cols, water="#385FA8"), rng),
        exhibit("coral", "coral_court_west", (4.7, 5.3), (1.7, 1.2), cols, rng),
        exhibit("touch_pool", "tide_table", (6.8, 5.3), (2.2, 1.3), cols, rng),
        exhibit("coral", "coral_court_east", (9.4, 5.3), (1.7, 1.2), cols, rng),
        mural("abyssal_window", (6.0, 0.0), 2.8,
              {"sky": "#123B52", "land": "#385FA8", "motif": "#F3C969"}),
        outdoor_exhibit("coral", "harbour_reef", (9.0, 23.2),
                        (1.5, 1.0), cols, rng),
    ]


def chronos_art(rng):
    """A hall of mechanisms with clocks marching around a central model."""
    cols = {"light": "#F0E9D8", "dark": "#343A4A", "lip": "#8E929C",
            "body": "#6B452B", "accent": "#E5C15F",
            "specimens": ["#D79445", "#4F758B", "#9B6AA8"]}
    return [
        exhibit("clockwork", "first_chime", (5.0, 1.2), (1.2, 1.0), cols, rng),
        exhibit("orrery", "age_engine", (7.2, 1.2), (1.5, 1.2), cols, rng),
        exhibit("clockwork", "last_chime", (9.8, 1.2), (1.2, 1.0), cols, rng),
        exhibit("casket", "sealed_century", (4.7, 4.7), (1.7, 1.0), cols, rng),
        exhibit("case", "watchmakers_table", (7.0, 4.7), (1.9, 1.0), cols, rng),
        exhibit("vitrine", "millennium_key", (9.8, 4.7), (1.3, 1.0), cols, rng),
        mural("calendar_of_ages", (5.9, 0.0), 2.7,
              {"sky": "#4F758B", "land": "#343A4A", "motif": "#E5C15F"}),
        outdoor_exhibit("clockwork", "gate_clock", (11.0, 26.2),
                        (1.2, 1.0), cols, rng),
    ]


def empyrean_art(rng):
    """A royal court framed by gold-capped columns and ceremonial guards."""
    cols = {"light": "#F1DCE8", "dark": "#5C426E", "lip": "#B99EBB",
            "body": "#9F3F6C", "accent": "#FFE08A",
            "specimens": ["#5E8BC7", "#E98773", "#FFE08A"]}
    return [
        exhibit("throne", "cloud_throne", (7.8, 1.3), (1.6, 1.2), cols, rng),
        exhibit("armor", "royal_guard_west", (5.0, 1.5), (1.3, 1.1), cols, rng),
        exhibit("armor", "royal_guard_east", (10.8, 1.5), (1.3, 1.1), cols, rng),
        exhibit("vitrine", "star_crown", (4.8, 5.2), (1.4, 1.0), cols, rng),
        exhibit("case", "imperial_regalia", (7.3, 5.2), (2.0, 1.0), cols, rng),
        exhibit("casket", "founding_dynasty", (10.2, 5.2), (1.8, 1.0), cols, rng),
        hanging("cloud_chariot", (8.5, 3.8), 62.0, cols, ceiling=64.0),
        mural("court_of_heaven", (7.0, 0.0), 3.0,
              {"sky": "#5E8BC7", "land": "#CF89D8", "motif": "#FFE08A"}),
        outdoor_exhibit("statue", "palace_herald", (14.0, 29.2),
                        (1.4, 1.0), cols, rng),
        # These are architecture, not browse targets. At the late venue's small
        # zoom, four pale verticals make the room read as a palace before any
        # individual treasure is large enough to inspect.
        column("court_column_nw", (4.25, 0.6), col="#F1DCE8", lip="#FFE08A"),
        column("court_column_ne", (12.15, 0.6), col="#F1DCE8", lip="#FFE08A"),
        column("court_column_sw", (4.25, 7.0), col="#F1DCE8", lip="#FFE08A"),
        column("court_column_se", (12.15, 7.0), col="#F1DCE8", lip="#FFE08A"),
    ]


def late_art(spec, rng):
    """A coherent landmark set placed from the venue's own gallery/lobby."""
    gallery = next(r for r in spec["plan"] if r["role"] == "exhibit")
    lobby = next(r for r in spec["plan"] if r["role"] == "lobby")
    gx, gy, gw, gh = gallery["rect"]
    lx, ly, lw, lh = lobby["rect"]
    pal = spec["palette"]
    cols = {
        "light": pal["panel_soft"], "dark": pal["shell"],
        "lip": pal["stone"], "body": pal["room.gallery"],
        "accent": pal["trim"],
        "specimens": [pal["room.archive"], pal["room.promotions"], pal["trim"]],
        "water": pal["room.gallery"], "weed": pal["room.archive"],
        "fauna": [pal["trim"], pal["room.promotions"], pal["room.ticket"]],
    }
    return [
        exhibit("statue", spec["id"] + "_crown",
                (gx + gw * 0.12, gy + gh * 0.22), (1.5, 1.2), cols, rng),
        exhibit("vitrine", spec["id"] + "_relic",
                (gx + gw * 0.48, gy + gh * 0.20), (1.5, 1.0), cols, rng),
        exhibit("case", spec["id"] + "_collection",
                (gx + gw * 0.16, gy + gh * 0.62), (2.2, 1.0), cols, rng),
        exhibit("plinth", spec["id"] + "_icon",
                (gx + gw * 0.68, gy + gh * 0.62), (1.2, 1.1), cols, rng),
        hanging(spec["id"] + "_canopy",
                (gx + gw * 0.58, gy + gh * 0.48), 62.0, cols, ceiling=62.0),
        mural(spec["id"] + "_panorama", (gx + gw * 0.28, gy), gw * 0.36,
              {"sky": pal["room.archive"], "land": pal["room.gallery"],
               "motif": pal["trim"]}),
        outdoor_exhibit("statue", spec["id"] + "_sentinel",
                (lx - 1.0, ly + lh - 0.6), (1.3, 1.0), cols, rng),
    ]


def finish(spec, art_fn, carpet_at, bunting):
    rng = random.Random(spec["seed"] + 7)
    spec = dict(spec)
    # A venue may narrow or widen the scatter vocabulary. The shared default is
    # 75% planters in exhibit rooms, which is invisible at 20 props and reads as
    # a garden centre at 56.
    spec.setdefault("prop_vocab", PROP_VOCAB)
    spec["exhibits"] = art_fn(rng)
    spec["floor_dressing"] = rugs(spec["plan"], rng)
    spec["carpet"] = [OD([("kind", "patch"), ("at", carpet_at[0]),
                          ("size", carpet_at[1]), ("col", "@carpet")])]
    spec["ceiling"] = bunting
    if "decor_anchors" not in spec:
        slot_counts = {
            "sunspire": 8, "cloudrest": 10, "aurora_world": 12,
        }
        gallery = next(r for r in spec["plan"] if r["role"] == "exhibit")
        lobby = next(r for r in spec["plan"] if r["role"] == "lobby")
        anchors = []
        for index in range(slot_counts.get(spec["id"], 0)):
            room = gallery if index % 2 == 0 else lobby
            rx, ry, rw, rh = room["rect"]
            lane = index // 2
            cols = max(3, int(rw // 2))
            col = lane % cols
            row = (lane // cols) % 2
            anchors.append([
                round(rx + 0.75 + col * max(0.8, (rw - 1.5) / max(1, cols - 1)), 2),
                round(ry + (0.75 if row == 0 else rh - 0.75), 2),
            ])
        spec["decor_anchors"] = anchors
    return spec


def bunt(frm, to, cols):
    return OD([("kind", "bunting"), ("from", frm), ("to", to),
               ("height", 46.0), ("sag", 9.0), ("flags", 5), ("cols", cols)])

def finish_late(spec, art_fn=None):
    """Late-venue assembly. `art_fn` overrides the shared generic exhibit set.

    Pass one whenever a venue is worth composing by hand -- see infinite_art for
    what that buys, and for why every venue still on `late_art` reads as the same
    museum repainted.
    """
    spec = dict(spec)
    ticket = next(r for r in spec["plan"] if r["role"] == "queue")
    lobby = next(r for r in spec["plan"] if r["role"] == "lobby")
    gallery = next(r for r in spec["plan"] if r["role"] == "exhibit")
    tx, ty, tw, _ = ticket["rect"]
    lx, ly, lw, lh = lobby["rect"]
    slot_counts = {
        "celestial_conservatory": 12, "ironwood_citadel": 14,
        "pelagic_crown": 14, "chronos_spire": 16,
        "empyrean_palace": 18, "infinite_museum": 20,
    }
    # An authored list always wins. The generator below walks a column index that
    # wraps every `cols` lanes, so above ~12 slots it starts handing out points it
    # has already used -- for infinite_museum's 20 slots it yielded five distinct
    # positions and stacked the remaining fifteen on top of them.
    if "decor_anchors" not in spec:
        anchors = []
        for index in range(slot_counts[spec["id"]]):
            room = gallery if index % 2 == 0 else lobby
            rx, ry, rw, rh = room["rect"]
            lane = index // 2
            cols = max(3, int(rw // 2))
            col = lane % cols
            row = (lane // cols) % 2
            anchors.append([
                round(rx + 0.75 + col * max(0.8, (rw - 1.5) / max(1, cols - 1)), 2),
                round(ry + (0.75 if row == 0 else rh - 0.75), 2),
            ])
        spec["decor_anchors"] = anchors
    colours = ["@trim", "@room.gallery", "@room.promotions",
               "@room.archive", "@room.ticket"]
    return finish(spec, art_fn or (lambda rng: late_art(spec, rng)),
                  ([lx + lw * 0.42, ly], [max(1.6, lw * 0.20), lh]),
                  [bunt([tx + 1.0, ty + 0.2], [tx + tw * 0.48, ty + 0.2], colours),
                   bunt([tx + tw * 0.52, ty + 0.2], [tx + tw - 1.0, ty + 0.2],
                        list(reversed(colours)))])


SPECS = [
    finish(SUNSPIRE, sunspire_art, ([8.0, 16.0], [1.6, 3.0]), [
        bunt([3.0, 12.2], [7.0, 12.2], ["@room.ticket", "@trim", "#E8622F", "#3FBFB5", "#F4A93C"]),
        bunt([7.4, 12.2], [12.0, 12.2], ["@trim", "#E56BB0", "@room.gallery", "#6C8CE8", "#E8622F"]),
    ]),
    finish(CLOUDREST, cloudrest_art, ([9.0, 15.0], [1.6, 3.0]), [
        bunt([4.0, 11.2], [7.2, 11.2], ["@room.ticket", "@trim", "#59C3E8", "#7FCB8C", "#C58CF0"]),
        bunt([7.6, 11.2], [11.2, 11.2], ["#F2A65A", "@trim", "#59C3E8", "#FFFFFF", "#7FCB8C"]),
    ]),
    finish(AURORA, aurora_art, ([9.2, 17.0], [1.6, 3.0]), [
        bunt([4.0, 13.2], [7.4, 13.2], ["@trim", "#22D3EE", "#F472B6", "#FBBF24", "#8B6BFF"]),
        bunt([7.8, 13.2], [12.2, 13.2], ["#22D3EE", "@trim", "#FBBF24", "#F472B6", "#7CF5D4"]),
    ]),
    finish_late(CELESTIAL, celestial_art),
    finish_late(IRONWOOD, ironwood_art),
    finish_late(PELAGIC, pelagic_art),
    finish_late(CHRONOS, chronos_art),
    finish_late(EMPYREAN, empyrean_art),
    finish_late(INFINITE, infinite_art),
]

LATE_META = [
    ("celestial_conservatory", "Celestial Conservatory", 7, 1.2, 18, 310.8, 18, 100, 0.90, 12,
     "A moonlit glasshouse whose orbital collection circles a living conservatory."),
    ("ironwood_citadel", "Ironwood Citadel", 8, 2.0, 21, 2240, 21, 100, 0.82, 14,
     "A mountain fortress museum of armories, royal halls, and guarded treasure."),
    ("pelagic_crown", "Pelagic Crown", 9, 3.5, 24, 14805, 24, 100, 0.75, 14,
     "A vast ocean palace where abyssal wonders gather beneath a coral crown."),
    ("chronos_spire", "Chronos Spire", 10, 6.0, 27, 90000, 27, 100, 0.68, 16,
     "A four-storey monument to time, machinery, and the civilizations between."),
    ("empyrean_palace", "Empyrean Palace", 11, 1.0, 31, 48400, 31, 100, 0.62, 18,
     "A monumental palace museum ascending through royal courts into the clouds."),
    ("infinite_museum", "The Infinite Museum", 12, 2.0, 34, 9600, 34, 100, 0.56, 20,
     "The final world museum: every age, realm, and impossible collection in one."),
]

MILESTONE_NAMES = {
    "celestial_conservatory": ["First Light", "Living Orbit", "Moon Salon", "Star Vault",
        "Glasshouse Gala", "Constellation Wing", "Celestial Laurels", "Grand Alignment"],
    "ironwood_citadel": ["Open the Gates", "Armory Muster", "Keep Feast", "Treasury Seal",
        "Citadel Court", "Royal Standard", "Mountain Crown", "Ironwood Ascendant"],
    "pelagic_crown": ["First Dive", "Coral Procession", "Pearl Reserve", "Abyssal Court",
        "Tidal Festival", "Leviathan Wing", "Ocean Crown", "Sovereign of the Deep"],
    "chronos_spire": ["First Chime", "Pendulum Hall", "Century Club", "Clockwork Reserve",
        "Age Gallery", "Millennium Bell", "Chronos Crown", "Master of Ages"],
    "empyrean_palace": ["Palace Doors", "Royal Salon", "Crown Treasury", "State Procession",
        "Celestial Court", "Empyrean Gala", "Cloud Throne", "Palace Eternal"],
    "infinite_museum": ["Open the Gate", "Realm One", "Eternity Lounge", "Singularity Vault",
        "Mirror Worlds", "Infinite Rotunda", "All Ages United", "The Endless Exhibition"],
}

def meta_record(row):
    vid, name, order, value_m, value_e, cost_m, cost_e, cap, pace, slots, desc = row
    return OD([
        ("id", vid), ("name", name), ("order", order),
        ("base_value_m", value_m), ("base_value_e", value_e),
        ("cost_mult", cost_m), ("cost_exp", cost_e),
        ("track_level_cap", cap), ("quest_progress_mult", pace),
        ("decor_slots", slots), ("desc", desc),
    ])

def milestone_chain(vid, order):
    out = []
    for index, name in enumerate(MILESTONE_NAMES[vid], 1):
        out.append(OD([
            ("id", "%s_m%d" % ("".join(p[0] for p in vid.split("_")), index)),
            ("venue_id", vid),
            ("name", name + (" (COMPLETE)" if index == 8 else "")),
            ("reward", OD([
                ("gems", order * 100 * index),
                ("box", "executive_case" if index >= 6 else
                        "specialist_case" if index >= 3 else "field_case"),
            ])),
            ("global_income_mult", round(1.04 + index * 0.025, 3)),
        ]))
    return out


def main():
    check_only = "--check" in sys.argv
    with open(VENUES) as f:
        doc = json.load(f, object_pairs_hook=collections.OrderedDict)
    by_id = {v["id"]: v for v in doc["venues"]}
    for row in LATE_META:
        vid = row[0]
        if vid not in by_id:
            record = meta_record(row)
            doc["venues"].append(record)
            by_id[vid] = record
        else:
            # Balance metadata is authored here too; rerunning the tool must
            # apply tuning changes instead of only regenerating geometry.
            for key, value in meta_record(row).items():
                by_id[vid][key] = value

    # Venues whose framing is KNOWN BROKEN and not yet reframed.
    #
    # These three authored a camera_zoom below the renderer's readable floor
    # (0.48), so the value in the data was never the value drawn. Correcting the
    # data to what actually renders is what exposed the real defect underneath:
    # at 0.48, chronos_spire's lobby is 88% off-canvas and empyrean_palace's is
    # 100% — on those levels the front door and the entrance crowd are simply
    # not on screen. pelagic_crown's is 19%.
    #
    # They are listed here rather than silently re-lowered, because lowering the
    # zoom back is what hid the bug in the first place: the validator then blesses
    # a framing the game cannot draw. Each entry FAILS LOUDLY on every run until
    # its plan is stepped east the way infinite_museum's now is. Delete a name
    # when its venue is reframed; delete the list when it is empty.
    REFRAME_PENDING = set()

    warnings = []
    for spec in SPECS:
        theme = build(spec)
        pending = spec["id"] in REFRAME_PENDING
        warns, errs = VK.validate(spec["id"], theme, strict=not pending)
        warnings += warns
        for err in errs:
            warnings.append(f"{spec['id']}: FRAMING BROKEN, awaiting reframe — {err}")
        b = VK.bounds(theme["rooms"])
        clipped = sum(VK.clip_fraction(r["rect"],
                      float(theme.get("layout_spread", 1.0)),
                      float(theme.get("camera_zoom", 1.0)),
                      theme.get("camera_offset", [0.0, 0.0]))
                      * r["rect"][2] * r["rect"][3]
                      for r in theme["rooms"])
        area = sum(r["rect"][2] * r["rect"][3] for r in theme["rooms"])
        print(f"{spec['id']:<14} rooms={len(theme['rooms'])} "
              f"walls={len(theme['walls'])} exh={len(theme['exhibits'])} "
              f"props={len(theme['props'])} "
              f"dress={sum(len(v) for v in theme['dressing'].values())} "
              f"bounds={tuple(b)} clip={clipped / area:.1%} "
              f"surround={theme['surround']}")
        by_id[spec["id"]]["theme"] = theme

    for w in warnings:
        print("  warn:", w)

    if check_only:
        print("\n--check: nothing written")
        return 0
    with open(MILESTONES) as f:
        qdoc = json.load(f, object_pairs_hook=collections.OrderedDict)
    for row in LATE_META:
        qdoc["milestones"][row[0]] = milestone_chain(row[0], row[2])
    with open(VENUES, "w") as f:
        json.dump(doc, f, indent=2)
    with open(MILESTONES, "w") as f:
        json.dump(qdoc, f, indent=2)
    print(f"\nwrote {VENUES}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
