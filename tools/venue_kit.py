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

def derive_walls(rooms, colour_of):
    """A back wall wherever a room's north or west edge faces open air.

    Derived rather than authored because a wall that does not match the plan is
    the single most obvious way a venue looks broken, and hand-listing them is
    where that mismatch comes from. Runs are merged so a shared edge across two
    rooms is one wall, not two abutting stubs.
    """
    walls = []
    for r in rooms:
        gx, gy, w, h = r["rect"]
        col = colour_of(r)
        # North face: any span along the top edge with nothing above it.
        run = None
        for i in range(w):
            open_air = not covered(rooms, gx + i + 0.5, gy - 0.5)
            if open_air and run is None:
                run = gx + i
            elif not open_air and run is not None:
                walls.append({"at": [run, gy], "len": gx + i - run, "axis": "x",
                              "col": f"{col}|d10"})
                run = None
        if run is not None:
            walls.append({"at": [run, gy], "len": gx + w - run, "axis": "x",
                          "col": f"{col}|d10"})
        # West face.
        run = None
        for i in range(h):
            open_air = not covered(rooms, gx - 0.5, gy + i + 0.5)
            if open_air and run is None:
                run = gy + i
            elif not open_air and run is not None:
                walls.append({"at": [gx, run], "len": gy + i - run, "axis": "y",
                              "col": f"{col}|d22"})
                run = None
        if run is not None:
            walls.append({"at": [gx, run], "len": gy + h - run, "axis": "y",
                          "col": f"{col}|d22"})
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
