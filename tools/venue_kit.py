#!/usr/bin/env python3
"""Venue authoring kit — validation and derivation for venue theme blocks.

WHY THIS EXISTS

A venue theme is ~10-13KB of hand-shaped JSON, and three classes of mistake in
it are invisible until someone renders the venue and squints:

  1. CLIPPING. The visible floor is a DIAMOND, not a rectangle. The projection
     shears x by -gy, so a room's east vertex sits at (gx+w-gy) and its west
     vertex at (gx-gy-h), and BOTH have to stay inside a 720px canvas. An
     axis-aligned box poking out both side vertices is why the venues so far
     read as the same shape crammed into the same hole — and why one shipped
     with 45% of its archive off-screen.

     The useful consequence: the constraint FORCES a plan to narrow toward the
     bottom-left. Following it produces varied outlines for free; fighting it
     produces clipped boxes.

  2. SHAPE MISMATCH. `dressing` is a Dictionary keyed by BAND
     (carpet/floor/wall/ceiling). Authored as a flat list it casts to null and
     the entire block silently does not draw. That has already happened once.

  3. UNREGISTERED KINDS. A typo in a `kind` draws nothing, silently.

So a venue is declared as a PLAN (rects + roles) plus a VOCABULARY (palette,
exhibit kinds, prop kinds), and everything bulky — walls, floor dressing, wall
art, prop scatter — is derived and validated here. Authoring a venue becomes a
statement about its shape and its subject rather than 400 lines of coordinates.
"""

import collections
import random

# --- projection, mirrored from scenes/venue/floor/iso.gd ---------------------
ORIGIN = (390.0, 80.0)
HALF = (30.0, 20.0)          # TILE * 0.5
VIEW = (720.0, 760.0)

# Calibrated from the venues that already ship and look right: they run about
# 7% of floor area past the canvas edge, all of it the extreme side vertices.
# Total is held at roughly that. Per-room is held well BELOW what shipped,
# because one room half off-screen is what reads as broken even when the total
# looks fine (grand_river's archive was 45% and it showed).
CLIP_TOTAL_MAX = 0.075
CLIP_ROOM_MAX = 0.22

# Kinds registered in scenes/venue/floor/exhibits.gd.
KINDS = {
    "skeleton", "casket", "statue", "vitrine", "case", "tank", "hanging",
    "hung_skeleton", "touch_pool", "mural", "plinth", "orrery", "armor",
    "coral", "clockwork", "throne",
    "counter", "info_desk", "desk", "vault_door", "facade", "kiosk", "shelf",
    "rope_line",
    "bench", "cafe_table", "planter", "kelp", "bin", "rack", "cabinet", "crate", "trolley",
    "machine", "banner", "balloons", "recycle_bin",
    "rug", "patch", "picture", "porthole", "notice", "poster", "bunting",
}
ROLES_REQUIRED = {"queue", "store", "promo", "exhibit", "lobby"}
BANDS = ("carpet", "floor", "wall", "ceiling")


def screen(gx, gy):
    return (ORIGIN[0] + (gx - gy) * HALF[0], ORIGIN[1] + (gx + gy) * HALF[1])


def on_canvas(gx, gy, margin=10.0):
    x, y = screen(gx, gy)
    return margin <= x <= VIEW[0] - margin and margin <= y <= VIEW[1] - margin


def framed_screen(gx, gy, spread=1.0, zoom=1.0, camera_offset=(0.0, 0.0)):
    """Projected point after VenueFloor's per-venue spread and camera framing."""
    sx, sy = screen(gx * spread, gy * spread)
    return ((VIEW[0] - VIEW[0] * zoom) * 0.5 + (sx + camera_offset[0]) * zoom,
            (VIEW[1] - VIEW[1] * zoom) * 0.5 + (sy + camera_offset[1]) * zoom)


