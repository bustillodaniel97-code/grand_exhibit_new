# Procedural chibi cast, modelled and rendered in Blender.
#
# Run headless:
#   blender -b -P tools/blender/make_cast.py -- --out /abs/dir [--frames 6] [--look 0]
#
# WHY THIS EXISTS. The in-engine cast is drawn with 2D canvas primitives and baked
# to supersampled textures. That reads well in silhouette but it is flat: there is
# no real form, no cast shadow, and no way to get a consistent three-quarter view
# of a head. This pipeline builds the same character as low-poly geometry, lights
# it once, and renders it from the exact camera the game's isometric projection
# implies — so the sprite agrees with the floor it stands on instead of
# approximating it.
#
# WHY GENERATED RATHER THAN A DOWNLOADED MODEL. Every prop, room and surround in
# this game is procedural and parametric. A bought or CC0 rig would import a
# second visual language, fix the proportions we tune, and put a licence on the
# critical path. Generating means skin, hair, build and department uniform stay
# variables, which is what the bake cache and the manager portraits both need.
#
# THE CAMERA IS NOT ARBITRARY. scenes/venue/floor/iso.gd projects
#     screen = ((gx - gy) * TILE.x/2, (gx + gy) * TILE.y/2)   TILE = (60, 40)
# so a ground-plane axis moves 30px across for every 20px down: a ratio of 2/3.
# For an orthographic camera at azimuth 45, that ratio IS sin(elevation), giving
# asin(2/3) = 41.81 degrees. Classic 2:1 isometric would be 30 degrees; using it
# here would leave every sprite subtly disagreeing with the floor.

import bpy
import bmesh
import math
import os
import sys
from mathutils import Vector

# --- projection, mirrored from iso.gd ---------------------------------------
TILE_X, TILE_Y = 60.0, 40.0
# The FLOOR's implied elevation. Kept for reference and for prop rendering.
FLOOR_ELEVATION = math.asin(TILE_Y / TILE_X)      # 41.81 deg
# The CHARACTER camera is deliberately shallower. At the floor's true 41.8 degrees
# a chibi presents mostly scalp — the head is the largest mass and you are looking
# down onto it, so the face falls away and every figure reads as a coloured blob.
# Stylised isometric games cheat exactly here: characters are billboards and do not
# have to obey the ground plane's camera. Dropping to 24 degrees keeps the feet
# planted while turning the face back toward the viewer.
CHAR_ELEVATION = math.radians(24.0)
AZIMUTH = math.radians(45.0)

# --- sprite contract, mirrored from character_baker.gd -----------------------
# The baker stores at 2x the 48x64 design footprint and blits at half size, so
# matching it here makes these a drop-in replacement rather than a re-layout.
SPRITE_W, SPRITE_H = 96, 128
SUPERSAMPLE = 2                              # render big, let Godot's import filter
OUTLINE_MM = 0.018                           # inverted-hull thickness, world units

# --- look palettes, mirrored from character.gd -------------------------------
SKIN = ["F8D8B0", "EFC094", "D9A170", "B87B4C", "8E5733", "66412A"]
HAIR = ["2B2320", "4E3524", "7C5228", "C79A45", "B5AFA8", "8A3A2C", "42304E"]
SHIRT = ["4E7FB5", "C85A5A", "5FA86E", "D19A3E", "7A6BB5", "4FA3A5", "C77BA6", "5C6B8A"]
PANTS = ["3A3F4A", "5A4A3A", "44546A", "4A3F52"]
BUILDS = [0.91, 1.0, 1.09]
HAIR_STYLES = 8
OUTLINE_RGB = "3A2A1F"


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_rgba(h, a=1.0):
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    return (srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b), a)


