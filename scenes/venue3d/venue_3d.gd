extends Node3D
## Real-time 3D museum floor in the toy-diorama style (vertical slice, museum 1).
##
## Everything is built from the venue's authored data (data/venues.json ->
## theme): the SAME rooms, walls, props, exhibits and stations the 2D floor
## draws, rendered from the glTF kit that tools/blender/toybox generates into
## art3d/. Placement mirrors tools/blender/toybox/venue.py `_place`; keep the
## two in step when a rule changes.
##
## Grid -> world: a grid point (gx, gy) is world (gx, height, gy). The camera
## looks toward -Z, so the building's front (large gy) faces the player.

const Npc := preload("res://scenes/venue3d/toy_npc.gd")
const ToyCamera := preload("res://scenes/venue3d/toy_camera.gd")
const TILT_SHIFT := preload("res://scenes/venue3d/tilt_shift.gdshader")
const POP_FONT := preload("res://assets/fonts/Quicksand-Bold.ttf")
const WingSystem := preload("res://scripts/meta/wing_system.gd")

## A visitor paid at ticket window `index` (world position of the counter top).
signal ticket_sold(index: int, at: Vector3)
## A wing finished its renovation reveal (after WingSystem opened it).
signal wing_revealed(wing_id: String)

const FLOOR_TOP := 0.17
const WALL_T := 0.16
const STOREY := 2.8  # tools/blender/toybox/venue.py STOREY: height between theme levels

## kind -> [art3d folder, footprint it was modelled at]
## (tools/blender/toybox/props.py PROPS).
const KIT := {
	"planter": ["props", Vector2(0.5, 0.5)], "bench": ["props", Vector2(1.5, 0.4)],
	"kiosk": ["props", Vector2(0.7, 0.7)], "shelf": ["props", Vector2(2.0, 0.5)],
	"crate": ["props", Vector2(0.8, 0.6)], "cabinet": ["props", Vector2(0.5, 0.7)],
	"vault_door": ["props", Vector2(1.6, 0.24)], "info_desk": ["props", Vector2(2.2, 0.7)],
	"bin": ["props", Vector2(0.3, 0.3)], "desk": ["props", Vector2(1.9, 0.6)],
	"facade": ["props", Vector2(2.4, 0.5)], "ticket_counter": ["props", Vector2(1.55, 0.6)],
	"docent_stand": ["props", Vector2(0.5, 0.4)], "promo_booth": ["props", Vector2(1.9, 0.6)],
	"rope_post": ["props", Vector2(0.2, 0.2)],
	"skeleton": ["exhibits", Vector2(3.2, 1.2)], "mural": ["exhibits", Vector2(2.2, 0.08)],
	"casket": ["exhibits", Vector2(1.0, 1.0)], "statue": ["exhibits", Vector2(1.0, 1.0)],
	"vitrine": ["exhibits", Vector2(0.7, 1.5)], "case": ["exhibits", Vector2(1.5, 0.7)],
	"mammoth": ["exhibits", Vector2(4.0, 2.2)], "whale": ["exhibits", Vector2(6.0, 1.6)],
	"cafe_table": ["props", Vector2(1.2, 1.2)], "telescope": ["props", Vector2(0.8, 0.8)],
	"topiary": ["props", Vector2(0.6, 0.6)], "scaffold": ["props", Vector2(2.0, 0.6)],
	"dust_sheet": ["props", Vector2(1.4, 1.4)], "work_sign": ["props", Vector2(0.8, 0.4)],
	"tank": ["exhibits", Vector2(2.4, 1.1)], "touch_pool": ["exhibits", Vector2(2.2, 1.6)],
	"kelp": ["exhibits", Vector2(0.8, 0.8)], "coral": ["exhibits", Vector2(1.7, 1.2)],
	"hung_skeleton": ["exhibits", Vector2(5.0, 1.4)], "hanging": ["exhibits", Vector2(2.6, 1.0)],
	"plinth": ["exhibits", Vector2(1.0, 1.0)], "armor": ["exhibits", Vector2(1.3, 1.1)],
	"clockwork": ["exhibits", Vector2(1.2, 1.0)], "orrery": ["exhibits", Vector2(1.6, 1.2)],
	"throne": ["exhibits", Vector2(1.6, 1.2)], "rack": ["props", Vector2(1.2, 0.5)],
	"machine": ["props", Vector2(0.7, 0.55)], "chandelier": ["props", Vector2(1.2, 1.2)],
	"banner": ["outdoor", Vector2(0.5, 0.3)], "fountain": ["outdoor", Vector2(2.0, 2.0)],
}
## Decor visual kind (data/decor.json) -> 3D kit piece.
const DECOR_KIT := {"bench": "bench", "fountain": "fountain", "facade": "facade", "rope_line": "rope_post",
	"banner": "banner", "planter": "topiary", "plinth": "plinth", "statue": "statue", "casket": "casket",
	"vitrine": "vitrine", "touch_pool": "touch_pool", "hanging": "chandelier", "case": "case",
	"cafe_table": "cafe_table", "shelf": "shelf", "rug": "", "patch": ""}
const HERO_KINDS := ["skeleton", "casket", "statue", "mammoth", "whale", "hung_skeleton", "tank", "throne", "orrery", "clockwork", "armor"]
const GOLD := Color("#E8B83A")

# Cast palettes: brighter than the 2D cast's, for the toy look.
const SKIN := ["#FFE0C2", "#F7C9A0", "#E3A876", "#C68552", "#94603A", "#6E4529"]
const HAIR := ["#2B2320", "#5A3A22", "#8A5A2B", "#E0B14A", "#E8E4DC", "#C0452E", "#5B3F8C"]
const SHIRT := ["#3A78D8", "#E0524A", "#4FB86A", "#F2A33A", "#8E6BD8", "#2FB0B0", "#E36FA8", "#F2D14A"]
const PANTS := ["#2F3848", "#5A4A3A", "#3F5A84", "#4A3F5A", "#7A6A5A"]
const SHOE := ["#5A3A22", "#2B2B33", "#E8E4DC", "#C0392B"]
const DEPT_VEST := {"ticket": "#C0392B", "gallery": "#2E8B57", "promotions": "#8E44AD", "archive": "#8B5A2B"}

@export var venue_id := "whispering_pines"
@export var visitor_target := 26

var theme: Dictionary = {}
var rooms: Array = []
var W := 14.0
var H := 18.0
var road_z := 0.0
var camera: Camera3D

var _rng := RandomNumberGenerator.new()
var _scenes := {}
var _region: NavigationRegion3D
var _nav_ready := false
var _visitors := 0
var _spawn_clock := 0.0
var _windows: Array = []  # {spot, look}: where a visitor stands to buy a ticket
var _views: Array = []    # {spot, look, hero}
var _door_out := Vector3.ZERO
var _door_in := Vector3.ZERO
var _exit_in := Vector3.ZERO
var _exit_out := Vector3.ZERO
var _vehicles: Array = []
var _open_windows := 1
## Upper floors (data/wings.json layouts), bottom to top. Each entry:
## {id, name, dept, label, rect: Rect2, y, below_y, open, floor, lift, cabin,
##  bottom, top, enter, exit, busy, pieces: [Node3D], derelict: [Node3D], tints}
var floors: Array = []
var _shell: Node3D
var _grand_tier := 0
## Hero exhibits (skeleton, mammoth, whale, casket, statue): {node, scale, dress: []}
var _heroes: Array = []
var exhibit_tier := 1
var _decor_nodes := {}  # slot -> {id, node}