def clip_fraction(rect, spread=1.0, zoom=1.0, camera_offset=(0.0, 0.0)):
    """Fraction of a room's floor area falling off the canvas."""
    gx, gy, w, h = rect
    n = bad = 0
    yy = gy + 0.25
    while yy < gy + h:
        xx = gx + 0.25
        while xx < gx + w:
            n += 1
            sx, sy = framed_screen(xx, yy, spread, zoom, camera_offset)
            if not (10.0 <= sx <= VIEW[0] - 10.0 and
                    10.0 <= sy <= VIEW[1] - 10.0):
                bad += 1
            xx += 0.5
        yy += 0.5
    return (bad / n) if n else 0.0


# --- validation ---------------------------------------------------------------

def validate(vid, theme, strict=True):
    """Return warnings; raise on anything that would render wrong or not at all."""
    errs, warns = [], []
    rooms = theme.get("rooms", [])
    spread = float(theme.get("layout_spread", 1.0))
    zoom = float(theme.get("camera_zoom", 1.0))
    camera_offset = theme.get("camera_offset", [0.0, 0.0])

    missing = ROLES_REQUIRED - {r.get("role") for r in rooms}
    if missing:
        errs.append(f"missing load-bearing role(s): {sorted(missing)}")

    total = bad = 0.0
    for r in rooms:
        gx, gy, w, h = r["rect"]
        frac = clip_fraction(r["rect"], spread, zoom, camera_offset)
        cells = w * h
        total += cells
        bad += cells * frac
        if frac > CLIP_ROOM_MAX:
            errs.append(
                f"room '{r['id']}' is {frac:.0%} off-canvas (max {CLIP_ROOM_MAX:.0%}) "
                f"— east vertex gx-gy={gx + w - gy:g}, west vertex={gx - gy - h:g}")
        elif frac > 0.12:
            warns.append(f"{vid}: room '{r['id']}' is {frac:.0%} clipped")
    if total and bad / total > CLIP_TOTAL_MAX:
        errs.append(f"plan is {bad / total:.0%} off-canvas (max {CLIP_TOTAL_MAX:.0%})")

    for i, a in enumerate(rooms):
        ax, ay, aw, ah = a["rect"]
        for b in rooms[i + 1:]:
            bx, by, bw, bh = b["rect"]
            if ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah:
                errs.append(f"rooms '{a['id']}' and '{b['id']}' overlap")

    for group in ("exhibits", "props"):
        for item in theme.get(group, []):
            if item.get("kind") not in KINDS:
                errs.append(f"{group}: unregistered kind '{item.get('kind')}'")

    dressing = theme.get("dressing")
    if not isinstance(dressing, dict):
        errs.append("dressing must be a Dictionary keyed by band "
                    "(carpet/floor/wall/ceiling), not a flat list")
    else:
        for band, items in dressing.items():
            if band not in BANDS:
                errs.append(f"dressing: unknown band '{band}'")
            for it in items:
                if it.get("kind") not in KINDS:
                    errs.append(f"dressing.{band}: unregistered kind '{it['kind']}'")

    if not theme.get("surround"):
        errs.append("no surround style named")

    if errs and strict:
        raise SystemExit(f"\n{vid} FAILED validation:\n  " + "\n  ".join(errs))
    return warns, errs


# --- geometry helpers ---------------------------------------------------------

def covered(rooms, gx, gy):
    """Is this half-tile point inside any room?"""
    for r in rooms:
        rx, ry, rw, rh = r["rect"]
        if rx <= gx < rx + rw and ry <= gy < ry + rh:
            return True
    return False


def _level_span(room):
    """The storeys a room occupies. A staircase occupies BOTH of its ends."""
    lo = int(room.get("level", 0))
    hi = int(room.get("rise_to", lo))
    return (min(lo, hi), max(lo, hi))


