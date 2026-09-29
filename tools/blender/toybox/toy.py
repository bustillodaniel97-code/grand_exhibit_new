"""Shared toolkit for the toy-diorama art pipeline (tools/blender/toybox/*).

Every generator in this folder builds glossy, rounded "toy" geometry in the
Link's Awakening (2019) spirit and exports glTF for the 3D venue scene
(scenes/venue3d). Import this module after putting its folder on sys.path.

AXES. Venue data is authored on a grid: gx grows right, gy grows toward the
viewer. Blender is Z-up and glTF is Y-up (x, z, -y), so a grid point is placed
at Blender (gx, -gy, height). It then lands in Godot at (gx, height, gy), with
the camera looking toward -Z from the gy-large side.
"""
import bpy
import math
import os
import random
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
ART3D = os.path.join(ROOT, "art3d")


def g2b(gx, gy, z=0.0):
    """Venue grid point -> Blender location."""
    return (gx, -gy, z)


# ------------------------------------------------------------------ scene
def reset():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.actions, bpy.data.armatures):
        for block in list(coll):
            if block.users == 0:
                coll.remove(block)
    _MATS.clear()


# ------------------------------------------------------------------ colour + materials
def srgb2lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexcol(h):
    h = h.lstrip("#")
    return tuple(srgb2lin(int(h[i:i + 2], 16) / 255) for i in (0, 2, 4)) + (1.0,)


def shade(h, k):
    """Scale a hex colour's brightness by k (0.8 = 20% darker), stays hex."""
    h = h.lstrip("#")
    rgb = [min(255, max(0, round(int(h[i:i + 2], 16) * k))) for i in (0, 2, 4)]
    return "#%02X%02X%02X" % tuple(rgb)


_MATS = {}


def mat(hexc, rough=0.4, metal=0.0, emit=0.0, alpha=1.0, name=None):
    """Cached Principled material. Only glTF-exportable inputs are used."""
    key = (hexc.upper(), round(rough, 3), round(metal, 3), round(emit, 3), round(alpha, 3))
    if key in _MATS:
        return _MATS[key]
    m = bpy.data.materials.new(name or f"toy_{hexc.lstrip('#')}_{int(rough * 100)}")
    b = m.node_tree.nodes.get("Principled BSDF")
    col = hexcol(hexc)
    b.inputs["Base Color"].default_value = col
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = col
        b.inputs["Emission Strength"].default_value = emit
    if alpha < 1.0:
        b.inputs["Alpha"].default_value = alpha
        m.surface_render_method = "BLENDED"
    m.diffuse_color = col
    _MATS[key] = m
    return m


# ------------------------------------------------------------------ primitives
def smooth(o):
    for p in o.data.polygons:
        p.use_smooth = True


def set_mat(o, m):
    o.data.materials.clear()
    o.data.materials.append(m)


def bevel(o, w, seg=3):
    b = o.modifiers.new("Bevel", "BEVEL")
    b.width = w
    b.segments = seg
    b.limit_method = "ANGLE"
    b.harden_normals = True


def _finish(o, m, bev=0.0, seg=3, flat=False, name=None):
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if bev:
        bevel(o, bev, seg)
    if not flat:
        smooth(o)
    if m:
        set_mat(o, m)
    if name:
        o.name = name
    return o


def box(size, loc, m, bev=0.0, rot=(0, 0, 0), seg=3, name=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.scale = size
    return _finish(o, m, bev, seg, flat=not bev, name=name)


def sphere(r, loc, m, scale=(1, 1, 1), seg=24, name=None):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=loc, segments=seg, ring_count=seg // 2)
    o = bpy.context.active_object
    o.scale = scale
    return _finish(o, m, name=name)


def cyl(r, depth, loc, m, r2=None, rot=(0, 0, 0), bev=0.02, verts=24, name=None):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, location=loc, rotation=rot, vertices=verts)
    else:
        bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=depth, location=loc, rotation=rot, vertices=verts)
    return _finish(bpy.context.active_object, m, bev, 2, name=name)


def rod(p1, p2, r, m, r2=None, verts=12, name=None):
    """Cylinder (or cone when r2 is given) spanning two points."""
    a, b = Vector(p1), Vector(p2)
    d = b - a
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_euler()
    return cyl(r, d.length, (a + b) / 2, m, r2=r2, rot=rot, bev=0, verts=verts, name=name)