func _ready() -> void:
	_rng.seed = 20260928
	get_viewport().msaa_3d = Viewport.MSAA_4X
	theme = DataLoader.get_venue(venue_id).get("theme", {})
	rooms = theme.get("rooms", [])
	_measure()
	_environment()
	_region = NavigationRegion3D.new()
	add_child(_region)
	_shell = _scene("res://art3d/venues/%s/shell.glb" % venue_id).instantiate()
	_region.add_child(_shell)
	_scatter()
	_read_floors()
	_place_all()
	_place_floors()
	_staff()
	_traffic()
	_camera()
	_tilt_shift()
	_bake_nav()
	for f in floors:
		if not bool(f["open"]):
			_make_derelict(f)
	_apply_grandeur(WingSystem.grandeur_tier(venue_id), false)
	EventBus.wing_renovated.connect(_on_wing_renovated)
	refresh_decor(false)
	EventBus.decor_purchased.connect(_on_decor_changed)

# ------------------------------------------------------------------ layout
func _measure() -> void:
	for r in rooms:
		var rect: Array = r["rect"]
		W = maxf(W, float(rect[0]) + float(rect[2]))
		H = maxf(H, float(rect[1]) + float(rect[3]))
	road_z = H + 5.2 + 1.5
	var door_x := W * 0.5
	for p in theme.get("props", []):
		if str(p.get("kind", "")) == "facade":
			door_x = float(p["at"][0]) + float(p.get("len", 2.4)) * 0.5
	_door_out = Vector3(door_x, 0.08, H + 1.4)
	_door_in = Vector3(door_x, FLOOR_TOP, H - 0.6)
	var lobby := _room_by_role("lobby")
	var ex: Array = lobby.get("exit", [W * 0.5, 3])
	var ex_x := float(lobby["rect"][0]) + float(ex[0])
	_exit_in = Vector3(ex_x, FLOOR_TOP, H - 0.6)
	_exit_out = Vector3(ex_x, 0.08, H + 1.4)

func _room_by_role(role: String) -> Dictionary:
	for r in rooms:
		if str(r.get("role", "")) == role:
			return r
	return {}

func _room_by_id(id: String) -> Dictionary:
	for r in rooms:
		if str(r.get("id", "")) == id:
			return r
	return {}

func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]

func _kit(kind: String) -> Node3D:
	var info: Array = KIT[kind]
	return _scene("res://art3d/%s/%s.glb" % [info[0], kind]).instantiate()

static func _v2(a: Variant, fallback := Vector2.ZERO) -> Vector2:
	if a is Array and (a as Array).size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return fallback

# ------------------------------------------------------------------ props
## Theme level (storey) of the room under grid point p (0 when outside).
func level_at(p: Vector2) -> int:
	for r in rooms:
		var rect: Array = r["rect"]
		if Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3])).has_point(p):
			return int(r.get("level", 0))
	return 0

## The upper floor (floors[] entry) a theme level maps to, or {} for the ground.
func _floor_for_level(lv: int) -> Dictionary:
	if lv <= 0:
		return {}
	for f in floors:
		if int(f.get("level", -1)) == lv:
			return f
	return {}

func _level_y(lv: int) -> float:
	return FLOOR_TOP + float(maxi(lv, 0)) * STOREY

func _place_all() -> void:
	for spec in theme.get("props", []) + theme.get("exhibits", []):
		var kind := str(spec.get("kind", ""))
		var anchor_pt := _v2(spec.get("anchor", spec.get("at")))
		var lv := level_at(anchor_pt)
		var y := _level_y(lv)
		var fl := _floor_for_level(lv)
		if KIT.has(kind):
			var node := _place(kind, spec, y)
			if kind in HERO_KINDS:
				_heroes.append({"node": node, "scale": node.scale, "dress": []})
			if not fl.is_empty():
				(fl["pieces"] as Array).append(node)
				if spec.has("views"):
					(fl["dust"] as Array).append({"at": spec.get("at"), "size": spec.get("size", [1.0, 1.0])})
		if spec.has("barrier"):
			_rope_line(spec["barrier"], y, fl)
		if spec.has("views") and spec.has("anchor"):
			var anchor := _v2(spec["anchor"])
			var dest: Array = fl["views"] if not fl.is_empty() else _views
			for v in spec["views"]:
				var p := anchor + _v2(v)
				dest.append({"spot": Vector3(p.x, y, p.y), "look": Vector3(anchor.x, y + 0.85, anchor.y),
					"hero": kind in HERO_KINDS, "floor": floors.find(fl) + 1 if not fl.is_empty() else 0})
	for room in rooms:
		var origin := _v2(room["rect"])
		var lv := int(room.get("level", 0))
		var fl := _floor_for_level(lv)
		if str(room.get("role", "")) == "exhibit":
			for s in room.get("stations", []):
				var st := _place("docent_stand", {"at": [origin.x + float(s[0]), origin.y + float(s[1])]}, _level_y(lv))
				if not fl.is_empty():
					(fl["pieces"] as Array).append(st)
		var q: Dictionary = room.get("queue", {})
		for st in q.get("stations", []):
			var base := _v2(_room_by_id(str(st.get("room", ""))).get("rect", room["rect"]))
			var at := base + _v2(st["at"])
			var f := _v2(st.get("front"), Vector2(1, 0))
			var counter := _place("ticket_counter", {"at": [at.x + f.x * 0.15, at.y + f.y * 0.15], "front": [f.x, f.y]})
			var spot := at + f * 0.85
			_windows.append({"spot": Vector3(spot.x, FLOOR_TOP, spot.y), "look": Vector3(at.x, 0.5, at.y),
				"clerk": Vector3(at.x - f.x * 0.55, FLOOR_TOP, at.y - f.y * 0.55), "front": f,
				"top": Vector3(at.x, FLOOR_TOP + 0.75, at.y), "nodes": [counter]})