def joined_at(rooms, gx, gy, level):
    """Is the room at this point walkable-into FROM `level`?

    The distinction `covered` cannot make, and the reason a three-storey vault
    shipped with a doorway cut through its floor edge.

    Wall derivation calls a boundary "interior" whenever another room is on the
    far side of it, then puts a partition there with a door through the middle.
    That is right for two rooms on one storey and nonsense across a cliff: the
    vault sits at level 3 with a ground-floor lounge directly south of it, so a
    46px partition was emitted against a 222px drop — and then holed. It reads
    exactly like a missing wall, because that is what it is.

    A neighbour counts as joined only if its storey SPAN contains `level`, which
    also gets stairs right for nothing: a flight from 0 to 1 occupies both, so it
    joins the room below and the room above, and nothing else.
    """
    for r in rooms:
        rx, ry, rw, rh = r["rect"]
        if rx <= gx < rx + rw and ry <= gy < ry + rh:
            lo, hi = _level_span(r)
            return lo <= level <= hi
    return False


def bounds(rooms):
    xs = [r["rect"][0] for r in rooms] + [r["rect"][0] + r["rect"][2] for r in rooms]
    ys = [r["rect"][1] for r in rooms] + [r["rect"][1] + r["rect"][3] for r in rooms]
    return (min(xs), min(ys), max(xs) - min(xs), max(ys) - min(ys))


def structural_signature(theme):
    """Small, stable description of a venue's massing.

    Palette, prop vocabulary and labels are deliberately excluded: two venues
    with the same room arrangement are the same building even if one is blue
    and filled with fish. Used by authoring checks and tests to prevent the
    six-venue roster collapsing back into one four-room template.
    """
    rooms = theme.get("rooms", [])
    bx, by, bw, bh = bounds(rooms)
    roles = {}
    levels = set()
    for room in rooms:
        role = room.get("role")
        if role in ("exhibit", "store", "promo", "queue", "lobby"):
            x, y, w, h = room["rect"]
            roles[role] = (
                round((x - bx) / max(bw, 1), 2),
                round((y - by) / max(bh, 1), 2),
                round(w / max(bw, 1), 2),
                round(h / max(bh, 1), 2),
                int(room.get("level", 0)),
            )
        levels.add(int(room.get("level", 0)))
        levels.add(int(room.get("rise_to", room.get("level", 0))))
    return {
        "aspect": round(bw / max(bh, 1), 2),
        "room_count": len(rooms),
        "levels": tuple(sorted(levels)),
        "roles": roles,
    }


def structural_distance(a, b):
    """0 is the same plan; larger values mean visibly different massing."""
    sa, sb = structural_signature(a), structural_signature(b)
    score = abs(sa["aspect"] - sb["aspect"]) * 0.5
    score += abs(sa["room_count"] - sb["room_count"]) * 0.12
    score += len(set(sa["levels"]) ^ set(sb["levels"])) * 0.35
    for role in set(sa["roles"]) | set(sb["roles"]):
        if role not in sa["roles"] or role not in sb["roles"]:
            score += 1.0
            continue
        score += sum(abs(x - y) for x, y in zip(sa["roles"][role], sb["roles"][role]))
    return round(score, 3)


# --- derivation ---------------------------------------------------------------

