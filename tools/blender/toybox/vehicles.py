"""Toy vehicles -> art3d/vehicles/{car,bus}.glb

    blender -b --factory-startup --python tools/blender/toybox/vehicles.py

Long axis X, front at +X. The body is one node and each wheel is its own node
named wheel_* so the game can spin them. The body material is named "paint" so
one car model gives every colour on the road.
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import toy  # noqa: E402
from toy import box, cyl, sphere, mat  # noqa: E402


def paint(hexc):
    m = bpy.data.materials.get("paint") or bpy.data.materials.new("paint")
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = toy.hexcol(hexc)
    b.inputs["Roughness"].default_value = 0.6
    return m


def wheels(xs, half_track, r, name_prefix="wheel"):
    out = []
    for i, x in enumerate(xs):
        for side, y in (("L", half_track), ("R", -half_track)):
            tyre = cyl(r, 0.14, (x, y, r), mat("#22252B", 0.6), rot=(math.pi / 2, 0, 0), bev=0.03)
            hub = cyl(r * 0.45, 0.16, (x, y, r), mat("#D8DEE6", 0.3, metal=0.5), rot=(math.pi / 2, 0, 0), bev=0.01)
            w = toy.join([tyre, hub], f"{name_prefix}_{i}{side}")
            out.append(w)
    return out


def car():
    body = [box((1.3, 0.62, 0.3), (0, 0, 0.3), paint("#D9413A"), bev=0.12),
            box((0.7, 0.54, 0.28), (-0.08, 0, 0.55), paint("#D9413A"), bev=0.12),
            box((0.66, 0.56, 0.2), (-0.08, 0, 0.56), mat("#9FD8FF", 0.05), bev=0.06),
            box((0.04, 0.5, 0.08), (0.66, 0, 0.32), mat("#FFF4D6", 0.2, emit=0.8), bev=0.02),
            box((0.04, 0.5, 0.06), (-0.66, 0, 0.34), mat("#FF4D4D", 0.2, emit=0.6), bev=0.02)]
    b = toy.join(body, "body")
    return [b] + wheels((0.42, -0.42), 0.28, 0.15)


def bus():
    yellow = paint("#F2B632")
    body = [box((3.0, 0.9, 0.9), (0, 0, 0.62), yellow, bev=0.16),
            box((3.02, 0.92, 0.1), (0, 0, 0.36), mat("#2F7FD1", 0.3), bev=0.04),
            box((2.2, 0.94, 0.3), (-0.25, 0, 0.82), mat("#9FD8FF", 0.05), bev=0.06),
            box((0.06, 0.8, 0.34), (1.5, 0, 0.8), mat("#9FD8FF", 0.05), bev=0.04),
            box((0.05, 0.3, 0.12), (1.52, 0, 0.35), mat("#FFF4D6", 0.2, emit=0.8), bev=0.02),
            box((2.6, 0.7, 0.08), (0, 0, 1.1), mat("#FFF4E0", 0.4), bev=0.04)]
    for x in (-0.9, 0.0, 0.9):
        body.append(box((0.05, 0.94, 0.34), (x, 0, 0.82), yellow))
    b = toy.join(body, "body")
    return [b] + wheels((1.0, -1.0), 0.42, 0.19)


def export(name, parts):
    root = toy.parent_all(parts, name)
    toy.export_glb(os.path.join(toy.ART3D, "vehicles", f"{name}.glb"), [root])


if __name__ == "__main__":
    toy.reset()
    export("car", car())
    toy.reset()
    export("bus", bus())