def wipe_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def flat_material(name, hex_colour):
    """Unlit-ish toon fill. Emission carries the base colour so the sprite keeps
    the palette exactly as authored; a weak diffuse adds just enough form that
    the head is not a disc. Full PBR would fight the flat-shaded environment."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    mix = nt.nodes.new("ShaderNodeMixShader")
    emit = nt.nodes.new("ShaderNodeEmission")
    diff = nt.nodes.new("ShaderNodeBsdfDiffuse")
    col = hex_rgba(hex_colour)
    emit.inputs["Color"].default_value = col
    diff.inputs["Color"].default_value = col
    mix.inputs["Fac"].default_value = 0.45      # 55% flat fill, 45% shaded
    nt.links.new(emit.outputs[0], mix.inputs[1])
    nt.links.new(diff.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    return mat


def outline_material():
    mat = bpy.data.materials.new("outline")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Color"].default_value = hex_rgba(OUTLINE_RGB)
    nt.links.new(emit.outputs[0], out.inputs["Surface"])
    mat.use_backface_culling = True
    return mat


def set_pivot(ob, pivot):
    """Move the object origin to `pivot` without moving the mesh in world space, so
    a later rotation_euler swings the part about the joint instead of about its own
    centre. Hand-rolling that rotation on ob.location is what detached the arms."""
    from mathutils import Matrix
    delta = ob.location - Vector(pivot)
    ob.data.transform(Matrix.Translation(delta))
    ob.location = Vector(pivot)


def add_box(name, size, loc, mat, bevel=0.012):
    """Rounded low-poly box. Bevelled because a hard-edged cube reads as
    programmer art at sprite size — the same lesson the 2D cast already learned."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = Vector(size) * 0.5
    bpy.ops.object.transform_apply(scale=True)
    m = ob.modifiers.new("bevel", "BEVEL")
    m.width = bevel
    m.segments = 2
    m.limit_method = "ANGLE"
    ob.data.materials.append(mat)
    for p in ob.data.polygons:
        p.use_smooth = False
    return ob


def add_sphere(name, radius, loc, mat, squash=1.0):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=loc, segments=20, ring_count=12)
    ob = bpy.context.active_object
    ob.name = name
    ob.scale.z = squash
    bpy.ops.object.transform_apply(scale=True)
    ob.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return ob


def add_outline_shell(objects, mat):
    """Inverted-hull outline: a slightly fattened copy with flipped normals and a
    backface-culled emission material. Chosen over Freestyle because it renders in
    Eevee at full speed and its width is uniform in world units, so every sprite
    in the atlas gets the same weight of line."""
    shells = []
    for ob in objects:
        dup = ob.copy()
        dup.data = ob.data.copy()
        dup.name = ob.name + "_outline"
        bpy.context.collection.objects.link(dup)
        dup.data.materials.clear()
        dup.data.materials.append(mat)
        sol = dup.modifiers.new("shell", "SOLIDIFY")
        sol.thickness = OUTLINE_MM
        sol.offset = 1.0
        sol.use_flip_normals = True
        shells.append(dup)
    return shells