def derive_walls(rooms, colour_of, partition="@partition",
                 exterior_h=None, interior_h=46.0, parapet_h=19.0):
    """A wall on EVERY room boundary, with doorways cut through the interior ones.

    THIS IS WHAT MAKES A VENUE READ AS A BUILDING. The previous rule only walled
    edges that faced open air, so the inside was one continuous plane with
    coloured floor patches on it — reported, correctly, as "no walls or
    staircases / section division". The reference draws a full partition between
    every pair of rooms and cuts a door through it, and that single difference is
    most of why its floors read as separate rooms rather than as zones.

    Only NORTH and WEST faces are drawn. A south or east wall stands between the
    camera and the room it belongs to and would black out its own interior; and
    every shared boundary is still covered exactly once, because the more
    southern room's north wall IS the northern room's south wall.

    Doorways are a GAP in the run rather than a new kind: a wall with a hole in
    it is two shorter walls, so this needs nothing from the renderer. The sim
    never consults them — walkers cross where they always did — so a doorway is
    a promise about where people LOOK like they walk, and it is placed on the
    middle of the shared span where the traffic actually crosses.
    """
    walls = []

    def emit(at, length, axis, interior, height=None, level=0):
        if length <= 0:
            return
        # Exteriors take the room's own accent, shaded by which way the face
        # turns: north catches the key light, west is turned away from it.
        shade = "|d10" if axis == "x" else "|d22"
        col = partition if interior else colour_of_edge + shade
        entry = {"at": [round(at[0], 2), round(at[1], 2)],
                 "len": round(length, 2), "axis": axis, "col": col}
        if height is not None:
            entry["h"] = height
        elif interior:
            entry["h"] = interior_h
        elif exterior_h is not None:
            entry["h"] = exterior_h
        # A south or east face is anchored on the room's FAR edge, so the
        # renderer cannot recover its storey by sampling just inside the corner.
        # Carry it explicitly. (North and west faces get it too, so every wall
        # states its own storey rather than half of them relying on a probe.)
        if level:
            entry["level"] = int(level)
        walls.append(entry)

    def runs(edge_cells):
        """Group consecutive cells sharing an interior/exterior classification."""
        out, run = [], None
        for pos, interior in edge_cells:
            if run is not None and run[2] == interior and pos == run[0] + run[1]:
                run[1] += 1
            else:
                if run is not None:
                    out.append(run)
                run = [pos, 1, interior]
        if run is not None:
            out.append(run)
        return out

    def with_doorway(start, length):
        """Split an interior run into segments either side of a door."""
        if length < 2:
            return []                      # too short to wall AND door: leave open
        door = 2 if length >= 6 else 1
        lead = (length - door) // 2
        segs = []
        if lead > 0:
            segs.append((start, lead))
        tail = length - lead - door
        if tail > 0:
            segs.append((start + lead + door, tail))
        return segs

    for r in rooms:
        gx, gy, w, h = r["rect"]
        colour_of_edge = colour_of(r)
        level = int(r.get("level", 0))
        # North face, cell by cell: is there a room on the far side of it?
        cells = [(gx + i, joined_at(rooms, gx + i + 0.5, gy - 0.5, level))
                 for i in range(w)]
        for start, length, interior in runs(cells):
            if interior:
                for s0, ln in with_doorway(start, length):
                    emit((s0, gy), ln, "x", True, level=level)
            else:
                emit((start, gy), length, "x", False, level=level)
        # West face.
        cells = [(gy + j, joined_at(rooms, gx - 0.5, gy + j + 0.5, level))
                 for j in range(h)]
        for start, length, interior in runs(cells):
            if interior:
                for s0, ln in with_doorway(start, length):
                    emit((gx, s0), ln, "y", True, level=level)
            else:
                emit((gx, start), length, "y", False, level=level)
        # South and east EXTERIOR faces, as a low parapet.
        #
        # These were emitted nowhere. The original rule was that only north and
        # west faces are drawn, on the grounds that a shared boundary is covered
        # once because the southern room's north wall IS the northern room's south
        # wall. True for a shared boundary — and silent about the building's
        # PERIMETER, where there is no southern room to supply the wall. So every
        # venue's south and east outside edges had no wall at all: the floor simply
        # stopped. On a raised storey that reads as a hole punched in the building.
        #
        # Kept LOW (well under WALL_H) precisely because of the original concern:
        # a full-height wall on the camera side would black out the room behind it.
        # A parapet closes the shell and you still see over it, which is what the
        # genre does.
        for start, length, interior in runs(
                [(gx + i, joined_at(rooms, gx + i + 0.5, gy + h + 0.5, level))
                 for i in range(w)]):
            if not interior:
                emit((start, gy + h), length, "x", False, height=parapet_h, level=level)
        for start, length, interior in runs(
                [(gy + j, joined_at(rooms, gx + w + 0.5, gy + j + 0.5, level))
                 for j in range(h)]):
            if not interior:
                emit((gx + w, start), length, "y", False, height=parapet_h, level=level)

    # Back to front. Walls are drawn in list order into one canvas item, so a
    # wall further from the camera has to be emitted first or it paints over the
    # one in front of it.
    walls.sort(key=lambda e: e["at"][0] + e["at"][1])
    return walls