func _place(kind: String, spec: Dictionary, base := FLOOR_TOP, parent: Node = null) -> Node3D:
	var node := _kit(kind)
	(parent if parent != null else _region).add_child(node)
	var fp: Vector2 = KIT[kind][1]
	var at := _v2(spec.get("at"))
	if kind == "mural":
		var len_m := float(spec.get("len", 2.2))
		node.position = Vector3(at.x + len_m * 0.5, base + 0.55, at.y + WALL_T * 0.5 + 0.05)
		return node
	if kind == "vault_door" or kind == "facade":
		var length := float(spec.get("len", fp.x))
		var vertical := str(spec.get("axis", "x")) == "y"
		var c := Vector2(at.x, at.y + length * 0.5) if vertical else Vector2(at.x + length * 0.5, at.y)
		node.position = Vector3(c.x, base, c.y)
		node.rotation.y = PI * 0.5 if vertical else 0.0
		return node
	var size := Vector2.ZERO
	if spec.has("size"):
		size = _v2(spec["size"])
	elif spec.has("len") or kind == "bench":
		var l := float(spec.get("len", 1.5))
		size = Vector2(0.4, l) if str(spec.get("axis", "x")) == "y" else Vector2(l, 0.4)
	if size == Vector2.ZERO:  # point-placed piece
		node.position = Vector3(at.x, base, at.y)
		if spec.has("front"):
			var f := _v2(spec["front"])
			node.rotation.y = atan2(f.x, f.y)
		return node
	var rotate := (fp.x >= fp.y) != (size.x >= size.y)
	node.position = Vector3(at.x + size.x * 0.5, base, at.y + size.y * 0.5)
	node.rotation.y = PI * 0.5 if rotate else 0.0
	var k := maxf(size.x, size.y) / maxf(fp.x, fp.y)
	var short := clampf(minf(size.x, size.y) / minf(fp.x, fp.y), 0.6, 1.4)
	node.scale = Vector3(k, 1.0, short)  # local axes, applied before the turn
	return node

func _rope_line(barrier: Dictionary, y := FLOOR_TOP, fl: Dictionary = {}) -> void:
	var a := _v2(barrier.get("from"))
	var b := _v2(barrier.get("to"))
	var posts := maxi(2, int(barrier.get("posts", 3)))
	var rope := StandardMaterial3D.new()
	rope.albedo_color = Color("#B0263A")
	rope.roughness = 0.5
	for i in posts:
		var p := a.lerp(b, float(i) / float(posts - 1))
		var post := _place("rope_post", {"at": [p.x, p.y]}, y)
		if not fl.is_empty():
			(fl["pieces"] as Array).append(post)
		if i > 0:
			var q := a.lerp(b, float(i - 1) / float(posts - 1))
			var seg := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.02
			cyl.bottom_radius = 0.02
			cyl.height = p.distance_to(q)
			cyl.radial_segments = 8
			seg.mesh = cyl
			seg.material_override = rope
			_region.add_child(seg)
			var mid := (p + q) * 0.5
			seg.position = Vector3(mid.x, y + 0.5, mid.y)
			if not fl.is_empty():
				(fl["pieces"] as Array).append(seg)
			var d := p - q
			seg.rotation = Vector3(0.0, -atan2(d.y, d.x), PI * 0.5)

# ------------------------------------------------------------------ people
func _look(role := "visitor", dept := "") -> Dictionary:
	var pick := func(arr: Array) -> String: return str(arr[_rng.randi() % arr.size()])
	var look := {"skin": pick.call(SKIN), "hair": pick.call(HAIR), "shirt": pick.call(SHIRT),
		"pants": pick.call(PANTS), "shoe": pick.call(SHOE), "acc": []}
	var acc: Array = look["acc"]
	if role == "staff":
		look["shirt"] = "#FFF7E6"
		look["pants"] = "#2F3848"
		look["acc_vest"] = DEPT_VEST.get(dept, "#C0392B")
		acc.append("acc_vest")
		if dept == "archive":
			acc.append("acc_cap")
			look["acc_cap"] = "#8B5A2B"
		return look
	var r := _rng.randf()
	if r < 0.18:
		acc.append("acc_hat")
	elif r < 0.36:
		acc.append("acc_cap")
		look["acc_cap"] = pick.call(SHIRT)
	elif r < 0.5:
		acc.append("acc_bow")
	if _rng.randf() < 0.25:
		acc.append("acc_backpack")
		look["acc_pack"] = pick.call(SHIRT)
	if _rng.randf() < 0.2:
		acc.append("acc_glasses")
	if _rng.randf() < 0.18:
		acc.append("acc_camera")
	if _rng.randf() < 0.15:
		acc.append("acc_bag")
	var age := _rng.randf()
	if age < 0.2:
		look["scale"] = 0.78  # kids
	elif age > 0.88:
		look["hair"] = "#E8E4DC"
	return look

func _spawn(look: Dictionary, at: Vector3) -> Npc:
	var n := Npc.new()
	add_child(n)
	n.global_position = at
	n.setup(look)
	return n

func _staff() -> void:
	for w in _windows:
		var clerk := _spawn(_look("staff", "ticket"), w["clerk"])
		clerk.face(w["spot"])
		(w["nodes"] as Array).append(clerk)
	for room in rooms:
		var origin := _v2(room["rect"])
		var dept := str(room.get("dept", ""))
		var lv := int(room.get("level", 0))
		var y := _level_y(lv)
		var fl := _floor_for_level(lv)
		var hired: Array = []
		for s in room.get("stations", []):
			var p := origin + _v2(s) + (Vector2(0.35, 0.1) if dept == "gallery" else Vector2.ZERO)
			var n := _spawn(_look("staff", dept), Vector3(p.x, y, p.y))
			n.face(Vector3(p.x, y, p.y + 1.0))
			hired.append(n)
		if room.has("marketer"):
			var m := origin + _v2(room["marketer"])
			var mk := _spawn(_look("staff", "promotions"), Vector3(m.x, y, m.y))
			mk.face(_door_in + Vector3(0, 0, 3))
			hired.append(mk)
		var store: Dictionary = room.get("store", {})
		if store.has("home"):
			var h := origin + _v2(store["home"])
			var ar := _spawn(_look("staff", "archive"), Vector3(h.x, y, h.y))
			ar.face(Vector3(h.x + 1.0, y, h.y))
			hired.append(ar)
		if not fl.is_empty():
			(fl["staff"] as Array).append_array(hired)
	for f in floors:
		_floor_staff(f)

func _process(delta: float) -> void:
	_drive(delta)
	if not _nav_ready:
		return
	_spawn_clock -= delta
	if _visitors < visitor_target and _spawn_clock <= 0.0:
		_spawn_clock = _rng.randf_range(0.6, 1.8)
		var side := -7.0 if _rng.randf() < 0.5 else W + 7.0
		_visit(_spawn(_look(), Vector3(side, 0.1, road_z - 2.35)))

