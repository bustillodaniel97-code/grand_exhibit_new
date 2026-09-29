"""
Toy-diorama style test scene (Link's Awakening remake-inspired look, original content).
Run:  blender -b --factory-startup --python build_island.py
Outputs renders/island_v3.png and island_v3.blend next to this script.
"""
import bpy, math, random, os, time
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_PNG = os.path.join(HERE, "renders", "island_v3.png")
OUT_BLEND = os.path.join(HERE, "island_v3.blend")
rnd = random.Random(42)

# ---------------------------------------------------------------- map
# M high cliff  g tall grass  . grass  = dirt path  ~ water  ^ cliff  C cave  T tree  b bush  r rock  H house footprint
MAP = [
    "TTTTTMMMMMMMMMMTTTTT",
    "TTTMMMMM^^^^^MMMMTTT",
    "TT.^^^^^^C^^^^^^.bTT",
    "T..b.....=.....b..TT",
    "T.gg.....=........~T",
    "T.HHHH...=.......~~T",
    "T.HHHH...=......~~~T",
    "T.HHHH...=.....~~~~T",
    "T..=======....~~~~~T",
    "Tb...=.........~~~.T",
    "T....=..r..ggg..b..T",
    "TT...=....b.gg.....T",
    "TTb..=.............T",
    "TTTTT=TTTTTTTTTTTTTT",
]
W, H = len(MAP[0]), len(MAP)
assert all(len(r) == W for r in MAP), [len(r) for r in MAP]


def tile_xy(c, r):
    return (c - W / 2 + 0.5, H / 2 - r - 0.5)


# ---------------------------------------------------------------- reset
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)
scene = bpy.context.scene
ROOT = scene.collection
PROTOS = bpy.data.collections.new("_protos")
ROOT.children.link(PROTOS)


# ---------------------------------------------------------------- materials
def srgb2lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexcol(h):
    h = h.lstrip("#")
    return tuple(srgb2lin(int(h[i:i + 2], 16) / 255) for i in (0, 2, 4)) + (1.0,)


def setin(node, name, val):
    if name in node.inputs:
        node.inputs[name].default_value = val


def mat(name, hexc, rough=0.4, coat=0.0, var=0.0, emit=0.0):
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    col = hexcol(hexc)
    setin(b, "Roughness", rough)
    setin(b, "Coat Weight", coat)
    setin(b, "Coat Roughness", 0.15)
    if var > 0:
        oi = nt.nodes.new("ShaderNodeObjectInfo")
        mr = nt.nodes.new("ShaderNodeMapRange")
        mr.inputs["To Min"].default_value = 1 - var
        mr.inputs["To Max"].default_value = 1 + var
        hsv = nt.nodes.new("ShaderNodeHueSaturation")
        hsv.inputs["Color"].default_value = col
        nt.links.new(oi.outputs["Random"], mr.inputs["Value"])
        nt.links.new(mr.outputs["Result"], hsv.inputs["Value"])
        nt.links.new(hsv.outputs["Color"], b.inputs["Base Color"])
    else:
        b.inputs["Base Color"].default_value = col
    if emit:
        setin(b, "Emission Color", col)
        setin(b, "Emission Strength", emit)
    m.diffuse_color = col
    return m


