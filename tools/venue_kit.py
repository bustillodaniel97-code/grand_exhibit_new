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
    "hung_skeleton", "touch_pool", "mural", "plinth",
    "counter", "info_desk", "desk", "vault_door", "facade", "kiosk", "shelf",
    "rope_line",
    "bench", "planter", "kelp", "bin", "rack", "cabinet", "crate", "trolley",
    "machine", "banner", "balloons",
    "rug", "patch", "picture", "porthole", "notice", "poster", "bunting",
}
ROLES_REQUIRED = {"queue", "store", "promo", "exhibit", "lobby"}
BANDS = ("carpet", "floor", "wall", "ceiling")


def screen(gx, gy):
    return (ORIGIN[0] + (gx - gy) * HALF[0], ORIGIN[1] + (gx + gy) * HALF[1])


def on_canvas(gx, gy, margin=10.0):
    x, y = screen(gx, gy)
    return margin <= x <= VIEW[0] - margin and margin <= y <= VIEW[1] - margin


def clip_fraction(rect):
    """Fraction of a room's floor area falling off the canvas."""
    gx, gy, w, h = rect
    n = bad = 0
    yy = gy + 0.25
    while yy < gy + h:
        xx = gx + 0.25
        while xx < gx + w:
            n += 1
            if not on_canvas(xx, yy):
                bad += 1
            xx += 0.5
        yy += 0.5
    return (bad / n) if n else 0.0


# --- validation ---------------------------------------------------------------

def validate(vid, theme, strict=True):
    """Return warnings; raise on anything that would render wrong or not at all."""
    errs, warns = [], []
    rooms = theme.get("rooms", [])

    missing = ROLES_REQUIRED - {r.get("role") for r in rooms}
    if missing:
        errs.append(f"missing load-bearing role(s): {sorted(missing)}")

    total = bad = 0.0
    for r in rooms:
        gx, gy, w, h = r["rect"]
        frac = clip_fraction(r["rect"])
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


def bounds(rooms):
    xs = [r["rect"][0] for r in rooms] + [r["rect"][0] + r["rect"][2] for r in rooms]
    ys = [r["rect"][1] for r in rooms] + [r["rect"][1] + r["rect"][3] for r in rooms]
    return (min(xs), min(ys), max(xs) - min(xs), max(ys) - min(ys))


# --- derivation ---------------------------------------------------------------

def derive_walls(rooms, colour_of, partition="@partition",
                 exterior_h=None, interior_h=46.0):
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

    def emit(at, length, axis, interior):
        if length <= 0:
            return
        # Exteriors take the room's own accent, shaded by which way the face
        # turns: north catches the key light, west is turned away from it.
        shade = "|d10" if axis == "x" else "|d22"
        col = partition if interior else colour_of_edge + shade
        entry = {"at": [round(at[0], 2), round(at[1], 2)],
                 "len": round(length, 2), "axis": axis, "col": col}
        if interior:
            entry["h"] = interior_h
        elif exterior_h is not None:
            entry["h"] = exterior_h
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
        # North face, cell by cell: is there a room on the far side of it?
        cells = [(gx + i, covered(rooms, gx + i + 0.5, gy - 0.5)) for i in range(w)]
        for start, length, interior in runs(cells):
            if interior:
                for s0, ln in with_doorway(start, length):
                    emit((s0, gy), ln, "x", True)
            else:
                emit((start, gy), length, "x", False)
        # West face.
        cells = [(gy + j, covered(rooms, gx - 0.5, gy + j + 0.5)) for j in range(h)]
        for start, length, interior in runs(cells):
            if interior:
                for s0, ln in with_doorway(start, length):
                    emit((gx, s0), ln, "y", True)
            else:
                emit((gx, start), length, "y", False)

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
        want = max(1, int(round(w * h * per_tile)))
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
                prop["len"] = round(rng.uniform(1.4, 2.0), 2)
            out.append(prop)
            placed += 1
    return out
