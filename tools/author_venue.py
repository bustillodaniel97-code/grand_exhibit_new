#!/usr/bin/env python3
"""Venue theme authoring harness.

WHY THIS EXISTS. A venue theme is ~10-13KB of hand-shaped JSON, and two classes
of mistake in it are invisible until someone renders the venue and squints:

  1. OFF-CANVAS GEOMETRY. The visible floor is a DIAMOND in grid space, not a
     rectangle — the projection shears x by -gy, so the low-gx / high-gy corner
     runs past the clipped left edge. A plan that looks generous on paper can put
     a whole wing, or a forecourt, where nobody will ever see it. That has
     already happened once.
  2. SHAPE MISMATCH. `dressing` is a Dictionary keyed by BAND
     (carpet/floor/wall/ceiling). Authored as a flat list it casts to null and the
     entire block silently does not draw. That has also already happened once.

So every plan goes through validate() before it is written, and both mistakes
become a hard error at authoring time instead of a mystery at render time.

Usage:  python3 tools/author_venue.py           # validates + writes all themes
        python3 tools/author_venue.py --check    # validate only, write nothing
"""

import json
import collections
import sys

REPO = "/data/dev/godot-saga/repo"
VENUES = f"{REPO}/data/venues.json"

# --- projection, mirrored from scenes/venue/floor/iso.gd ---------------------
ORIGIN = (390.0, 80.0)
TILE = (60.0, 40.0)
VIEW = (720.0, 760.0)
MARGIN = 26.0


def screen(gx, gy):
    return (ORIGIN[0] + (gx - gy) * TILE[0] * 0.5,
            ORIGIN[1] + (gx + gy) * TILE[1] * 0.5)


def on_canvas(gx, gy):
    x, y = screen(gx, gy)
    return MARGIN <= x <= VIEW[0] - MARGIN and MARGIN <= y <= VIEW[1] - MARGIN


# Kinds registered in scenes/venue/floor/exhibits.gd. Kept here so a typo in a
# theme is caught while authoring rather than by the runtime suite.
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


def OD(*kv):
    return collections.OrderedDict(kv)


def validate(vid, theme):
    """Raise on anything that would render wrong or not at all."""
    errs = []

    rooms = theme.get("rooms", [])
    roles = {r.get("role") for r in rooms}
    missing = ROLES_REQUIRED - roles
    if missing:
        errs.append(f"missing load-bearing role(s): {sorted(missing)}")

    # Every room corner must be inside the visible diamond, or part of the
    # building is drawn where the canvas is clipped away.
    for r in rooms:
        gx, gy, w, h = r["rect"]
        for cx, cy in ((gx, gy), (gx + w, gy), (gx, gy + h), (gx + w, gy + h)):
            if not on_canvas(cx, cy):
                errs.append(
                    f"room '{r['id']}' corner ({cx},{cy}) is off-canvas "
                    f"-> screen {tuple(round(v) for v in screen(cx, cy))}")
                break

    # Rooms must not overlap: two floors drawn on the same tile z-fight and the
    # queue derivation picks whichever it finds first.
    for i, a in enumerate(rooms):
        ax, ay, aw, ah = a["rect"]
        for b in rooms[i + 1:]:
            bx, by, bw, bh = b["rect"]
            if ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah:
                errs.append(f"rooms '{a['id']}' and '{b['id']}' overlap")

    # Anchors: props and exhibits Y-sort at their anchor, so an off-canvas anchor
    # is an invisible object even when its footprint is on screen.
    for group in ("exhibits", "props"):
        for item in theme.get(group, []):
            if item.get("kind") not in KINDS:
                errs.append(f"{group}: unregistered kind '{item.get('kind')}'")
            a = item.get("anchor")
            if a and not on_canvas(a[0], a[1]):
                errs.append(f"{group} '{item.get('kind')}' anchor {a} is off-canvas")

    # dressing must be banded, not a flat list.
    dressing = theme.get("dressing")
    if not isinstance(dressing, dict):
        errs.append("dressing must be a Dictionary keyed by band "
                    "(carpet/floor/wall/ceiling), not a list")
    else:
        for band in dressing:
            if band not in BANDS:
                errs.append(f"dressing: unknown band '{band}'")
        for band, items in dressing.items():
            for it in items:
                if it.get("kind") not in KINDS:
                    errs.append(f"dressing.{band}: unregistered kind '{it.get('kind')}'")

    if not theme.get("surround"):
        errs.append("no surround style named")

    if errs:
        raise SystemExit(f"\n{vid} FAILED validation:\n  " + "\n  ".join(errs))
    return True


def load():
    with open(VENUES) as f:
        return json.load(f, object_pairs_hook=collections.OrderedDict)


def save(doc):
    with open(VENUES, "w") as f:
        json.dump(doc, f, indent=2)


def apply_theme(doc, vid, name, theme):
    validate(vid, theme)
    for v in doc["venues"]:
        if v["id"] == vid:
            if name:
                v["name"] = name
            v["theme"] = theme
            return
    raise SystemExit(f"venue id '{vid}' not found")


def summarise(doc):
    print(f"{'venue':<18} {'rooms':>5} {'exh':>4} {'props':>6} {'dress':>6}  surround")
    for v in doc["venues"]:
        t = v.get("theme", {})
        if "extends" in t:
            print(f"  {v['id']:<16} {'—':>5} {'—':>4} {'—':>6} {'—':>6}  extends {t['extends']}")
            continue
        dr = sum(len(x) for x in t.get("dressing", {}).values())
        print(f"  {v['id']:<16} {len(t.get('rooms', [])):>5} {len(t.get('exhibits', [])):>4} "
              f"{len(t.get('props', [])):>6} {dr:>6}  {t.get('surround')}")


if __name__ == "__main__":
    doc = load()
    summarise(doc)
    print("\nEnvelope: gx-gy must stay within [-11, 9]; gx+gy within [0, 30].")