def derive_wall_art(rooms, rng, palette_keys, density=0.55):
    """Framed pictures along the north walls, spaced and jittered.

    Wall art is the cheapest thing that makes a room read as curated rather than
    as a coloured rectangle, and it costs nothing per frame — the whole band is
    drawn into the shared ground canvas item.
    """
    art = []
    for r in rooms:
        if r.get("role") == "lobby":
            continue
        gx, gy, w, _ = r["rect"]
        x = gx + 0.8
        while x < gx + w - 0.6:
            if not covered(rooms, x, gy - 0.5) and rng.random() < density:
                art.append({
                    "kind": "picture", "at": [round(x, 2), gy], "axis": "x",
                    "len": round(rng.uniform(0.7, 1.1), 2),
                    "y0": round(rng.uniform(20.0, 25.0), 1),
                    "y1": round(rng.uniform(36.0, 42.0), 1),
                    "col": rng.choice(palette_keys),
                })
            x += rng.uniform(1.3, 1.9)
    return art


def scatter_props(rooms, rng, vocab, blocked, count):
    """Furniture on free floor, kept off the walkways and out of the fixtures.

    Placement is validated against the plan rather than eyeballed: a prop on a
    queue lane or inside a counter is invisible at authoring time and obvious in
    the first screenshot.
    """
    out = []
    taken = list(blocked)
    rooms_by_role = collections.defaultdict(list)
    for r in rooms:
        rooms_by_role[r.get("role")].append(r)

    attempts = 0
    while len(out) < count and attempts < count * 60:
        attempts += 1
        r = rng.choice(rooms)
        role = r.get("role")
        kinds = vocab.get(role) or vocab.get("any")
        if not kinds:
            continue
        gx, gy, w, h = r["rect"]
        if w < 2 or h < 2:
            continue
        px = round(rng.uniform(gx + 0.6, gx + w - 0.8), 2)
        py = round(rng.uniform(gy + 0.6, gy + h - 0.8), 2)
        if not on_canvas(px, py, 24.0):
            continue
        if any(abs(px - tx) < 1.0 and abs(py - ty) < 0.9 for tx, ty in taken):
            continue
        taken.append((px, py))
        kind = rng.choice(kinds)
        prop = {"kind": kind, "at": [px, py]}
        if kind == "bench":
            prop["len"] = round(rng.uniform(1.4, 2.0), 2)
        out.append(prop)
    return out


def prop_palette(kind):
    """Palette tokens a scattered prop needs so it takes the VENUE's colours.

    A prop emitted as bare {kind, at} falls back to whatever its painter defaults
    to, and most of those defaults are sensible neutrals — wood, foliage, slate.
    `banner` is not: exhibits.gd defaults its cloth to UI.ROOM_PROMO, a global
    interface accent. So every scattered banner came out the same hot magenta
    regardless of the museum it stood in, which is exactly how twelve of them
    looked in a wine-and-gold building. Anything else whose default is a UI
    colour rather than a material belongs in this table too.
    """
    if kind == "banner":
        return {"col": "@carpet", "field": "@panel", "motif": "@trim"}
    return {}