## A visitor's day: in through the entrance, buy a ticket, look at two or
## three exhibits (cheering at the hero pieces), then out through the exit.
## `inside` starts them already past the ticket desk (the opening crowd).
func _visit(n: Npc, inside := false) -> void:
	_visitors += 1
	n.speed = _rng.randf_range(0.9, 1.25)
	if not inside:
		await _walk(n, _door_out + Vector3(_rng.randf_range(-0.6, 0.6), 0, 0))
		if not _alive(n):
			return
		await _walk(n, _door_in)
		if not _alive(n):
			return
	if not inside and not _windows.is_empty():
		var wi := _rng.randi() % mini(_open_windows, _windows.size())
		var w: Dictionary = _windows[wi]
		await _walk(n, w["spot"] + Vector3(_rng.randf_range(-0.2, 0.2), 0, _rng.randf_range(-0.2, 0.2)))
		if not _alive(n):
			return
		n.face(w["look"])
		await _wait(_rng.randf_range(1.2, 2.6))
		if not _alive(n):
			return
		ticket_sold.emit(wi, w["top"])
	for i in _rng.randi_range(2, 3):
		var pool := _open_views()
		if pool.is_empty():
			break
		var v: Dictionary = pool[_rng.randi() % pool.size()]
		var want := int(v.get("floor", 0))
		var here := int(n.get_meta("floor", 0))
		if want != here:
			await _travel(n, here, want)
		if not _alive(n):
			return
		await _walk(n, v["spot"])
		if not _alive(n):
			return
		n.face(v["look"])
		if bool(v["hero"]) and _rng.randf() < 0.5:
			n.play("cheer")
		await _wait(_rng.randf_range(2.0, 4.5))
		if not _alive(n):
			return
	if int(n.get_meta("floor", 0)) != 0:
		await _travel(n, int(n.get_meta("floor", 0)), 0)
	for to in [_exit_in, _exit_out]:
		if not _alive(n):
			return
		await _walk(n, to)
	if not _alive(n):
		return
	var leave_x := -7.0 if n.global_position.x < W * 0.5 else W + 7.0
	await _walk(n, Vector3(leave_x, 0.1, road_z - 2.35))
	if not _alive(n):
		return
	_visitors -= 1
	n.queue_free()

## Wait on a Timer CHILD rather than a SceneTreeTimer: a coroutine suspended on
## a tree timer (or a tween) forms a reference cycle with it, and if the museum
## is torn down mid-wait (graduation, tab switch, quit) the pair is never freed.
## A child Timer dies with the museum and takes the suspended call with it.
func _wait(secs: float) -> void:
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = maxf(secs, 0.01)
	add_child(t)
	_waits.append(t)
	t.start()
	await t.timeout
	_waits.erase(t)
	if is_instance_valid(t):
		t.queue_free()

var _waits: Array = []

## Run `cb` after `secs`, unless the museum is gone by then.
func _after(secs: float, cb: Callable) -> void:
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = maxf(secs, 0.01)
	add_child(t)
	t.timeout.connect(func() -> void:
		cb.call()
		t.queue_free())
	t.start()

## A visitor's coroutine carries on only while it and the museum still exist.
func _alive(n: Object) -> bool:
	return not _closing and is_instance_valid(n)

var _closing := false

## Leaving the tree: stop every visitor's day. Walkers suspended on `arrived`
## are released (they check _alive and return), so no coroutine is left holding
## this script when the museum is torn down (graduation, tab switch, quit).
func _on_decor_changed(v: String, _decor_id: String) -> void:
	if v == venue_id:
		refresh_decor()

func _exit_tree() -> void:
	_closing = true
	if EventBus.decor_purchased.is_connected(_on_decor_changed):
		EventBus.decor_purchased.disconnect(_on_decor_changed)
	if EventBus.wing_renovated.is_connected(_on_wing_renovated):
		EventBus.wing_renovated.disconnect(_on_wing_renovated)
	# A coroutine awaiting a signal of an object that is then freed is never
	# released (Godot keeps its GDScriptFunctionState). Wake every suspended
	# walker and waiter now; each sees _closing and returns.
	for c in get_children():
		if c is Npc:
			(c as Npc).arrived.emit()
	for t in _waits.duplicate():
		if is_instance_valid(t):
			(t as Timer).timeout.emit()
	_waits.clear()

## Ground views plus every open floor's; upper floors weighted up so the new
## wing visibly fills once it opens.
func _open_views() -> Array:
	var out: Array = _views.duplicate()
	for f in floors:
		# A storey is only visitable once it is open AND every floor below it
		# is reachable (lifts chain upward floor by floor).
		if not bool(f["open"]) or not bool(f["has_lift"]):
			break
		out += f["views"]
		out += f["views"]
	return out

func _walk(n: Npc, to: Vector3) -> void:
	n.walk_to(to)
	if n.is_walking():
		await n.arrived

# ------------------------------------------------------------------ scatter (instanced greenery)
## Trees and bushes come as spots on the grounds node (glTF extras, flat
## [gx, gy, rot, scale, ...]) and are drawn as MultiMeshes: one shared mesh,
## many transforms. Outside the navigation region: nobody walks into a hedge.
func _scatter() -> void:
	var g := _shell.find_child("grounds", true, false)
	if g == null:
		return
	var ex: Dictionary = g.get_meta("extras", {})
	_instance_field(str(ex.get("trees_kind", "tree")), ex.get("trees", []))
	_instance_field("bush", ex.get("bushes", []))

func _instance_field(kind: String, flat: Array) -> void:
	var n := flat.size() / 4
	var path := "res://art3d/outdoor/%s.glb" % kind
	if n <= 0 or not ResourceLoader.exists(path):
		return
	var src: Node3D = _scene(path).instantiate()
	for node in src.find_children("*", "MeshInstance3D", true, false) + ([src] if src is MeshInstance3D else []):
		var mi := node as MeshInstance3D
		var local := mi.global_transform if mi.is_inside_tree() else mi.transform
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mi.mesh
		mm.instance_count = n
		for i in n:
			var basis := Basis(Vector3.UP, float(flat[i * 4 + 2])).scaled(Vector3.ONE * float(flat[i * 4 + 3]))
			mm.set_instance_transform(i, Transform3D(basis, Vector3(float(flat[i * 4]), 0.0, float(flat[i * 4 + 1]))) * local)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Scatter_%s" % kind
		mmi.multimesh = mm
		add_child(mmi)
	src.free()

# ------------------------------------------------------------------ floors (wings)
## Upper floors come from data/wings.json layouts; the shell carries their
## architecture as nodes named floor_<id>, lift_<id> and cabin_<id>.
func _read_floors() -> void:
	var below := FLOOR_TOP
	for w in WingSystem.wings(venue_id):
		var lay: Dictionary = {}
		if (w as Dictionary).has("layout"):
			lay = w["layout"]
		elif int(w.get("floor", 0)) >= 1:
			# Theme storeys: the shell carries each one's layout as glTF extras.
			var node := _shell.find_child("floor_" + str(w["id"]), true, false)
			if node == null:
				continue
			var ex: Dictionary = node.get_meta("extras", {})
			lay = {"rect": ex.get("rect", [0, 0, W, 4]), "y": ex.get("y", _level_y(int(w["floor"])))}
			if ex.has("lift_at"):
				lay["lift"] = {"at": ex["lift_at"], "enter": ex["enter"], "exit": ex["exit"]}
			if not (w as Dictionary).has("dept"):
				w["dept"] = str(ex.get("dept", "gallery"))
		else:
			continue
		var r: Array = lay["rect"]
		var lift: Dictionary = lay.get("lift", {})
		var y := float(lay.get("y", 3.0))
		var at := _v2(lift.get("at"))
		var f := {
			"id": str(w["id"]), "name": str(w.get("name", "")), "dept": str(w.get("dept", "gallery")),
			"label": str(w.get("label", "")), "rect": Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])),
			"y": y, "below_y": below, "open": WingSystem.is_open(venue_id, str(w["id"])),
			"floor": _shell.find_child("floor_" + str(w["id"]), true, false),
			"lift": _shell.find_child("lift_" + str(w["id"]), true, false),
			"cabin": _shell.find_child("cabin_" + str(w["id"]), true, false),
			"bottom": below, "top": y,
			"lift_at": Vector3(at.x, below, at.y),
			"enter": Vector3(_v2(lift.get("enter")).x, below, _v2(lift.get("enter")).y),
			"exit": Vector3(_v2(lift.get("exit")).x, y, _v2(lift.get("exit")).y),
			"busy": false, "pieces": [], "staff": [], "derelict": [], "tints": [], "views": [],
			"layout": lay, "has_lift": lift.has("at"), "dust": [],
			"level": int(w.get("floor", 1)) if not (w as Dictionary).has("layout") else -1,
		}
		for spec in lay.get("exhibits", []):
			(f["dust"] as Array).append({"at": spec.get("at"), "size": spec.get("size", [1.0, 1.0])})
		floors.append(f)
		below = y