M = {
    "grass": mat("grass", "#6cc24a", 0.55, var=0.06),
    "cap": mat("grass_cap", "#74c950", 0.55, var=0.05),
    "tuft": mat("tuft", "#8fd65e", 0.5),
    "dirt": mat("dirt", "#e6b873", 0.6, var=0.05),
    "rock": mat("cliff_rock", "#b8885a", 0.55, var=0.07),
    "rock_dark": mat("cliff_band", "#94683f", 0.6),
    "stone": mat("stone", "#a9b1ba", 0.45, coat=0.2, var=0.06),
    "bed": mat("water_bed", "#2d7fb5", 0.6),
    "water": mat("water", "#1f8fe0", 0.12, coat=0.8),
    "lily": mat("lily", "#4fae3c", 0.4, coat=0.3),
    "leaf": mat("leaf", "#2f9a3e", 0.35, coat=0.35, var=0.06),
    "leaf2": mat("leaf_dark", "#237a35", 0.35, coat=0.35),
    "leaf_hi": mat("leaf_hi", "#4dbb4a", 0.35, coat=0.35),
    "trunk": mat("trunk", "#7a4a2a", 0.5),
    "bush": mat("bush", "#5cc04a", 0.35, coat=0.35, var=0.06),
    "stem": mat("stem", "#3f9a36", 0.5),
    "pink": mat("petal_pink", "#ff6fa8", 0.3, coat=0.4),
    "white": mat("petal_white", "#fff6f0", 0.3, coat=0.4),
    "yellow": mat("petal_yellow", "#ffd23f", 0.3, coat=0.4),
    "orange": mat("flower_center", "#ff9a2e", 0.3),
    "roof": mat("roof", "#d9413a", 0.3, coat=0.5),
    "wall": mat("wall", "#f3e3c3", 0.6),
    "wood": mat("wood", "#8b5a2b", 0.5, coat=0.2),
    "door": mat("door", "#6b3f1f", 0.45, coat=0.3),
    "frame": mat("frame", "#fffaf0", 0.4),
    "glass": mat("window", "#8fd2ff", 0.1, coat=0.6, emit=0.4),
    "gold": mat("gold", "#f2c14e", 0.2, coat=0.6),
    "clay": mat("clay", "#d0714a", 0.4, coat=0.3),
    "cave": mat("cave", "#0d0a08", 0.9),
    "skin": mat("skin", "#ffd2a8", 0.45, coat=0.4),
    "hair": mat("hair", "#e0662a", 0.35, coat=0.5),
    "tunic": mat("tunic", "#3a78d8", 0.35, coat=0.5),
    "scarf": mat("scarf", "#ffcc33", 0.35, coat=0.5),
    "boot": mat("boot", "#6b3f1f", 0.4, coat=0.4),
    "black": mat("eye", "#141414", 0.15, coat=0.8),
    "cheek": mat("cheek", "#ff9a9a", 0.5),
    "shield": mat("shield", "#c8332e", 0.3, coat=0.6),
    "straw": mat("straw", "#e8c35a", 0.5, coat=0.2),
    "shirt": mat("npc_shirt", "#c95f9e", 0.4, coat=0.4),
    "apron": mat("apron", "#fff4e6", 0.5),
    "stache": mat("mustache", "#5a3a22", 0.5),
}


# ---------------------------------------------------------------- mesh helpers
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


def finish(o, m, bev=0.0, seg=3, flat=False):
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if bev:
        bevel(o, bev, seg)
    if not flat:
        smooth(o)
    if m:
        set_mat(o, m)
    return o


def cube(size, loc, m, bev=0.0, rot=(0, 0, 0), seg=3):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.scale = size
    return finish(o, m, bev, seg, flat=not bev)  # unbevelled boxes stay flat-shaded


def sphere(r, loc, m, scale=(1, 1, 1), seg=24):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=loc, segments=seg, ring_count=seg // 2)
    o = bpy.context.active_object
    o.scale = scale
    return finish(o, m)


def cyl(r, depth, loc, m, r2=None, rot=(0, 0, 0), bev=0.02, verts=24):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, location=loc, rotation=rot, vertices=verts)
    else:
        bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=depth, location=loc, rotation=rot, vertices=verts)
    return finish(bpy.context.active_object, m, bev, 2)


def torus(R, r, loc, m, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, location=loc, rotation=rot,
                                     major_segments=32, minor_segments=12)
    return finish(bpy.context.active_object, m)


