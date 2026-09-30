"""Rigged toy chibi for visitors, staff and porters -> art3d/characters/chibi.glb

    blender -b --factory-startup --python tools/blender/toybox/characters.py

One model serves the whole cast. Each body part is rigidly skinned to one bone
(a vertex group at weight 1), so there is no deformation to go wrong on import.
Variety comes from the game side:
  - materials are named by ROLE (skin, hair, shirt, pants, shoe) so Godot can
    recolour each surface per look;
  - accessories are separate meshes named acc_* (hat, cap, backpack, glasses,
    bag, vest, bow, camera, and the visitor-type pieces: top hat, beret, crown,
    shades, cape, scarf) and are shown or hidden per look.
Animations: walk (loop), idle (loop), cheer. The model faces -Y in Blender,
which is +Z in Godot (Godot's model-front convention).
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import toy  # noqa: E402
from toy import box, cyl, sphere, torus, rod  # noqa: E402

FPS = 24
BONES = {  # name: (head, tail, parent)
    "root": ((0, 0, 0), (0, 0, 0.1), None),
    "hips": ((0, 0, 0.25), (0, 0, 0.33), "root"),
    "torso": ((0, 0, 0.33), (0, 0, 0.52), "hips"),
    "head": ((0, 0, 0.52), (0, 0, 0.8), "torso"),
    "arm.L": ((0.16, 0, 0.47), (0.2, 0, 0.31), "torso"),
    "arm.R": ((-0.16, 0, 0.47), (-0.2, 0, 0.31), "torso"),
    "leg.L": ((0.07, 0, 0.25), (0.07, 0, 0.05), "hips"),
    "leg.R": ((-0.07, 0, 0.25), (-0.07, 0, 0.05), "hips"),
}


def role(name, hexc, rough=0.88):
    """A material whose NAME is the role the game recolours."""
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = toy.hexcol(hexc)
    b.inputs["Roughness"].default_value = rough
    return m


def bind(o, bone):
    vg = o.vertex_groups.new(name=bone)
    vg.add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
    return o


def build_armature():
    arm_data = bpy.data.armatures.new("rig")
    arm = bpy.data.objects.new("chibi", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for name, (h, t, parent) in BONES.items():
        eb = arm_data.edit_bones.new(name)
        eb.head, eb.tail = Vector(h), Vector(t)
        eb.roll = 0.0
        if parent:
            eb.parent = arm_data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def body_parts():
    skin, hair = role("skin", "#FFD2A8", 0.45), role("hair", "#6B3F1F", 0.3)
    shirt, pants, shoe = role("shirt", "#3A78D8"), role("pants", "#3A3F4A", 0.45), role("shoe", "#5A3A22", 0.4)
    eye, cheek = role("eye", "#141414", 0.1), role("cheek", "#FF9A9A", 0.5)
    parts = [
        bind(sphere(0.13, (0, 0, 0.27), pants, scale=(1, 0.9, 0.7)), "hips"),
        bind(cyl(0.15, 0.24, (0, 0, 0.41), shirt, r2=0.12, bev=0.03), "torso"),
        bind(torus(0.085, 0.03, (0, 0, 0.53), shirt), "torso"),
        bind(sphere(0.21, (0, 0, 0.69), skin, scale=(1, 0.95, 0.95)), "head"),
        bind(sphere(0.222, (0, 0.035, 0.74), hair, scale=(1, 1, 0.82)), "head"),
    ]
    for fx in (-0.09, 0.0, 0.09):
        parts.append(bind(sphere(0.07, (fx, -0.14, 0.83 - abs(fx) * 0.4), hair, seg=16), "head"))
    for sx in (-1, 1):
        parts.append(bind(sphere(0.033, (sx * 0.072, -0.19, 0.67), eye, scale=(0.75, 0.5, 1.25), seg=16), "head"))
        parts.append(bind(sphere(0.012, (sx * 0.072 + 0.01, -0.205, 0.685), role("eye_hi", "#FFFFFF", 0.2), seg=8), "head"))
        parts.append(bind(sphere(0.028, (sx * 0.125, -0.165, 0.62), cheek, scale=(1, 0.4, 0.7), seg=12), "head"))
        side = "L" if sx > 0 else "R"
        parts.append(bind(sphere(0.062, (sx * 0.165, 0, 0.47), shirt, seg=16), f"arm.{side}"))
        parts.append(bind(rod((sx * 0.17, 0, 0.46), (sx * 0.2, 0, 0.34), 0.045, shirt), f"arm.{side}"))
        parts.append(bind(sphere(0.05, (sx * 0.2, -0.01, 0.31), skin, seg=16), f"arm.{side}"))
        parts.append(bind(rod((sx * 0.07, 0, 0.24), (sx * 0.07, 0, 0.07), 0.05, pants), f"leg.{side}"))
        parts.append(bind(sphere(0.066, (sx * 0.07, -0.025, 0.045), shoe, scale=(1, 1.4, 0.7), seg=16), f"leg.{side}"))
    return parts


def accessory(name, parts):
    o = toy.join(parts, name)
    return o


def accessories():
    acc = []
    straw, band = role("acc_straw", "#E8C35A", 0.5), role("acc_band", "#C0392B", 0.4)
    acc.append(accessory("acc_hat", [bind(cyl(0.3, 0.03, (0, 0.02, 0.86), straw, bev=0.01), "head"),
                                     bind(sphere(0.16, (0, 0.03, 0.88), straw, scale=(1, 1, 0.75)), "head"),
                                     bind(torus(0.155, 0.022, (0, 0.03, 0.9), band), "head")]))
    capc = role("acc_cap", "#D9413A", 0.35)
    acc.append(accessory("acc_cap", [bind(sphere(0.215, (0, 0.03, 0.78), capc, scale=(1, 1, 0.7)), "head"),
                                     bind(cyl(0.15, 0.025, (0, -0.2, 0.8), capc, bev=0.008), "head")]))
    pack = role("acc_pack", "#F2A33A", 0.4)
    acc.append(accessory("acc_backpack", [bind(box((0.2, 0.1, 0.22), (0, 0.16, 0.42), pack, bev=0.04), "torso"),
                                          bind(box((0.14, 0.03, 0.08), (0, 0.22, 0.38), role("acc_pack2", "#C77A1E"), bev=0.015), "torso")]))
    frame = role("acc_frame", "#2B2245", 0.3)
    acc.append(accessory("acc_glasses", [bind(torus(0.045, 0.01, (sx * 0.072, -0.2, 0.67), frame, rot=(math.pi / 2, 0, 0)), "head")
                                         for sx in (-1, 1)] + [bind(rod((-0.03, -0.205, 0.68), (0.03, -0.205, 0.68), 0.008, frame), "head")]))
    bag = role("acc_bag", "#8E5A9E", 0.4)
    acc.append(accessory("acc_bag", [bind(box((0.14, 0.06, 0.12), (0.19, -0.02, 0.28), bag, bev=0.025), "hips"),
                                     bind(rod((0.12, -0.02, 0.5), (0.19, -0.02, 0.33), 0.012, bag), "torso")]))
    vest, badge = role("acc_vest", "#C0392B", 0.35), role("acc_badge", "#F2C14E", 0.25)
    acc.append(accessory("acc_vest", [bind(cyl(0.158, 0.2, (0, 0, 0.42), vest, r2=0.128, bev=0.02), "torso"),
                                      bind(cyl(0.028, 0.012, (0.06, -0.14, 0.46), badge, rot=(math.pi / 2, 0, 0), bev=0.004), "torso")]))
    bow = role("acc_bow", "#FF6FA8", 0.35)
    acc.append(accessory("acc_bow", [bind(sphere(0.05, (sx * 0.055, 0.05, 0.92), bow, scale=(1.2, 0.6, 0.9), seg=12), "head")
                                     for sx in (-1, 1)] + [bind(sphere(0.025, (0, 0.05, 0.92), bow, seg=10), "head")]))
    cam = role("acc_camera", "#2E3A4A", 0.3)
    acc.append(accessory("acc_camera", [bind(box((0.1, 0.05, 0.07), (0, -0.16, 0.38), cam, bev=0.015), "torso"),
                                        bind(cyl(0.022, 0.03, (0, -0.19, 0.38), role("acc_lens", "#7FD4E8", 0.1),
                                                 rot=(math.pi / 2, 0, 0), bev=0.005), "torso")]))
    # Visitor types unlocked by reputation (data/visitor_types.json).
    silk, ribbon = role("acc_tophat", "#26232E", 0.25), role("acc_ribbon", "#B0303A", 0.35)
    acc.append(accessory("acc_tophat", [bind(cyl(0.23, 0.025, (0, 0.03, 0.885), silk, bev=0.01), "head"),
                                        bind(cyl(0.145, 0.25, (0, 0.03, 1.01), silk, r2=0.155, bev=0.02), "head"),
                                        bind(cyl(0.162, 0.045, (0, 0.03, 0.925), ribbon, bev=0.008), "head")]))
    beret = role("acc_beret", "#7A1F3D", 0.5)
    acc.append(accessory("acc_beret", [bind(sphere(0.2, (0.03, 0.04, 0.9), beret, scale=(1.08, 1.08, 0.36)), "head"),
                                       bind(cyl(0.018, 0.04, (0.03, 0.04, 0.975), beret, bev=0.006), "head")]))
    gold, gem = role("acc_gold", "#F2C14E", 0.18), role("acc_gem", "#E0314B", 0.1)
    crown = [bind(cyl(0.155, 0.08, (0, 0.03, 0.92), gold, r2=0.17, bev=0.012), "head")]
    for i in range(6):
        a = i * math.tau / 6
        x, y = 0.15 * math.sin(a), 0.03 - 0.15 * math.cos(a)
        crown.append(bind(cyl(0.032, 0.08, (x, y, 0.99), gold, r2=0.004, bev=0.0, verts=10), "head"))
        crown.append(bind(sphere(0.016, (x, y, 1.035), gold, seg=10), "head"))
    crown.append(bind(sphere(0.03, (0, -0.135, 0.925), gem, scale=(1, 0.5, 1.2), seg=12), "head"))
    acc.append(accessory("acc_crown", crown))
    lens = role("acc_shades", "#16161E", 0.08)
    acc.append(accessory("acc_shades", [bind(box((0.1, 0.02, 0.06), (sx * 0.072, -0.205, 0.68), lens, bev=0.015), "head")
                                        for sx in (-1, 1)] + [bind(rod((-0.03, -0.21, 0.69), (0.03, -0.21, 0.69), 0.01, lens), "head")]))
    cape, trim = role("acc_cape", "#A4263A", 0.45), role("acc_trim", "#FFF4E0", 0.6)
    acc.append(accessory("acc_cape", [bind(box((0.34, 0.035, 0.36), (0, 0.155, 0.35), cape, bev=0.015, rot=(-0.12, 0, 0)), "torso"),
                                      bind(torus(0.11, 0.035, (0, 0.01, 0.53), trim), "torso")]))
    scarf = role("acc_scarf", "#2F8FD8", 0.55)
    acc.append(accessory("acc_scarf", [bind(torus(0.1, 0.038, (0, 0, 0.535), scarf), "torso"),
                                       bind(box((0.06, 0.03, 0.16), (0.07, -0.13, 0.44), scarf, bev=0.012, rot=(0.15, 0, 0.1)), "torso")]))
    return acc


# ------------------------------------------------------------ animation
def key(arm, frame, pose):
    for bone, (rot, loc) in pose.items():
        pb = arm.pose.bones[bone]
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = rot
        pb.location = loc
        pb.keyframe_insert("rotation_euler", frame=frame)
        pb.keyframe_insert("location", frame=frame)


def rest():
    return {b: ((0, 0, 0), (0, 0, 0)) for b in BONES}


def make_action(arm, name, frames, pose_fn):
    arm.animation_data_create()
    arm.animation_data.action = None
    for f in range(frames + 1):
        key(arm, f, pose_fn(f / frames))
    act = arm.animation_data.action
    act.name = name
    act.use_fake_user = True
    track = arm.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, 0, act)
    arm.animation_data.action = None


def walk(t):
    p = rest()
    s = math.sin(t * math.tau)
    p["leg.L"] = ((0.6 * s, 0, 0), (0, 0, 0))
    p["leg.R"] = ((-0.6 * s, 0, 0), (0, 0, 0))
    p["arm.L"] = ((-0.5 * s, 0, 0), (0, 0, 0))
    p["arm.R"] = ((0.5 * s, 0, 0), (0, 0, 0))
    p["hips"] = ((0, 0, 0), (0, 0.025 * abs(math.cos(t * math.tau)), 0))  # bone-local Y is world up here
    p["torso"] = ((0, 0.08 * s, 0), (0, 0, 0))
    p["head"] = ((0.04 * math.cos(t * math.tau * 2), 0, 0), (0, 0, 0))
    return p


def idle(t):
    p = rest()
    s = math.sin(t * math.tau)
    p["torso"] = ((0.03 * s, 0, 0), (0, 0, 0))
    p["head"] = ((0.04 * s, 0.05 * math.sin(t * math.tau * 0.5 + 1), 0), (0, 0, 0))
    p["arm.L"] = ((0, 0, 0.05 + 0.03 * s), (0, 0, 0))
    p["arm.R"] = ((0, 0, -0.05 - 0.03 * s), (0, 0, 0))
    return p


def cheer(t):
    p = rest()
    jump = math.sin(min(1.0, t * 2) * math.pi) if t < 0.5 else 0.0
    up = math.sin(t * math.pi)
    p["hips"] = ((0, 0, 0), (0, 0.12 * jump, 0))
    p["arm.L"] = ((0, 0, 2.4 * up), (0, 0, 0))
    p["arm.R"] = ((0, 0, -2.4 * up), (0, 0, 0))
    p["head"] = ((-0.2 * up, 0, 0), (0, 0, 0))
    return p


def main():
    toy.reset()
    bpy.context.scene.render.fps = FPS
    arm = build_armature()
    body = toy.join(body_parts(), "body")
    meshes = [body] + accessories()
    for o in meshes:
        o.parent = arm
        mod = o.modifiers.new("rig", "ARMATURE")
        mod.object = arm
    make_action(arm, "walk", 16, walk)
    make_action(arm, "idle", 48, idle)
    make_action(arm, "cheer", 24, cheer)
    path = os.path.join(toy.ART3D, "characters", "chibi.glb")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    for o in meshes:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=False,
                              export_yup=True, export_animations=True, export_animation_mode="NLA_TRACKS",
                              export_skins=True, export_lights=False, export_cameras=False)
    print("EXPORTED", os.path.relpath(path, toy.ROOT))
    if "--preview" in sys.argv:
        for o in meshes:
            o.hide_render = o.name not in ("body", "acc_crown", "acc_cape")
        toy.preview(os.path.join(toy.ROOT, "docs", "visual-overhaul", "chibi_preview.png"), target=(0, 0, 0.45), dist=2.6,
                    tilt_deg=70, lens=50, res=(800, 800))


if __name__ == "__main__":
    main()