func floor_by_id(id: String) -> Dictionary:
	for f in floors:
		if str(f["id"]) == id:
			return f
	return {}

func _place_floors() -> void:
	for f in floors:
		var lay: Dictionary = f["layout"]
		var y := float(f["y"])
		for spec in lay.get("props", []) + lay.get("exhibits", []):
			var kind := str(spec.get("kind", ""))
			if KIT.has(kind):
				var piece := _place(kind, spec, y)
				(f["pieces"] as Array).append(piece)
				if kind in HERO_KINDS:
					_heroes.append({"node": piece, "scale": piece.scale, "dress": []})
			if spec.has("views") and spec.has("anchor"):
				var anchor := _v2(spec["anchor"])
				for v in spec["views"]:
					var p := anchor + _v2(v)
					(f["views"] as Array).append({"spot": Vector3(p.x, y, p.y), "look": Vector3(anchor.x, y + 1.0, anchor.y),
						"hero": kind in HERO_KINDS, "floor": floors.find(f) + 1})
		for st in lay.get("stations", []):
			(f["pieces"] as Array).append(_place("docent_stand", {"at": st}, y))

## Floor index 0 is the ground; floor i (1-based) is floors[i - 1].
func _floor_staff(f: Dictionary) -> void:
	var lay: Dictionary = f["layout"]
	var y := float(f["y"])
	for st in lay.get("stations", []):
		var p := _v2(st) + Vector2(0.35, 0.1)
		var n := _spawn(_look("staff", str(f["dept"])), Vector3(p.x, y, p.y))
		n.face(Vector3(p.x, y, p.y + 1.0))
		(f["staff"] as Array).append(n)
	if lay.has("marketer"):
		var m := _v2(lay["marketer"])
		var n2 := _spawn(_look("staff", "promotions"), Vector3(m.x, y, m.y))
		n2.face(Vector3(m.x, y, m.y + 1.0))
		(f["staff"] as Array).append(n2)

## Derelict: the floor is there but grey, its exhibits under dust sheets, with
## a scaffold, crates and a sign. Dressing is parented outside the navigation
## region so renovating never leaves holes in the baked walkable area.
func _make_derelict(f: Dictionary) -> void:
	for node in [f["floor"], f["lift"], f["cabin"]]:
		if node != null:
			_tint_grey(node as Node3D, f["tints"])
	var y := float(f["y"])
	var rect: Rect2 = f["rect"]
	for piece in f["pieces"]:
		(piece as Node3D).visible = false
	for n in f["staff"]:
		(n as Node3D).visible = false
	var dress: Array = f["derelict"]
	for spec in f["dust"]:
		var at := _v2(spec.get("at"))
		var size := _v2(spec.get("size"), Vector2(1.0, 1.0))
		var sheet := _place("dust_sheet", {"at": [at.x + size.x * 0.5, at.y + size.y * 0.5]}, y, self)
		sheet.scale = Vector3(clampf(size.x / 1.4, 0.6, 3.0), clampf(maxf(size.x, size.y) / 2.2, 0.8, 1.8), clampf(size.y / 1.4, 0.6, 2.0))
		sheet.rotation.y = _rng.randf_range(-0.2, 0.2)
		dress.append(sheet)
	dress.append(_place("scaffold", {"at": [rect.position.x + 1.3, rect.position.y + 0.5]}, y, self))
	dress.append(_place("scaffold", {"at": [rect.end.x - 1.3, rect.position.y + 0.5]}, y, self))
	for i in 4:
		var c := _place("crate", {"at": [rect.position.x + 1.0 + _rng.randf() * (rect.size.x - 2.0),
			rect.position.y + 2.0 + _rng.randf() * (rect.size.y - 3.5)]}, y, self)
		c.rotation.y = _rng.randf_range(0.0, TAU)
		dress.append(c)
	var sign_at := Vector2(rect.get_center().x, rect.end.y - 1.2)
	dress.append(_place("work_sign", {"at": [sign_at.x, sign_at.y]}, y, self))
	var sign := Label3D.new()
	sign.font = POP_FONT
	sign.font_size = 56
	sign.outline_size = 16
	sign.pixel_size = 0.006
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.no_depth_test = true
	sign.modulate = Color("#FFF4D6")
	sign.outline_modulate = Color("#3A2A10")
	sign.position = Vector3(sign_at.x, y + 1.7, sign_at.y)
	add_child(sign)
	f["sign"] = sign
	dress.append(sign)
	refresh_signs()

## Sign text follows the wing's status (locked -> ready to renovate).
func refresh_signs() -> void:
	for f in floors:
		var sign_v: Variant = f.get("sign")
		if sign_v == null or not is_instance_valid(sign_v):
			continue
		var sign := sign_v as Label3D
		var w := WingSystem.wing(venue_id, str(f["id"]))
		var ready := WingSystem.status(venue_id, str(f["id"])) == WingSystem.STATUS_READY
		sign.text = "%s\n%s" % [str(f["name"]), "Tap to renovate!" if ready else WingSystem.requirement_text(venue_id, w)]
		sign.modulate = Color("#FFE680") if ready else Color("#FFF4D6")

func _tint_grey(root: Node3D, out: Array) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false) + ([root] if root is MeshInstance3D else []):
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if src == null:
				continue
			var grey := src.duplicate() as StandardMaterial3D
			var c := src.albedo_color
			var l := c.get_luminance()
			grey.albedo_color = Color(l, l, l * 1.02, c.a).darkened(0.18)
			grey.roughness = 0.9
			grey.metallic = 0.0
			mi.set_surface_override_material(i, grey)
			out.append({"mi": mi, "i": i, "mat": grey, "from": grey.albedo_color, "to": c})

func _on_wing_renovated(vid: String, wing_id: String) -> void:
	if vid != venue_id:
		return
	var f := floor_by_id(wing_id)
	if not f.is_empty() and not bool(f["open"]):
		_reveal(f)
	_apply_grandeur(WingSystem.grandeur_tier(venue_id), true)