def build_character(look):
    """One chibi, in Blender units where 1.0 == the character's full height."""
    skin = flat_material("skin", look["skin"])
    hair = flat_material("hair", look["hair"])
    shirt = flat_material("shirt", look["shirt"])
    pants = flat_material("pants", look["pants"])
    shoe = flat_material("shoe", "3B2E26")
    ink = flat_material("ink", "4A3728")

    w = look["build"]
    parts, limbs = [], {}

    # Legs. Kept short and wide: chibi proportion is head-dominant, and thin legs
    # vanish entirely once the sprite is minified onto a phone.
    for side, sx in (("l", -1.0), ("r", 1.0)):
        leg = add_box(f"leg_{side}", (0.095 * w, 0.095, 0.26), (sx * 0.062 * w, 0.0, 0.13), pants)
        foot = add_box(f"foot_{side}", (0.115 * w, 0.15, 0.06), (sx * 0.062 * w, -0.018, 0.03), shoe)
        for part in (leg, foot):
            set_pivot(part, (sx * 0.062 * w, 0.0, 0.26))     # hip
        limbs[f"leg_{side}"] = [leg, foot]
        parts += [leg, foot]

    torso = add_box("torso", (0.30 * w, 0.17, 0.30), (0.0, 0.0, 0.41), shirt)
    parts.append(torso)

    for side, sx in (("l", -1.0), ("r", 1.0)):
        arm = add_box(f"arm_{side}", (0.075 * w, 0.075, 0.22), (sx * 0.187 * w, 0.0, 0.42), shirt)
        hand = add_sphere(f"hand_{side}", 0.047, (sx * 0.187 * w, 0.0, 0.30), skin)
        for part in (arm, hand):
            set_pivot(part, (sx * 0.187 * w, 0.0, 0.53))     # shoulder
        limbs[f"arm_{side}"] = [arm, hand]
        parts += [arm, hand]

    head_z = 0.70
    head = add_sphere("head", 0.145, (0.0, 0.0, head_z), skin, squash=0.95)
    parts.append(head)

    # Hair as a skull cap plus per-style masses. Silhouette is the only thing that
    # survives minification, so every style has to change the outline, not just
    # the shading — the 2D pass learned this the hard way when eight "styles" all
    # hugged the skull and read as one haircut in eight colours.
    # Cap sits back and high so it frames the face rather than swallowing it.
    cap = add_sphere("hair_cap", 0.152, (0.0, 0.022, head_z + 0.030), hair, squash=0.80)
    parts.append(cap)
    style = look["hair_style"]
    if style == 1:
        parts.append(add_sphere("fringe", 0.075, (0.0, -0.115, head_z + 0.045), hair, squash=0.7))
    elif style == 2:
        parts.append(add_sphere("bun", 0.078, (0.0, 0.10, head_z + 0.115), hair))
    elif style == 3:
        for sx in (-1.0, 1.0):
            parts.append(add_sphere(f"bob_{sx}", 0.062, (sx * 0.135, 0.02, head_z - 0.045), hair, squash=1.5))
    elif style == 4:
        for i, (dx, dy, dz) in enumerate(((-0.11, 0.03, 0.10), (0.0, 0.06, 0.14), (0.11, 0.03, 0.10))):
            parts.append(add_sphere(f"curl{i}", 0.072, (dx, dy, head_z + dz), hair))
    elif style == 5:
        parts.append(add_sphere("stack", 0.088, (0.0, 0.02, head_z + 0.135), hair, squash=0.8))
    elif style == 6:
        parts.append(add_sphere("tail", 0.070, (0.0, 0.155, head_z + 0.02), hair, squash=1.7))
    elif style == 7:
        for sx in (-1.0, 1.0):
            parts.append(add_sphere(f"twin_{sx}", 0.060, (sx * 0.145, 0.09, head_z + 0.05), hair))

    # Face. Placed on -Y, which is the camera-facing side after the 45 azimuth.
    for sx in (-1.0, 1.0):
        parts.append(add_sphere(f"eye_{sx}", 0.024, (sx * 0.052, -0.131, head_z + 0.012), ink, squash=1.3))

    if look.get("uniform"):
        uni = flat_material("uniform", look["uniform"])
        parts.append(add_box("cap_crown", (0.30, 0.28, 0.075), (0.0, 0.01, head_z + 0.145), uni))
        parts.append(add_box("cap_peak", (0.27, 0.15, 0.022), (0.0, -0.155, head_z + 0.115), uni))
        parts.append(add_box("sash", (0.28 * w, 0.16, 0.035), (0.0, 0.0, 0.335), uni))

    return parts, limbs


