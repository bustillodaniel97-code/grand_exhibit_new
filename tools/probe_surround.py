#!/usr/bin/env python3
"""Does any surround scenery land inside a venue's rooms after the footprint remap?

Mirrors City._g() and the STYLES table so the answer is available while authoring
a plan, instead of after rendering it and squinting at the result.
"""
import json
import re
import sys

REPO = "/home/bustillo/godot-saga/repo"
NOMINAL = (0.0, 0.0, 15.0, 17.0)   # x, y, w, h


def remap(c, n0, n1, b0, b1):
    if c <= n0:
        return b0 + (c - n0)
    if c >= n1:
        return b1 + (c - n1)
    return b0 + (c - n0) / (n1 - n0) * (b1 - b0)


def g(pt, fp):
    nx, ny, nw, nh = NOMINAL
    bx, by, bw, bh = fp
    return (remap(pt[0], nx, nx + nw, bx, bx + bw),
            remap(pt[1], ny, ny + nh, by, by + bh))


def parse_styles():
    """Pull the scenery arrays straight out of city.gd so this cannot drift."""
    src = open(f"{REPO}/scenes/venue/floor/city.gd").read()
    styles = {}
    for name in re.findall(r'^\t"(\w+)": \{', src, re.M):
        styles[name] = {}
    # Grab each `"key": [ ... ],` list inside each style block.
    blocks = re.split(r'^\t"(\w+)": \{', src, flags=re.M)
    for i in range(1, len(blocks), 2):
        name, body = blocks[i], blocks[i + 1]
        for key in ("blocks", "trees", "pines", "hedges", "near_trees",
                    "planters", "lamps", "fences"):
            m = re.search(r'"%s": (\[.*?\]),\n' % key, body, re.S)
            if not m:
                continue
            try:
                styles[name][key] = json.loads(m.group(1).replace("\n", " "))
            except json.JSONDecodeError:
                pass
    return styles


def points(style_def):
    """Every ground contact point a style plants, as (label, gx, gy)."""
    out = []
    for b in style_def.get("blocks", []):
        out.append(("block", b[0], b[1]))
        out.append(("block", b[0] + b[2], b[1] + b[3]))
    for key in ("trees", "pines", "near_trees"):
        for t in style_def.get(key, []):
            out.append((key[:-1], t[0], t[1]))
    for h in style_def.get("hedges", []):
        # Sample the run: an endpoint test misses a hedge that crosses a wing.
        for k in range(9):
            f = k / 8.0
            out.append(("hedge", h[0] + (h[2] - h[0]) * f, h[1] + (h[3] - h[1]) * f))
    for key in ("planters", "lamps"):
        for p in style_def.get(key, []):
            out.append((key[:-1], p[0], p[1]))
    return out


def main():
    styles = parse_styles()
    doc = json.load(open(f"{REPO}/data/venues.json"))
    bad = 0
    for v in doc["venues"]:
        t = v.get("theme", {})
        if "extends" in t or not t.get("rooms"):
            continue
        rooms = [r["rect"] for r in t["rooms"]]
        xs = [r[0] for r in rooms] + [r[0] + r[2] for r in rooms]
        ys = [r[1] for r in rooms] + [r[1] + r[3] for r in rooms]
        fp = (min(xs), min(ys), max(xs) - min(xs), max(ys) - min(ys))
        sd = styles.get(t.get("surround", "parkland"), {})
        hits = []
        for label, px, py in points(sd):
            qx, qy = g((px, py), fp)
            for r in rooms:
                # A quarter tile of slack. Any more and the deliberate forecourt
                # planters — which stand ~0.35 outside the lobby's front wall,
                # flanking the doors — read as intrusions.
                if (r[0] - 0.25 <= qx <= r[0] + r[2] + 0.25
                        and r[1] - 0.25 <= qy <= r[1] + r[3] + 0.25):
                    hits.append(f"{label} at ({qx:.1f},{qy:.1f})")
                    break
        state = "CLEAN" if not hits else f"{len(hits)} INTRUSIONS"
        print(f"{v['id']:<18} fp={tuple(round(f,1) for f in fp)}  {state}")
        for h in hits[:6]:
            print(f"    {h}")
        bad += len(hits)
    print(f"\ntotal intrusions: {bad}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