## The renovation moment: dust sheets fly off, colour floods back in, the
## exhibits pop up, staff arrive and confetti goes up.
func _reveal(f: Dictionary) -> void:
	f["open"] = true
	for node in f["derelict"]:
		var n := node as Node3D
		if not is_instance_valid(n):
			continue
		var tw := n.create_tween()
		tw.tween_property(n, "position:y", n.position.y + 2.5, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(n, "scale", Vector3.ONE * 0.05, 0.45)
		tw.tween_callback(n.queue_free)
	(f["derelict"] as Array).clear()
	var tints: Array = f["tints"]
	var flood := create_tween()
	flood.tween_method(func(t: float) -> void:
		for e in tints:
			(e["mat"] as StandardMaterial3D).albedo_color = (e["from"] as Color).lerp(e["to"], t), 0.0, 1.0, 1.2)
	flood.tween_callback(func() -> void:
		for e in tints:
			if is_instance_valid(e["mi"]):
				(e["mi"] as MeshInstance3D).set_surface_override_material(int(e["i"]), null)
		tints.clear())
	var delay := 0.35
	for piece in f["pieces"]:
		var n := piece as Node3D
		var target := n.scale
		n.scale = target * 0.05
		n.visible = true
		var tw := n.create_tween()
		tw.tween_interval(delay)
		tw.tween_property(n, "scale", target, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		delay += 0.08
	for n in f["staff"]:
		(n as Node3D).visible = true
	var rect: Rect2 = f["rect"]
	var centre := Vector3(rect.get_center().x, float(f["y"]) + 1.5, rect.get_center().y)
	burst(centre, 90)
	pop_text(centre + Vector3(0, 1.0, 0), "%s OPEN!" % str(f["name"]).to_upper(), Color("#FFE680"), true)
	_after(1.6, func() -> void:
		set_exhibit_tier(exhibit_tier)
		wing_revealed.emit(str(f["id"])))

# ------------------------------------------------------------------ lifts
## Take `n` from floor index `from` to `to` (0 = ground), one lift at a time.
func _travel(n: Npc, from: int, to: int) -> void:
	var at := from
	while at != to and _alive(n):
		if to > at:
			await _ride(n, floors[at], true)
			at += 1
		else:
			await _ride(n, floors[at - 1], false)
			at -= 1
	if is_instance_valid(n):
		n.set_meta("floor", at)

func _ride(n: Npc, f: Dictionary, up: bool) -> void:
	await _walk(n, f["enter"] if up else f["exit"])
	while bool(f["busy"]) and _alive(n):
		await _wait(0.4)
	if not _alive(n):
		return
	f["busy"] = true
	var cabin := f["cabin"] as Node3D
	var from_y := float(f["bottom"] if up else f["top"])
	var to_y := float(f["top"] if up else f["bottom"])
	if cabin and absf(cabin.global_position.y - from_y) > 0.01:
		var fetch := create_tween()
		fetch.tween_method(func(y: float) -> void: cabin.global_position.y = y,
			cabin.global_position.y, from_y, 0.8).set_trans(Tween.TRANS_SINE)
		await _wait(0.8)
	var la: Vector3 = f["lift_at"]
	if not is_instance_valid(n):
		f["busy"] = false
		return
	n.global_position = Vector3(la.x, from_y, la.z)
	n.face(Vector3(la.x, from_y, la.z + (-1.0 if up else 1.0)))
	var ride := create_tween()
	var ride_secs := absf(to_y - from_y) * 0.45 + 0.5
	ride.tween_method(func(y: float) -> void:
		if is_instance_valid(n):
			n.global_position = Vector3(la.x, y, la.z)
		if cabin:
			cabin.global_position.y = y, from_y, to_y, ride_secs).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _wait(ride_secs)
	if not _alive(n):
		f["busy"] = false
		return
	f["busy"] = false
	if is_instance_valid(n):
		await _walk(n, f["exit"] if up else f["enter"])

# ------------------------------------------------------------------ grandeur
## Exterior dressing by tier: II banners, III red carpet and spotlights,
## IV gold statues and a gold dome, V fireworks.
func _apply_grandeur(tier: int, celebrate: bool) -> void:
	var before := _grand_tier
	_grand_tier = tier
	for t: int in [2, 3, 4]:
		var node := _shell.find_child("grand_%d" % t, true, false) as Node3D
		if node:
			var show: bool = tier >= t
			if show and not node.visible and celebrate:
				node.visible = true
				var s0 := node.scale
				node.scale = Vector3(1, 0.05, 1)
				node.create_tween().tween_property(node, "scale", s0, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			node.visible = show
	var dome := _shell.find_child("dome", true, false) as MeshInstance3D
	if dome:
		if tier >= 4:
			var gold := StandardMaterial3D.new()
			gold.albedo_color = GOLD
			gold.metallic = 0.85
			gold.roughness = 0.22
			dome.material_override = gold
		else:
			dome.material_override = null
	if celebrate and tier > before and camera:
		var names := WingSystem.grandeur_names()
		var title := str((names[tier - 1] as Dictionary).get("name", "")) if tier - 1 < names.size() else ""
		var at := Vector3(W * 0.5, 4.0, H + 1.0)
		burst(at, 120)
		pop_text(at + Vector3(0, 1.4, 0), "GRANDEUR: %s!" % title.to_upper(), Color("#FFD34D"), true)
	if tier >= 5:
		_fireworks()

var _fireworks_on := false
func _fireworks() -> void:
	if _fireworks_on:
		return
	_fireworks_on = true
	var t := Timer.new()
	t.wait_time = 2.2
	t.autostart = true
	add_child(t)
	t.timeout.connect(func() -> void:
		var z := 0.0
		if not floors.is_empty():
			z = ((floors.back() as Dictionary)["rect"] as Rect2).position.y
		burst(Vector3(_rng.randf_range(0.0, W), 11.0 + _rng.randf() * 3.0, z + _rng.randf_range(-2.0, 6.0)), 60, true))

## Confetti (or a firework shell when `sky`) at a world point.
func burst(at: Vector3, amount := 80, sky := false) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = 1.6
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 180.0 if sky else 70.0
	p.initial_velocity_min = 3.0 if sky else 4.0
	p.initial_velocity_max = 6.0 if sky else 8.0
	p.gravity = Vector3(0, -2.5 if sky else -9.0, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.09)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = m
	p.mesh = quad
	var grad := Gradient.new()
	var cols := [Color("#FF5A5F"), Color("#FFD34D"), Color("#4FB86A"), Color("#3A78D8"), Color("#E36FA8")]
	grad.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	grad.colors = PackedColorArray(cols)
	p.color_initial_ramp = grad
	add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.5).timeout.connect(p.queue_free)

## Ground height under a focus point: the highest floor whose rect covers z.
func height_at(z: float) -> float:
	var h := 0.0
	for f in floors:
		var r: Rect2 = f["rect"]
		if z <= r.end.y + 1.0 and z >= r.position.y - 1.0:
			h = float(f["y"])
	return h

## World point on the floor the player tapped, and which floor it is.
func pick(screen: Vector2) -> Dictionary:
	if camera == null:
		return {}
	var o := camera.project_ray_origin(screen)
	var d := camera.project_ray_normal(screen)
	for i in range(floors.size() - 1, -1, -1):
		var f: Dictionary = floors[i]
		var hit: Variant = Plane(Vector3.UP, float(f["y"])).intersects_ray(o, d)
		if hit != null and (f["rect"] as Rect2).has_point(Vector2((hit as Vector3).x, (hit as Vector3).z)):
			var dept := str(f["dept"])
			if int(f["level"]) > 0:
				var d2 := dept_at(hit, int(f["level"]))
				dept = d2 if d2 != "" else dept
			return {"point": hit, "wing": str(f["id"]), "open": bool(f["open"]), "dept": dept}
	var g: Variant = Plane(Vector3.UP, FLOOR_TOP).intersects_ray(o, d)
	if g == null:
		return {}
	return {"point": g, "wing": "", "open": true, "dept": dept_at(g)}

# ------------------------------------------------------------------ decor
## Placed decor (DecorSystem) stands at the theme's decor anchor for its slot.
## New pieces pop in with confetti; removed ones leave. Cheap to call often.
func refresh_decor(celebrate := true) -> void:
	var placed: Dictionary = GameState.venue_state(venue_id).get("decor", {})
	var anchors: Array = theme.get("decor_anchors", [])
	for slot in _decor_nodes.keys():
		var e: Dictionary = _decor_nodes[slot]
		if str(placed.get(str(slot), "")) != str(e["id"]):
			if is_instance_valid(e["node"]):
				(e["node"] as Node).queue_free()
			_decor_nodes.erase(slot)
	for slot_key in placed.keys():
		var slot := int(slot_key)
		var id := str(placed[slot_key])
		if _decor_nodes.has(slot) or slot >= anchors.size():
			continue
		var def: Dictionary = DataLoader.get_decor(id)
		var vis: Dictionary = def.get("visual", {})
		var kind := str(DECOR_KIT.get(str(vis.get("kind", "")), "planter"))
		var at := _v2(anchors[slot])
		var y := _level_y(level_at(at))
		var node: Node3D
		if kind == "":
			node = _decor_rug(at, y, vis)
		else:
			node = _place(kind, {"at": [at.x, at.y]}, y, self)
		_decor_nodes[slot] = {"id": id, "node": node}
		if celebrate:
			var s0 := node.scale
			node.scale = s0 * 0.05
			node.create_tween().tween_property(node, "scale", s0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			burst(Vector3(at.x, y + 1.2, at.y), 50)
			pop_text(Vector3(at.x, y + 1.8, at.y), str(def.get("name", "")), Color("#FFE680"))

func _decor_rug(at: Vector2, y: float, vis: Dictionary) -> Node3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.8, 0.03, 1.3)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(str(vis.get("col", "#C0392B"))) if str(vis.get("col", "#")).begins_with("#") else Color("#C0392B")
	m.roughness = 0.8
	bm.material = m
	mi.mesh = bm
	add_child(mi)
	mi.position = Vector3(at.x, y + 0.02, at.y)
	return mi

# ------------------------------------------------------------------ hero exhibit tiers
## Hero exhibits grow with the gallery: tier 1 as found, 2 adds a light beam and
## brass rim, 3 a gold ring and more size, 4 sparkles. The floor calls this from
## the gallery's value track, so upgrading the department is visible on the
## museum's star pieces, not only in a number.
func set_exhibit_tier(tier: int, celebrate := false) -> void:
	tier = clampi(tier, 1, 4)
	var grew := tier > exhibit_tier
	exhibit_tier = tier
	for h in _heroes:
		var node := h["node"] as Node3D
		if not is_instance_valid(node):
			continue
		for d in h["dress"]:
			if is_instance_valid(d):
				(d as Node).queue_free()
		(h["dress"] as Array).clear()
		if not node.visible:
			continue  # a derelict floor's piece is dressed when it is revealed
		var target: Vector3 = (h["scale"] as Vector3) * (1.0 + 0.09 * float(tier - 1))
		if celebrate and grew:
			var tw := node.create_tween()
			tw.tween_property(node, "scale", target * 1.12, 0.18).set_trans(Tween.TRANS_BACK)
			tw.tween_property(node, "scale", target, 0.25)
		else:
			node.scale = target
		var aabb := _world_aabb(node)
		var c := aabb.get_center()
		var r := maxf(aabb.size.x, aabb.size.z) * 0.5
		var base_y := node.global_position.y
		if tier >= 2:
			(h["dress"] as Array).append(_beam(Vector3(c.x, base_y, c.z), r, aabb.size.y))
			(h["dress"] as Array).append(_rim(Vector3(c.x, base_y + 0.02, c.z), r + 0.15, Color("#C9A04A")))
		if tier >= 3:
			(h["dress"] as Array).append(_rim(Vector3(c.x, base_y + 0.06, c.z), r + 0.3, GOLD))
		if tier >= 4:
			(h["dress"] as Array).append(_sparkles(Vector3(c.x, base_y + aabb.size.y * 0.6, c.z), r))
		if celebrate and grew:
			pop_text(Vector3(c.x, base_y + aabb.size.y + 0.6, c.z), "EXHIBIT UPGRADED!", Color("#FFE680"), true)
			burst(Vector3(c.x, base_y + aabb.size.y, c.z), 40)

func _world_aabb(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for n in node.find_children("*", "MeshInstance3D", true, false) + ([node] if node is MeshInstance3D else []):
		var mi := n as MeshInstance3D
		var box := mi.global_transform * mi.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out

## A soft vertical light beam (cheap: one unshaded, additive cone).
func _beam(at: Vector3, r: float, h: float) -> Node3D:
	var mi := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = r * 0.35
	cone.bottom_radius = r * 1.05
	cone.height = h + 2.2
	cone.radial_segments = 24
	cone.cap_top = false
	cone.cap_bottom = false
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(1.0, 0.92, 0.6, 0.16)
	cone.material = m
	mi.mesh = cone
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at + Vector3(0, (h + 2.2) * 0.5, 0)
	return mi

func _rim(at: Vector3, r: float, col: Color) -> Node3D:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = r
	t.outer_radius = r + 0.09
	t.rings = 48
	t.ring_segments = 8
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = 0.8
	m.roughness = 0.25
	t.material = m
	mi.mesh = t
	add_child(mi)
	mi.global_position = at
	mi.scale = Vector3(1, 0.5, 1)
	return mi

func _sparkles(at: Vector3, r: float) -> Node3D:
	var p := CPUParticles3D.new()
	p.amount = 24
	p.lifetime = 1.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = r
	p.direction = Vector3.UP
	p.spread = 30.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.6
	p.gravity = Vector3.ZERO
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color("#FFF3B0")
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	q.material = m
	p.mesh = q
	add_child(p)
	p.global_position = at
	return p

# ------------------------------------------------------------------ game hooks
## How many ticket windows the player owns: the rest stand empty (counter and
## clerk hidden), so buying a station visibly opens a new desk.
func set_open_windows(n: int) -> void:
	_open_windows = clampi(n, 1, maxi(_windows.size(), 1))
	for i in _windows.size():
		for node in _windows[i]["nodes"]:
			(node as Node3D).visible = i < _open_windows

func window_count() -> int:
	return _windows.size()

func open_windows() -> int:
	return mini(_open_windows, _windows.size())

## World anchor above ticket counter `index` (for the 2D station chips).
func station_anchor(index: int) -> Vector3:
	if index < 0 or index >= _windows.size():
		return Vector3.ZERO
	return _windows[index]["top"]

## Screen point -> the ground point under it (floor height), or null.
func ground_at(screen: Vector2) -> Variant:
	if camera == null:
		return null
	var plane := Plane(Vector3.UP, FLOOR_TOP)
	return plane.intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))

## The department whose room contains world point `p` ("" for lobby/outside).
## Rooms that `merge_into` another count as that room's department.
func dept_at(p: Vector3, level := 0) -> String:
	for r in rooms:
		if int(r.get("level", 0)) != level:
			continue
		var rect: Array = r["rect"]
		if Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3])).has_point(Vector2(p.x, p.z)):
			if r.has("merge_into"):
				return str(_room_by_id(str(r["merge_into"])).get("dept", ""))
			return str(r.get("dept", ""))
	return ""