def stair_orientation(rooms, stair):
    """Which way a flight climbs, derived from what it connects.

    The renderer's fallback is "rise along the longer side", and for a staircase
    that is backwards: a grand flight is WIDE and SHALLOW, so you climb it across
    its short axis. Every stair in the roster is wider than it is deep, so every
    one of them was rising sideways relative to the way you walk it — treads
    presenting as one flat striped plane, and the storey lift ramping across the
    direction of travel instead of along it.

    The honest answer is not a heuristic about the rectangle. It is which
    NEIGHBOUR is at the bottom and which is at the top: a flight climbs from the
    face touching its low storey toward the face touching its high one.

    Returns (axis, reverse), or None when the two ends are not on opposite faces —
    an L-shaped route that a single-axis flight cannot express. The caller warns
    rather than guessing, because a wrong axis here is invisible until someone
    watches a visitor gain height sideways.
    """
    lo, hi = _level_span(stair)
    if lo == hi:
        return None
    gx, gy, w, h = stair["rect"]
    faces = {
        "n": (gx + w * 0.5, gy - 0.5),
        "s": (gx + w * 0.5, gy + h + 0.5),
        "w": (gx - 0.5, gy + h * 0.5),
        "e": (gx + w + 0.5, gy + h * 0.5),
    }
    low_faces, high_faces = [], []
    for side, (px, py) in faces.items():
        for r in rooms:
            if r is stair:
                continue
            rx, ry, rw, rh = r["rect"]
            if rx <= px < rx + rw and ry <= py < ry + rh:
                rlo, rhi = _level_span(r)
                if rlo <= lo <= rhi:
                    low_faces.append(side)
                if rlo <= hi <= rhi:
                    high_faces.append(side)
                break
    for axis, neg, pos in (("y", "n", "s"), ("x", "w", "e")):
        if neg in high_faces and pos in low_faces:
            return (axis, True)      # climbs toward -axis
        if pos in high_faces and neg in low_faces:
            return (axis, False)     # climbs toward +axis
    return None


def bench_along_wall(rect, px, py, length, clear=0.34):
    """Place a bench against the nearest wall of its room, running WITH that wall.

    Furniture was scattered at free points with no notion of orientation, and a
    bench is the one piece where that shows: its footprint has a long axis, so an
    unoriented one ends up crossing a wall at right angles, jammed in a doorway, or
    stranded in the middle of a floor where nobody would ever put a bench. Reported
    as benches "literally in between walls" and one "attached to a wall".

    Real seating hugs the perimeter, which also declutters the middle of the room —
    the exact space visitors and exhibits need. Returns the overriding fields, or
    None if the bench will not fit along the chosen wall.
    """
    gx, gy, w, h = rect
    if w < length + 1.0 and h < length + 1.0:
        return None
    # Nearest wall wins, so the bench barely moves from where the scatter put it
    # and the spread across the room is preserved.
    sides = {
        "n": py - gy, "s": (gy + h) - py,
        "w": px - gx, "e": (gx + w) - px,
    }
    for side in sorted(sides, key=sides.get):
        if side in ("n", "s"):
            if w < length + 1.0:
                continue
            a = min(max(px - length * 0.5, gx + 0.5), gx + w - length - 0.5)
            across = gy + clear if side == "n" else gy + h - clear - 0.55
            at, axis = (a, across), "x"
        else:
            if h < length + 1.0:
                continue
            a = min(max(py - length * 0.5, gy + 0.5), gy + h - length - 0.5)
            across = gx + clear if side == "w" else gx + w - clear - 0.55
            at, axis = (across, a), "y"
        # Both ends have to be on camera, not just the anchor: the projection
        # shears x by -gy, so a bench can start on screen and finish off it.
        far = (at[0] + length, at[1]) if axis == "x" else (at[0], at[1] + length)
        if on_canvas(at[0], at[1], 22.0) and on_canvas(far[0], far[1], 22.0):
            return {"at": [round(at[0], 2), round(at[1], 2)], "axis": axis,
                    "len": round(length, 2)}
    return None