def pose_walk(limbs, phase):
    """Counter-rotating limbs about hip and shoulder joints. Origins were already
    moved to those joints by set_pivot, so this is a plain rotation."""
    swing = math.sin(phase) * 0.40
    for key, sign in (("leg_l", 1.0), ("leg_r", -1.0), ("arm_l", -1.0), ("arm_r", 1.0)):
        for ob in limbs[key]:
            ob.rotation_euler = (swing * sign, 0.0, 0.0)


def setup_world_and_camera():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.film_transparent = True
    scene.render.resolution_x = SPRITE_W * SUPERSAMPLE
    scene.render.resolution_y = SPRITE_H * SUPERSAMPLE
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    try:
        scene.eevee.taa_render_samples = 64
    except AttributeError:
        pass

    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    # Frame the full figure with a little headroom; height 1.0 in world units.
    cam_data.ortho_scale = 1.15
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)
    d = 6.0
    cam.location = (
        d * math.cos(CHAR_ELEVATION) * math.sin(AZIMUTH),
        -d * math.cos(CHAR_ELEVATION) * math.cos(AZIMUTH),
        d * math.sin(CHAR_ELEVATION) + 0.34,
    )
    cam.rotation_euler = (math.pi / 2 - CHAR_ELEVATION, 0.0, AZIMUTH)
    scene.camera = cam

    # Key from the upper left, matching the 2D art's stated light direction, plus
    # a soft fill so the unlit side does not crush to black.
    key = bpy.data.lights.new("key", "SUN")
    key.energy = 2.6
    key_ob = bpy.data.objects.new("key", key)
    key_ob.rotation_euler = (math.radians(52), 0.0, math.radians(-35))
    bpy.context.collection.objects.link(key_ob)

    fill = bpy.data.lights.new("fill", "SUN")
    fill.energy = 1.1
    fill_ob = bpy.data.objects.new("fill", fill)
    fill_ob.rotation_euler = (math.radians(70), 0.0, math.radians(150))
    bpy.context.collection.objects.link(fill_ob)

    bpy.context.scene.world = bpy.data.worlds.new("w")
    bpy.context.scene.world.use_nodes = True
    bg = bpy.context.scene.world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (1.0, 1.0, 1.0, 1.0)
    bg.inputs[1].default_value = 0.28


def look_for_slot(slot, uniform=None):
    """Strided so each slot is a distinct combination rather than a random draw —
    same reasoning as character.gd, where a shared RNG made hair colour and style
    move together and the crowd read as clones."""
    return {
        "skin": SKIN[(slot * 5) % len(SKIN)],
        "hair": HAIR[(slot * 3) % len(HAIR)],
        "shirt": SHIRT[(slot * 5) % len(SHIRT)],
        "pants": PANTS[(slot * 3) % len(PANTS)],
        "hair_style": slot % HAIR_STYLES,
        "build": BUILDS[(slot // HAIR_STYLES) % len(BUILDS)],
        "uniform": uniform,
    }


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = "/tmp/cast"
    frames = 6
    slot = 0
    uniform = None
    outline = 1
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--out":
            out_dir = argv[i + 1]; i += 2
        elif a == "--frames":
            frames = int(argv[i + 1]); i += 2
        elif a == "--look":
            slot = int(argv[i + 1]); i += 2
        elif a == "--uniform":
            uniform = argv[i + 1]; i += 2
        elif a == "--outline":
            outline = int(argv[i + 1]); i += 2
        else:
            i += 1

    os.makedirs(out_dir, exist_ok=True)
    wipe_scene()
    setup_world_and_camera()
    look = look_for_slot(slot, uniform)
    parts, limbs = build_character(look)
    if outline:
        add_outline_shell(parts, outline_material())

    for f in range(frames):
        pose_walk(limbs, 2.0 * math.pi * f / frames)
        bpy.context.view_layer.update()
        bpy.context.scene.render.filepath = os.path.join(out_dir, f"look{slot:02d}_f{f}.png")
        bpy.ops.render.render(write_still=True)
        print(f"RENDERED {bpy.context.scene.render.filepath}")


main()