## Centre of a department's main room on the floor (for camera focus / tests).
func dept_center(dept: String) -> Vector3:
	for r in rooms:
		if str(r.get("dept", "")) == dept:
			var rect: Array = r["rect"]
			return Vector3(float(rect[0]) + float(rect[2]) * 0.5, FLOOR_TOP, float(rect[1]) + float(rect[3]) * 0.5)
	return Vector3.ZERO

## A floating "+$12" that rises and fades above a point.
func pop_text(at: Vector3, text: String, color := Color("#FFD34D"), big := false) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = POP_FONT
	l.font_size = 64 if big else 44
	l.outline_size = 14
	l.modulate = color
	l.outline_modulate = Color("#3A2A10")
	l.pixel_size = 0.006
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 10
	l.outline_render_priority = 9
	add_child(l)
	l.global_position = at
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", at.y + 1.4, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector3.ONE * 1.15, 0.18).from(Vector3.ONE * 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.75)
	tw.chain().tween_callback(l.queue_free)

# ------------------------------------------------------------------ traffic
func _traffic() -> void:
	var paints := ["#D9413A", "#3A78D8", "#F2D14A", "#4FB86A", "#FFFFFF", "#8E6BD8"]
	for i in 5:
		var bus := i == 0
		var car: Node3D = _scene("res://art3d/vehicles/%s.glb" % ("bus" if bus else "car")).instantiate()
		add_child(car)
		var dir := 1.0 if i % 2 == 0 else -1.0
		car.position = Vector3(_rng.randf_range(-10.0, W + 10.0), 0.03, road_z + (0.75 if dir > 0 else -0.75))
		car.rotation.y = 0.0 if dir > 0 else PI
		if not bus:
			for node in car.find_children("*", "MeshInstance3D", true, false):
				var mi := node as MeshInstance3D
				for s in mi.mesh.get_surface_count():
					var src := mi.mesh.surface_get_material(s)
					if src and src.resource_name == "paint":
						var m := src.duplicate() as StandardMaterial3D
						m.albedo_color = Color(paints[i % paints.size()])
						mi.set_surface_override_material(s, m)
		_vehicles.append({"node": car, "dir": dir, "speed": 1.6 if bus else _rng.randf_range(2.2, 3.4),
			"wheels": car.find_children("wheel_*", "Node3D", true, false), "wait": 0.0, "bus": bus})