def ico(r, loc, m, sub=2, jitter=0.0, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_ico_sphere_add(radius=r, location=(0, 0, 0), subdivisions=sub)
    o = bpy.context.active_object
    for v in o.data.vertices:
        v.co += Vector([rnd.uniform(-jitter, jitter) for _ in range(3)])
    o.scale = scale
    o.location = loc
    return finish(o, m)


def prism(w, d, h, loc, m, bev=0.06):
    x, y = w / 2, d / 2
    verts = [(-x, -y, 0), (x, -y, 0), (x, y, 0), (-x, y, 0), (-x, 0, h), (x, 0, h)]
    faces = [(0, 3, 2, 1), (0, 1, 5, 4), (2, 3, 4, 5), (0, 4, 3), (1, 2, 5)]
    me = bpy.data.meshes.new("prism")
    me.from_pydata(verts, [], faces)
    o = bpy.data.objects.new("roof", me)
    ROOT.objects.link(o)
    o.location = loc
    bevel(o, bev)
    smooth(o)
    set_mat(o, m)
    return o


def join(objs, name):
    for o in objs:
        bpy.context.view_layer.objects.active = o
        for mod in list(o.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    return o


def make_proto(o):
    for c in list(o.users_collection):
        c.objects.unlink(o)
    PROTOS.objects.link(o)
    return o


def inst(proto, loc, rz=0.0, s=1.0):
    n = proto.copy()
    n.location = loc
    n.rotation_euler = (0, 0, rz)
    n.scale = (s, s, s) if isinstance(s, (int, float)) else s
    ROOT.objects.link(n)
    return n


# ---------------------------------------------------------------- prototypes
P = {}
P["grass"] = make_proto(cube((1, 1, 1), (0, 0, -0.5), M["grass"], bev=0.02, seg=2))
P["dirt"] = make_proto(cube((1, 1, 1), (0, 0, -0.53), M["dirt"], bev=0.02, seg=2))
P["bed"] = make_proto(cube((1, 1, 1), (0, 0, -0.95), M["bed"]))
P["water"] = make_proto(cube((1, 1, 0.02), (0, 0, -0.13), M["water"]))
P["foam"] = make_proto(cube((1.02, 0.14, 0.03), (0, 0, -0.115), M["frame"], bev=0.012, seg=2))
CLIFF_TOP = 1.4


def build_cliff(seed):
    r = random.Random(seed)
    parts = [
        cube((1, 1, 2.2), (0, 0, CLIFF_TOP - 0.16 - 1.1), M["rock"], bev=0.07),
        cube((1.0, 1.04, 0.1), (0, 0, 0.42), M["rock_dark"], bev=0.04),
        cube((1, 1, 0.22), (0, 0, CLIFF_TOP - 0.11), M["cap"], bev=0.08),
    ]
    for side in (-1, 1):  # rounded boulders half-buried in front/back faces
        for _ in range(r.randint(3, 5)):
            s = r.uniform(0.14, 0.24)
            parts.append(ico(s, (r.uniform(-0.38, 0.38), side * 0.47, r.uniform(0.12, CLIFF_TOP - 0.4)),
                             M["rock"], sub=2, jitter=0.02, scale=(1.2, 0.55, 1.0)))
    return make_proto(join(parts, f"cliff_{seed}"))


P["cliffs"] = [build_cliff(s) for s in range(4)]


def build_tree(seed):
    r = random.Random(seed)
    parts = [cyl(0.15, 0.55, (0, 0, 0.27), M["trunk"], r2=0.11, bev=0.03)]
    parts.append(sphere(0.62, (0, 0, 1.0), M["leaf"], scale=(1, 1, 0.9)))
    n = 7
    for i in range(n):
        a = i / n * math.tau + r.uniform(-0.3, 0.3)
        parts.append(sphere(r.uniform(0.3, 0.4), (math.cos(a) * 0.45, math.sin(a) * 0.45, 0.82 + r.uniform(-0.05, 0.2)),
                            M["leaf2"] if i % 2 else M["leaf"]))
    parts.append(sphere(0.42, (0, -0.05, 1.38), M["leaf"]))
    parts.append(sphere(0.2, (-0.15, -0.2, 1.62), M["leaf_hi"], scale=(1, 1, 0.7)))
    return make_proto(join(parts, f"tree_{seed}"))


P["trees"] = [build_tree(s) for s in range(3)]


def build_bush(seed):
    r = random.Random(seed)
    parts = [sphere(0.3, (0, 0, 0.22), M["bush"], scale=(1, 1, 0.85))]
    for i in range(5):
        a = i / 5 * math.tau + r.uniform(-0.3, 0.3)
        parts.append(sphere(r.uniform(0.15, 0.2), (math.cos(a) * 0.24, math.sin(a) * 0.24, 0.2 + r.uniform(0, 0.1)), M["bush"]))
    parts.append(sphere(0.12, (-0.06, -0.1, 0.45), M["leaf_hi"], scale=(1, 1, 0.7)))
    return make_proto(join(parts, f"bush_{seed}"))


P["bushes"] = [build_bush(s) for s in range(3)]


def build_flower(petal, center):
    parts = [cyl(0.012, 0.18, (0, 0, 0.09), M["stem"], bev=0)]
    for i in range(5):
        a = i / 5 * math.tau
        parts.append(sphere(0.035, (math.cos(a) * 0.04, math.sin(a) * 0.04, 0.19), petal, scale=(1, 1, 0.6), seg=12))
    parts.append(sphere(0.028, (0, 0, 0.2), center, seg=12))
    return make_proto(join(parts, "flower"))


P["flowers"] = [build_flower(M["pink"], M["yellow"]), build_flower(M["white"], M["yellow"]),
                build_flower(M["yellow"], M["orange"])]


def build_tuft():
    parts = []
    for i in range(3):
        a = i / 3 * math.tau
        parts.append(cyl(0.035, 0.18, (math.cos(a) * 0.04, math.sin(a) * 0.04, 0.07), M["tuft"], r2=0.0,
                         rot=(math.sin(a) * 0.35, -math.cos(a) * 0.35, 0), bev=0, verts=8))
    return make_proto(join(parts, "tuft"))


P["tuft"] = build_tuft()


def build_tall_grass(seed):
    r = random.Random(seed)
    parts = []
    for i in range(9):
        a = r.uniform(0, math.tau)
        d = r.uniform(0, 0.28)
        lean = 0.25 + d
        parts.append(cyl(0.07, r.uniform(0.35, 0.5), (math.cos(a) * d, math.sin(a) * d, 0.18), M["bush" if i % 3 else "leaf_hi"],
                         r2=0.0, rot=(math.sin(a) * lean, -math.cos(a) * lean, 0), bev=0, verts=8))
    return make_proto(join(parts, f"tallgrass_{seed}"))


P["tallgrass"] = [build_tall_grass(s) for s in range(3)]
P["rocks"] = [make_proto(ico(0.26, (0, 0, 0.12), M["stone"], jitter=0.04, scale=(1.1, 1, 0.8))) for _ in range(3)]
P["lily"] = make_proto(cyl(0.17, 0.02, (0, 0, -0.11), M["lily"], bev=0.008))

# ---------------------------------------------------------------- terrain + scatter
occupied = set()


def scatter_grass(x, y, z, dense=1.0):
    for _ in range(rnd.randint(0, 3)):
        if rnd.random() < 0.55 * dense:
            inst(P["tuft"], (x + rnd.uniform(-0.4, 0.4), y + rnd.uniform(-0.4, 0.4), z), rnd.uniform(0, 6.3),
                 rnd.uniform(0.8, 1.3))
    if rnd.random() < 0.16 * dense:
        f = rnd.choice(P["flowers"])
        for _ in range(rnd.randint(2, 4)):
            inst(f, (x + rnd.uniform(-0.35, 0.35), y + rnd.uniform(-0.35, 0.35), z), rnd.uniform(0, 6.3),
                 rnd.uniform(0.9, 1.2))


for r, row in enumerate(MAP):
    for c, ch in enumerate(row):
        x, y = tile_xy(c, r)
        if ch in "^CM":
            tiers = 2 if ch == "M" else 1
            for t in range(tiers):
                inst(rnd.choice(P["cliffs"]), (x, y, t * CLIFF_TOP), rnd.choice([0, math.pi]))
            top = tiers * CLIFF_TOP
            if ch != "C":
                roll = rnd.random()
                if roll < 0.08:
                    inst(rnd.choice(P["trees"]), (x, y, top), rnd.uniform(0, 6.3), rnd.uniform(0.9, 1.1))
                elif roll < 0.22:
                    inst(rnd.choice(P["bushes"]), (x, y, top), rnd.uniform(0, 6.3))
                else:
                    scatter_grass(x, y, top, 0.8)
        elif ch == "~":
            inst(P["bed"], (x, y, 0))
            inst(P["water"], (x, y, 0))
            for dc, dr, rz in ((0, -1, 0), (0, 1, 0), (-1, 0, math.pi / 2), (1, 0, math.pi / 2)):
                cc, rr = c + dc, r + dr
                if 0 <= cc < W and 0 <= rr < H and MAP[rr][cc] != "~":  # foam line along the shore
                    inst(P["foam"], (x + dc * 0.44, y - dr * 0.44, 0), rz)
            if rnd.random() < 0.3:
                inst(P["lily"], (x + rnd.uniform(-0.25, 0.25), y + rnd.uniform(-0.25, 0.25), 0), rnd.uniform(0, 6.3),
                     rnd.uniform(0.7, 1.2))
        elif ch == "=":
            inst(P["dirt"], (x, y, 0), rnd.choice([0, math.pi / 2, math.pi]))
        else:
            inst(P["grass"], (x, y, 0), rnd.choice([0, math.pi / 2, math.pi]))
            if ch == "T":
                inst(rnd.choice(P["trees"]), (x + rnd.uniform(-0.1, 0.1), y + rnd.uniform(-0.1, 0.1), 0),
                     rnd.uniform(0, 6.3), rnd.uniform(1.0, 1.25))
            elif ch == "b":
                inst(rnd.choice(P["bushes"]), (x, y, 0), rnd.uniform(0, 6.3))
            elif ch == "g":
                inst(rnd.choice(P["tallgrass"]), (x, y, 0), rnd.uniform(0, 6.3))
            elif ch == "r":
                inst(rnd.choice(P["rocks"]), (x, y, 0), rnd.uniform(0, 6.3), 1.2)
            elif ch == "." and (c, r) not in occupied:
                if rnd.random() < 0.04:
                    inst(rnd.choice(P["rocks"]), (x, y, 0), rnd.uniform(0, 6.3))
                else:
                    scatter_grass(x, y, 0)

# cave entrance in the cliff face at 'C'
for r, row in enumerate(MAP):
    c = row.find("C")
    if c >= 0:
        x, y = tile_xy(c, r)
        fy = y - 0.5
        cube((0.72, 0.1, 0.5), (x, fy - 0.02, 0.25), M["stone"], bev=0.04)
        cyl(0.36, 0.1, (x, fy - 0.02, 0.5), M["stone"], rot=(math.pi / 2, 0, 0), bev=0.03)
        cube((0.5, 0.1, 0.45), (x, fy - 0.05, 0.225), M["cave"])
        cyl(0.25, 0.1, (x, fy - 0.05, 0.45), M["cave"], rot=(math.pi / 2, 0, 0), bev=0)

# ---------------------------------------------------------------- house
hx, hy = -6.0, 1.0
front = hy - 1.2
cube((3.4, 2.6, 0.25), (hx, hy, 0.125), M["stone"], bev=0.06)
cube((3.2, 2.4, 1.5), (hx, hy, 0.95), M["wall"], bev=0.04)
cube((3.3, 2.5, 0.14), (hx, hy, 1.62), M["wood"], bev=0.04)
for sx in (-1, 1):
    for sy in (-1, 1):
        cube((0.16, 0.16, 1.5), (hx + sx * 1.58, hy + sy * 1.18, 0.95), M["wood"], bev=0.04)
prism(3.9, 3.1, 1.35, (hx, hy, 1.66), M["roof"], bev=0.08)
slope = math.atan2(1.35, 1.55)
for side in (-1, 1):  # rounded shingle rows running along each roof slope
    for i in range(5):
        t = (i + 0.5) / 5.4
        sy = hy + side * 1.55 * (1 - t) + side * 0.05 * math.sin(slope)
        sz = 1.66 + 1.35 * t + 0.05 * math.cos(slope)
        cyl(0.075, 3.95, (hx, sy, sz), M["roof"] if i % 2 else M["clay"], rot=(0, math.pi / 2, 0), bev=0.02)
cyl(0.11, 4.0, (hx, hy, 3.0), M["roof"], rot=(0, math.pi / 2, 0), bev=0.03)
cube((0.38, 0.38, 0.9), (hx + 1.0, hy + 0.55, 2.55), M["stone"], bev=0.05)
cube((0.48, 0.48, 0.1), (hx + 1.0, hy + 0.55, 3.02), M["stone"], bev=0.03)
dx = -6.5
cube((0.52, 0.08, 0.8), (dx, front - 0.02, 0.65), M["door"], bev=0.02)
cyl(0.26, 0.08, (dx, front - 0.02, 1.05), M["door"], rot=(math.pi / 2, 0, 0))
sphere(0.04, (dx + 0.16, front - 0.08, 0.7), M["gold"])
for wx in (-5.3,):
    cube((0.56, 0.06, 0.56), (wx, front - 0.02, 1.05), M["frame"], bev=0.02)
    cube((0.42, 0.08, 0.42), (wx, front - 0.02, 1.05), M["glass"], bev=0.01)
    cube((0.04, 0.1, 0.42), (wx, front - 0.02, 1.05), M["frame"])
    cube((0.42, 0.1, 0.04), (wx, front - 0.02, 1.05), M["frame"])
    cube((0.62, 0.18, 0.14), (wx, front - 0.1, 0.72), M["wood"], bev=0.03)
    for i in range(4):
        sphere(0.06, (wx - 0.22 + i * 0.15, front - 0.1, 0.83), [M["pink"], M["yellow"]][i % 2], seg=12)
for px, py, s in ((-4.0, -0.25, 1.0), (-3.75, 0.05, 0.85), (-4.15, 0.2, 0.9)):
    o = sphere(0.16 * s, (px, py, 0.15 * s), M["clay"], scale=(1, 1, 0.9))
    torus(0.1 * s, 0.03 * s, (px, py, 0.28 * s), M["clay"])
for i in range(2):
    cyl(0.16, 0.04, (dx + (i - 0.5) * 0.15, front - 0.45 - i * 0.3, 0.01), M["stone"], bev=0.015)

# ---------------------------------------------------------------- props
def chest(x, y):
    cube((0.55, 0.38, 0.3), (x, y, 0.15), M["wood"], bev=0.03)
    cyl(0.19, 0.55, (x, y, 0.3), M["wood"], rot=(0, math.pi / 2, 0), bev=0.02)
    for sx in (-0.2, 0.2):
        cube((0.06, 0.4, 0.31), (x + sx, y, 0.155), M["gold"], bev=0.01)
    cube((0.1, 0.05, 0.12), (x, y - 0.2, 0.3), M["gold"], bev=0.01)


def sign(x, y):
    cyl(0.05, 0.5, (x, y, 0.25), M["wood"], verts=12)
    cube((0.6, 0.08, 0.36), (x, y - 0.03, 0.55), M["wood"], bev=0.03)
    for i in range(3):
        cube((0.4 - i * 0.08, 0.02, 0.03), (x - 0.02, y - 0.08, 0.64 - i * 0.08), M["door"])


def fence(x0, x1, y):
    n = int(round((x1 - x0) / 0.5))
    for i in range(n + 1):
        cyl(0.05, 0.42, (x0 + i * 0.5, y, 0.21), M["wood"], verts=12)
        sphere(0.055, (x0 + i * 0.5, y, 0.43), M["wood"], seg=12)
    for z in (0.16, 0.32):
        cube((x1 - x0, 0.05, 0.06), ((x0 + x1) / 2, y, z), M["wood"], bev=0.015)


chest(*tile_xy(12, 3))
sign(*tile_xy(10, 7))
fence(1.0, 5.0, 2.55)


# ---------------------------------------------------------------- characters (original designs)
def hero(x, y, z, rz):
    p = []
    for sx in (-1, 1):
        p.append(cyl(0.07, 0.1, (sx * 0.07, -0.02, 0.05), M["boot"], verts=16))
    p.append(cyl(0.2, 0.32, (0, 0, 0.26), M["tunic"], r2=0.12))
    p.append(torus(0.155, 0.025, (0, 0, 0.3), M["boot"]))
    for sx in (-1, 1):
        p.append(sphere(0.07, (sx * 0.17, 0, 0.37), M["tunic"], seg=16))
        p.append(sphere(0.055, (sx * 0.2, -0.02, 0.28), M["skin"], seg=16))
    p.append(torus(0.11, 0.045, (0, 0, 0.44), M["scarf"]))
    p.append(sphere(0.22, (0, 0, 0.64), M["skin"], scale=(1, 0.95, 0.95)))
    p.append(sphere(0.235, (0, 0.035, 0.7), M["hair"], scale=(1, 1, 0.85)))
    for fx in (-0.1, 0.0, 0.1):
        p.append(sphere(0.075, (fx, -0.15, 0.8 - abs(fx) * 0.4), M["hair"], seg=16))
    for sx in (-1, 1):
        p.append(sphere(0.035, (sx * 0.075, -0.19, 0.62), M["black"], scale=(0.75, 0.5, 1.25), seg=16))
        p.append(sphere(0.03, (sx * 0.13, -0.17, 0.57), M["cheek"], scale=(1, 0.4, 0.7), seg=12))
    p.append(cyl(0.13, 0.04, (-0.25, 0, 0.3), M["shield"], rot=(0, math.pi / 2, 0), bev=0.01))
    p.append(sphere(0.04, (-0.28, 0, 0.3), M["gold"], seg=12))
    o = join(p, "Hero")
    o.location, o.rotation_euler, o.scale = (x, y, z), (0, 0, rz), (1.1, 1.1, 1.1)
    return o


def villager(x, y, z, rz):
    p = []
    for sx in (-1, 1):
        p.append(sphere(0.08, (sx * 0.1, -0.03, 0.05), M["boot"], scale=(1, 1.3, 0.7), seg=16))
    p.append(sphere(0.26, (0, 0, 0.32), M["shirt"], scale=(1, 0.9, 1.05)))
    p.append(sphere(0.2, (0, -0.08, 0.28), M["apron"], scale=(1, 0.8, 1)))
    for sx in (-1, 1):
        p.append(sphere(0.06, (sx * 0.26, -0.03, 0.3), M["skin"], seg=16))
    p.append(sphere(0.21, (0, 0, 0.7), M["skin"]))
    p.append(sphere(0.055, (0, -0.21, 0.66), M["skin"], seg=16))
    for sx in (-1, 1):
        p.append(sphere(0.05, (sx * 0.06, -0.19, 0.6), M["stache"], scale=(1.4, 0.6, 0.6), seg=12))
        p.append(sphere(0.028, (sx * 0.08, -0.19, 0.73), M["black"], scale=(0.8, 0.5, 1.2), seg=12))
    p.append(cyl(0.34, 0.035, (0, 0, 0.84), M["straw"], bev=0.01))
    p.append(sphere(0.17, (0, 0, 0.86), M["straw"], scale=(1, 1, 0.8)))
    p.append(torus(0.16, 0.025, (0, 0, 0.9), M["shield"]))
    o = join(p, "Villager")
    o.location, o.rotation_euler, o.scale = (x, y, z), (0, 0, rz), (1.1, 1.1, 1.1)
    return o


hero_obj = hero(*tile_xy(9, 6), -0.04, math.radians(-15))
villager(*tile_xy(4, 8), -0.04, math.radians(35))

# ---------------------------------------------------------------- lighting / camera / render
PROTOS.hide_render = True
bpy.context.view_layer.layer_collection.children["_protos"].exclude = True

world = bpy.data.worlds.new("sky")
scene.world = world
try:
    world.use_nodes = True
except Exception:
    pass
bg = world.node_tree.nodes.get("Background")
bg.inputs["Color"].default_value = hexcol("#cfe8ff")
bg.inputs["Strength"].default_value = 0.9

sun_data = bpy.data.lights.new("sun", "SUN")
sun_data.energy = 4.2
sun_data.angle = math.radians(4)
sun_data.color = (1.0, 0.96, 0.9)
sun = bpy.data.objects.new("sun", sun_data)
sun.rotation_euler = (math.radians(42), 0, math.radians(-35))
ROOT.objects.link(sun)

cam_data = bpy.data.cameras.new("cam")
cam_data.lens = 50
cam = bpy.data.objects.new("cam", cam_data)
ROOT.objects.link(cam)
tilt = math.radians(40)
target = Vector((0, -0.3, 0))
D = 24.0
cam.location = target + Vector((0, -D * math.sin(tilt), D * math.cos(tilt)))
cam.rotation_euler = (tilt, 0, 0)
scene.camera = cam
cam_data.dof.use_dof = True
cam_data.dof.focus_distance = (hero_obj.location - cam.location).length
cam_data.dof.aperture_fstop = 0.06  # tiny f-stop at this scale = tilt-shift miniature look

for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
    try:
        scene.render.engine = eng
        break
    except Exception:
        pass
ee = scene.eevee
for attr, val in (("taa_render_samples", 64), ("use_raytracing", True), ("use_shadows", True)):
    try:
        setattr(ee, attr, val)
    except Exception:
        pass
scene.render.resolution_x, scene.render.resolution_y = 1920, 1080
scene.render.film_transparent = False
try:
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Punchy"
except Exception:
    pass

os.makedirs(os.path.dirname(OUT_PNG), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
scene.render.filepath = OUT_PNG
t = time.time()
bpy.ops.render.render(write_still=True)
print(f"RENDERED {OUT_PNG} in {time.time() - t:.1f}s with {scene.render.engine}")