def terrace_props(rooms, rng, vocab, count, pad=1.0):
    """Furniture on the apron — paved ground inside the plinth but outside every
    room.

    A plan that follows the diamond is not a rectangle, so the plinth it stands on
    has notches: paved terrace beside the building rather than lawn. Left bare
    those read as an empty car park. Dressed with benches, planters and an
    outdoor piece they read as the forecourt of a real museum, which is what the
    space is for.

    Points are rejected unless they are (a) inside the plinth, (b) outside every
    room, and (c) on canvas with margin — the apron's outer corners are the first
    thing the projection throws off screen.
    """
    bx, by, bw, bh = bounds(rooms)
    out, taken = [], []
    attempts = 0
    while len(out) < count and attempts < count * 200:
        attempts += 1
        px = round(rng.uniform(bx - pad, bx + bw + pad), 2)
        py = round(rng.uniform(by - pad, by + bh + pad), 2)
        if covered(rooms, px, py) or covered(rooms, px, py + 0.5):
            continue
        if not on_canvas(px, py, 40.0):
            continue
        if any(abs(px - tx) < 1.3 and abs(py - ty) < 1.1 for tx, ty in taken):
            continue
        taken.append((px, py))
        kind = rng.choice(vocab)
        prop = {"kind": kind, "at": [px, py]}
        if kind == "bench":
            prop["len"] = round(rng.uniform(1.5, 2.1), 2)
            # Outdoor benches follow the apron they stand on: one on the north or
            # south terrace runs east-west, one on a side terrace runs with the
            # building. Without this they all ran x and the side aprons ended up
            # with benches lying across them.
            near_x = min(abs(px - bx), abs(px - (bx + bw)))
            near_y = min(abs(py - by), abs(py - (by + bh)))
            prop["axis"] = "y" if near_x < near_y else "x"
        prop.update(prop_palette(kind))
        out.append(prop)
    return out


def plaque_at(role, rect):
    """Where a room's name plaque hangs, in room-relative tiles.

    NOT the centre. Centred plaques were reported sitting on top of the staff:
    the middle of a room is exactly where the counters, the porters and the
    browsing crowd are, because every fixture is derived from the rect's centre
    line. Each role has a different quiet corner:

      queue   above the counters — the top edge is clear, the rest is lanes
      store   far LEFT — the drop, the pile and the gold stack are all bottom-right
      promo   top-left, clear of the desks on the centre line
      other   bottom-left, behind the browse spots
    """
    w, h = rect[2], rect[3]
    if role == "queue":
        return [round(min(1.6, w * 0.16), 2), 0.55]
    if role == "store":
        return [round(w * 0.20, 2), round(h - 0.9, 2)]
    if role == "promo":
        return [round(w * 0.22, 2), 0.85]
    return [round(w * 0.18, 2), round(h - 0.85, 2)]


def scatter_weighted(rooms, rng, vocab, blocked, per_tile=0.16):
    """Furniture spread across the plan in proportion to FLOOR AREA.

    Picking a room uniformly at random left the big halls bare and the small
    ones cluttered — the large empty stretches reported in the treasury and the
    sun court. Budgeting per tile puts the furniture where the space actually is.
    """
    out, taken = [], list(blocked)
    for r in rooms:
        gx, gy, w, h = r["rect"]
        role = r.get("role")
        kinds = vocab.get(role) or vocab.get("any")
        if not kinds or w < 2 or h < 2:
            continue
        # A room may ask for its own density. A lounge whose whole job is to look
        # occupied cannot sit at the same per-tile budget as a gallery whose job is
        # to leave sightlines to the exhibits: at the shared rate a 21-tile lounge
        # got two pieces of furniture and read as bare floor.
        want = max(1, int(round(w * h * float(r.get("prop_density", per_tile)))))
        attempts = 0
        placed = 0
        while placed < want and attempts < want * 50:
            attempts += 1
            px = round(rng.uniform(gx + 0.6, gx + w - 0.8), 2)
            py = round(rng.uniform(gy + 0.6, gy + h - 0.8), 2)
            if not on_canvas(px, py, 24.0):
                continue
            if any(abs(px - tx) < 1.1 and abs(py - ty) < 0.95 for tx, ty in taken):
                continue
            taken.append((px, py))
            kind = rng.choice(kinds)
            prop = {"kind": kind, "at": [px, py]}
            if kind == "bench":
                snapped = bench_along_wall(
                    r["rect"], px, py, round(rng.uniform(1.4, 2.0), 2))
                if snapped is None:
                    continue          # no wall it fits along; spend the slot elsewhere
                prop.update(snapped)
                taken[-1] = (prop["at"][0], prop["at"][1])
            prop.update(prop_palette(kind))
            out.append(prop)
            placed += 1
    return out