func _drive(delta: float) -> void:
	for v in _vehicles:
		var car: Node3D = v["node"]
		if float(v["wait"]) > 0.0:
			v["wait"] = float(v["wait"]) - delta
			continue
		var dx := float(v["dir"]) * float(v["speed"]) * delta
		var before := car.position.x
		car.position.x += dx
		for w in v["wheels"]:
			(w as Node3D).rotation.z -= dx / 0.17
		# The bus stops at the shelter in front of the museum.
		if bool(v["bus"]) and signf(before - 1.5) != signf(car.position.x - 1.5):
			v["wait"] = 3.0
		if car.position.x > W + 12.0:
			car.position.x = -12.0
		elif car.position.x < -12.0:
			car.position.x = W + 12.0

# ------------------------------------------------------------------ look
func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#bfe3ff")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#cfe0ff")
	env.ambient_light_energy = 0.24
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR  # Filmic bleaches toy colours to white in Compatibility
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.2
	env.glow_hdr_threshold = 1.4
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.2
	env.adjustment_contrast = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -32.0, 0.0)
	sun.light_energy = 0.62
	sun.light_color = Color("#fff3df")
	sun.shadow_enabled = true
	sun.shadow_blur = 1.6
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)

func _camera() -> void:
	camera = ToyCamera.new()
	add_child(camera)
	var back := 0.0
	for f in floors:
		back = minf(back, (f["rect"] as Rect2).position.y)
	camera.bounds = Rect2(-3.0, back - 3.0, W + 6.0, H + 12.0 - back)
	camera.height_at = height_at
	camera.frame(Rect2(-0.5, -3.0, W + 1.0, H + 4.0), 0.6)
	camera.current = true

func _tilt_shift() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = TILT_SHIFT
	rect.material = mat
	layer.add_child(rect)

# ------------------------------------------------------------------ navigation
func _bake_nav() -> void:
	var map := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, 0.08)
	NavigationServer3D.map_set_cell_height(map, 0.04)
	# Bevelled floor tiles leave hairline steps that Recast splits into
	# near-duplicate edges; a finer merge grid keeps them from colliding.
	NavigationServer3D.map_set_merge_rasterizer_cell_scale(map, 0.001)
	var nm := NavigationMesh.new()
	nm.cell_size = 0.08
	nm.cell_height = 0.04
	nm.agent_radius = 0.2
	nm.agent_height = 0.9
	nm.agent_max_climb = 0.14
	nm.agent_max_slope = 30.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	var back := 0.0
	var top := 0.0
	for f in floors:
		back = minf(back, (f["rect"] as Rect2).position.y)
		top = maxf(top, float(f["y"]))
	nm.filter_baking_aabb = AABB(Vector3(-9.0, -1.0, back - 8.0), Vector3(W + 18.0, top + 4.0, H + 22.0 - back))
	_region.navigation_mesh = nm
	_region.bake_finished.connect(_on_baked, CONNECT_ONE_SHOT)
	_region.bake_navigation_mesh(true)

func _on_baked() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	_nav_ready = true
	# Open with a crowd already inside rather than an empty hall.
	for i in mini(_views.size() * 2, visitor_target / 2):
		var v: Dictionary = _views[_rng.randi() % _views.size()]
		var at: Vector3 = v["spot"] + Vector3(_rng.randf_range(-0.3, 0.3), 0.0, _rng.randf_range(-0.3, 0.3))
		_visit(_spawn(_look(), at), true)