def torus(R, r, loc, m, rot=(0, 0, 0), name=None):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, location=loc, rotation=rot,
                                     major_segments=32, minor_segments=12)
    return _finish(bpy.context.active_object, m, name=name)


def ico(r, loc, m, sub=2, jitter=0.0, scale=(1, 1, 1), rnd=None, name=None):
    rnd = rnd or random.Random(0)
    bpy.ops.mesh.primitive_ico_sphere_add(radius=r, location=(0, 0, 0), subdivisions=sub)
    o = bpy.context.active_object
    for v in o.data.vertices:
        v.co += Vector([rnd.uniform(-jitter, jitter) for _ in range(3)])
    o.scale = scale
    o.location = loc
    return _finish(o, m, name=name)


def mesh_from(verts, faces, loc, m, bev=0.0, name="mesh"):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.validate()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    if bev:
        bevel(o, bev)
    smooth(o)
    set_mat(o, m)
    return o


def prism(w, d, h, loc, m, bev=0.06, name="prism"):
    """Gable roof wedge: ridge along X, eaves at +-d/2, height h."""
    x, y = w / 2, d / 2
    verts = [(-x, -y, 0), (x, -y, 0), (x, y, 0), (-x, y, 0), (-x, 0, h), (x, 0, h)]
    faces = [(0, 3, 2, 1), (0, 1, 5, 4), (2, 3, 4, 5), (0, 4, 3), (1, 2, 5)]
    return mesh_from(verts, faces, loc, m, bev, name)


# ------------------------------------------------------------------ assembly + export
def apply_mods(o):
    bpy.context.view_layer.objects.active = o
    for mod in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)


def join(objs, name):
    objs = [o for o in objs if o is not None]
    for o in objs:
        apply_mods(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    return o


def parent_all(objs, name, loc=(0, 0, 0)):
    root = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(root)
    root.location = loc
    for o in objs:
        o.parent = root
        o.matrix_parent_inverse = root.matrix_world.inverted()
    return root


def export_glb(path, objects=None, animations=False):
    """Export `objects` (default: everything) to a .glb, modifiers applied."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    targets = objects if objects is not None else list(bpy.context.scene.objects)
    for o in targets:
        o.select_set(True)
        for c in o.children_recursive:
            c.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_apply=True,
        export_yup=True, export_animations=animations, export_lights=False, export_cameras=False,
        export_extras=True)
    print("EXPORTED", os.path.relpath(path, ROOT))


# ------------------------------------------------------------------ preview renders
def preview(path, target=(0, 0, 0), dist=20.0, tilt_deg=40.0, lens=50, res=(1080, 1350), fstop=0.0,
            sun_rot=(40, 0, -30)):
    """Quick EEVEE still for eyeballing an asset from the game's camera angle."""
    scene = bpy.context.scene
    world = bpy.data.worlds.new("sky")
    scene.world = world
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = hexcol("#cfe8ff")
    bg.inputs["Strength"].default_value = 0.9
    sd = bpy.data.lights.new("sun", "SUN")
    sd.energy, sd.angle, sd.color = 4.0, math.radians(4), (1.0, 0.96, 0.9)
    sun = bpy.data.objects.new("sun", sd)
    sun.rotation_euler = tuple(math.radians(a) for a in sun_rot)
    scene.collection.objects.link(sun)
    cd = bpy.data.cameras.new("cam")
    cd.lens = lens
    cam = bpy.data.objects.new("cam", cd)
    scene.collection.objects.link(cam)
    t = math.radians(tilt_deg)
    tgt = Vector(target)
    cam.location = tgt + Vector((0, -dist * math.sin(t), dist * math.cos(t)))
    cam.rotation_euler = (t, 0, 0)
    scene.camera = cam
    if fstop:
        cd.dof.use_dof = True
        cd.dof.focus_distance = dist
        cd.dof.aperture_fstop = fstop
    scene.render.engine = "BLENDER_EEVEE"
    scene.eevee.taa_render_samples = 32
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.view_settings.view_transform = "AgX"
    try:
        scene.view_settings.look = "AgX - Punchy"
    except Exception:
        pass
    os.makedirs(os.path.dirname(path), exist_ok=True)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    for o in (sun, cam):
        bpy.data.objects.remove(o)
    print("PREVIEW", os.path.relpath(path, ROOT))
