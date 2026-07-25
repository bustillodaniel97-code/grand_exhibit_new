extends RefCounted
## Exhibits — the registry of procedural KINDS a venue theme is assembled from.
##
## A theme never describes pixels. It names a KIND and hands it a spec: where the
## piece stands in grid space, how big it is, what colour its parts are. Every
## solid thing a floor can contain — the mounted skeleton, a water tank, the
## benches, the ticket counters, the rugs painted on the floor — is one of these,
## so authoring a venue is writing data, not writing another _draw function.
##
## Three rules hold the registry together:
##   · A painter is PURE. It reads its spec and draws. It never touches
##     GameState, the theme, another node, or a class member.
##   · A painter draws into whatever CanvasItem it is given. Floor kinds get
##     their own Y-sorted node from VenueFloor; wall pieces and floor dressing
##     are handed the shared ground item, where consecutive polygons batch and
##     therefore cost no extra draw calls.
##   · A spec is optional all the way down. Every key has a default that draws
##     something sensible, so a new theme can say {"kind": "bench", "at": [3, 4]}
##     and get a bench.
##
## Colours arriving here are already Colors: VenueFloor's Theme resolves the
## "@palette-key" tokens before a painter ever sees a spec.

const UI := preload("res://scripts/ui/ui_kit.gd")
const Iso := preload("res://scenes/venue/floor/iso.gd")

## Every kind this registry can draw, grouped by what a theme uses it for. The
## test suite renders one of each, so an entry here that has no painter fails
## loudly instead of silently drawing nothing on somebody's new venue.
const EXHIBIT_KINDS: Array[String] = [
	"skeleton", "casket", "statue", "vitrine", "case", "tank", "hanging",
	"hung_skeleton", "touch_pool", "mural", "plinth"]
const FIXTURE_KINDS: Array[String] = [
	"counter", "info_desk", "desk", "vault_door", "facade", "kiosk", "shelf",
	"rope_line"]
const FURNITURE_KINDS: Array[String] = [
	"bench", "planter", "kelp", "bin", "rack", "cabinet", "crate", "trolley",
	"machine", "banner", "balloons"]
const DRESSING_KINDS: Array[String] = [
	"rug", "patch", "picture", "porthole", "notice", "poster", "bunting"]

static func kinds() -> Array[String]:
	var out: Array[String] = []
	out.append_array(EXHIBIT_KINDS)
	out.append_array(FIXTURE_KINDS)
	out.append_array(FURNITURE_KINDS)
	out.append_array(DRESSING_KINDS)
	return out

static func has_kind(kind: String) -> bool:
	return kind in kinds()

# --- Spec readers -------------------------------------------------------------
##
## JSON gives arrays where the floor wants Vector2s and numbers where it wants
## floats, so every read goes through one of these. They also accept the native
## type, which is what lets VenueFloor build a spec in code (the ticket counters
## are generated from the queue geometry, not authored).

static func v2(value: Variant, def: Vector2 = Vector2.ZERO) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return def

static func f(value: Variant, def: float) -> float:
	if value is float or value is int:
		return float(value)
	return def

static func i(value: Variant, def: int) -> int:
	if value is float or value is int:
		return int(value)
	return def

static func c(value: Variant, def: Color) -> Color:
	if value is Color:
		return value
	if value is String:
		return Color(str(value))
	return def

static func cols(value: Variant, def: Array) -> Array:
	if value is Array and not (value as Array).is_empty():
		var out: Array = []
		for entry in value:
			out.append(c(entry, UI.PANEL))
		return out
	return def

## Grid points, for the kinds that take a path rather than a footprint.
static func points(value: Variant) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if value is Array:
		for entry in value:
			out.append(v2(entry))
	return out

# --- Placement ----------------------------------------------------------------

## Grid anchor a floor kind should be Y-sorted at.
##
## Defaults to the centre of the footprint, which is right for anything whose
## silhouette is roughly its base. The shipped natural-history theme states most
## anchors explicitly because they were tuned by eye against the cast walking
## past them, and a prop that sorts half a tile wrong is a visitor walking
## through a bench.
static func anchor(spec: Dictionary) -> Vector2:
	if spec.has("anchor"):
		return v2(spec["anchor"])
	var at: Vector2 = v2(spec.get("at"))
	var size: Vector2 = footprint(spec)
	return at + size * 0.5

## Footprint in tiles. `size` wins; length-based kinds carry `len` instead. A
## kind with neither (a planter, a bin, a trolley) is placed BY its anchor rather
## than by a corner, so its footprint is zero and `at` is the anchor.
static func footprint(spec: Dictionary) -> Vector2:
	if spec.has("size"):
		return v2(spec["size"])
	if spec.has("len"):
		return Vector2(f(spec["len"], 1.0), 0.4)
	return Vector2.ZERO

# --- Registry -----------------------------------------------------------------

## The painter for one spec. Returns a Callable taking the CanvasItem to draw
## into, so VenueFloor can hand a floor kind its own node and a dressing kind the
## shared ground item without either knowing the difference.
static func painter(kind: String, spec: Dictionary) -> Callable:
	match kind:
		"skeleton": return _skeleton(spec)
		"casket": return _casket(spec)
		"statue": return _statue(spec)
		"vitrine": return _vitrine(spec)
		"case": return _case(spec)
		"tank": return _tank(spec)
		"hanging": return _hanging(spec)
		"hung_skeleton": return _hung_skeleton(spec)
		"touch_pool": return _touch_pool(spec)
		"mural": return _mural(spec)
		"plinth": return _plinth(spec)
		"counter": return _counter(spec)
		"info_desk": return _info_desk(spec)
		"desk": return _desk(spec)
		"vault_door": return _vault_door(spec)
		"facade": return _facade(spec)
		"kiosk": return _kiosk(spec)
		"shelf": return _shelf(spec)
		"rope_line": return _rope_line(spec)
		"bench": return _bench(spec)
		"planter": return _planter(spec)
		"kelp": return _kelp(spec)
		"bin": return _bin(spec)
		"rack": return _rack(spec)
		"cabinet": return _cabinet(spec)
		"crate": return _crate(spec)
		"trolley": return _trolley(spec)
		"machine": return _machine(spec)
		"banner": return _banner(spec)
		"balloons": return _balloons(spec)
		"rug": return _rug(spec)
		"patch": return _patch(spec)
		"picture": return _picture(spec)
		"porthole": return _porthole(spec)
		"notice": return _notice(spec)
		"poster": return _poster(spec)
		"bunting": return _bunting(spec)
	push_warning("Exhibits: unknown kind '%s'" % kind)
	return func(_ci: CanvasItem) -> void: pass

## A painter plus, if the spec asks for one, the velvet barrier in front of it.
## Barriers belong to the piece they protect rather than to the room, so they
## sort with it: a rope drawn on its own node would sit in front of a visitor
## standing behind the exhibit.
static func guarded(kind: String, spec: Dictionary) -> Callable:
	var body: Callable = painter(kind, spec)
	if not spec.has("barrier"):
		return body
	var rope: Callable = _rope_line(spec["barrier"] as Dictionary)
	return func(ci: CanvasItem) -> void:
		body.call(ci)
		rope.call(ci)

# --- Exhibit kinds ------------------------------------------------------------

## Mounted skeleton on a plinth. The sauropod today; the same kind with a longer
## neck and no legs is a whale, and with `legs` at 2 it is a bird.
static func _skeleton(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var base: Vector2 = v2(spec.get("size"), Vector2(3.2, 1.2))
	var base_h: float = f(spec.get("plinth_h"), 14.0)
	var stone: Color = c(spec.get("plinth"), Color("#C9B896"))
	var lip: Color = c(spec.get("lip"), Color("#B3A281"))
	var bone: Color = c(spec.get("bone"), Color("#F3EAD6"))
	var edge: Color = c(spec.get("edge"), Color("#6E5C3C"))
	var span: float = f(spec.get("span"), 52.0)
	var hump: float = f(spec.get("hump"), 20.0)
	# Neck and tail are POLYLINES off the ends of the spine, not directions: the
	# bend is what makes a sauropod read as a sauropod and a plesiosaur as a
	# plesiosaur, and a straight interpolation loses it.
	var neck: Array[Vector2] = points(spec.get("neck", [[12.0, -12.0], [20.0, -26.0]]))
	var skull_at: Vector2 = v2(spec.get("skull"), Vector2(24.0, -30.0))
	var tail: Array[Vector2] = points(spec.get("tail", [[-16.0, 4.0], [-28.0, -4.0]]))
	var legs: Array = spec.get("legs", [-34.0, -12.0, 16.0, 34.0])
	var lift: float = f(spec.get("lift"), 26.0)
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, at + Vector2(0.08, 0.12), base + Vector2(0.0, 0.1), 0.22)
		Iso.box(ci, at, base, base_h, stone)
		Iso.box(ci, at + Vector2(0.0, base.y - 0.16), Vector2(base.x, 0.16),
			base_h + 2.0, lip)
		var mid: Vector2 = Iso.to_screen(at + base * 0.5) + Vector2(0.0, -base_h)
		# Spine first, then everything hung off it. Grouped by primitive so the
		# strokes batch: a bone-by-bone draw order costs three times the calls.
		var spine := PackedVector2Array()
		for k in 13:
			var t: float = float(k) / 12.0
			spine.append(mid + Vector2(lerpf(-span, span, t), -lift - sin(t * PI) * hump))
		Iso.stroke(ci, spine, edge, 8.0)
		Iso.stroke(ci, spine, bone, 4.6)
		for p in spine:
			Iso.pip(ci, p, 3.0, edge)
		for p in spine:
			Iso.pip(ci, p, 1.8, bone)
		for k in range(3, 10, 2):
			ci.draw_arc(spine[k] + Vector2(0, 2), 13.0, 0.10 * PI, 0.90 * PI, 10, edge, 4.6)
		for k in range(3, 10, 2):
			ci.draw_arc(spine[k] + Vector2(0, 2), 13.0, 0.10 * PI, 0.90 * PI, 10, bone, 2.4)
		var tail_pts := PackedVector2Array([spine[0]])
		for d in tail:
			tail_pts.append(spine[0] + d)
		Iso.stroke(ci, tail_pts, edge, 6.0)
		Iso.stroke(ci, tail_pts, bone, 3.0)
		var neck_pts := PackedVector2Array([spine[12]])
		for d in neck:
			neck_pts.append(spine[12] + d)
		Iso.stroke(ci, neck_pts, edge, 7.0)
		Iso.stroke(ci, neck_pts, bone, 3.8)
		var skull: Vector2 = spine[12] + skull_at
		var head := PackedVector2Array([
			skull + Vector2(-8, -6), skull + Vector2(6, -7), skull + Vector2(16, -1),
			skull + Vector2(17, 3), skull + Vector2(4, 5), skull + Vector2(-7, 3)])
		ci.draw_colored_polygon(head, bone)
		var ring := head.duplicate()
		ring.append(head[0])
		Iso.stroke(ci, ring, edge, 2.4)
		Iso.pip(ci, skull + Vector2(2, -2), 2.2, edge)
		var limbs: Array = []
		for lx in legs:
			var x: float = float(lx)
			limbs.append([
				mid + Vector2(x, -lift - sin((x + span) / (span * 2.0) * PI) * hump + 4.0),
				mid + Vector2(x - 3.0, 0.0)])
		for leg in limbs:
			ci.draw_line(leg[0], leg[1], edge, 6.4)
		for leg in limbs:
			ci.draw_line(leg[0], leg[1], bone, 3.4)

## Upright cased artefact with a rounded lid — a sarcophagus here, a specimen
## jar or a diving bell elsewhere. `body` is the shell, `trim` the inlay.
static func _casket(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var base: Vector2 = v2(spec.get("size"), Vector2(1.0, 1.0))
	var base_h: float = f(spec.get("plinth_h"), 12.0)
	var stone: Color = c(spec.get("plinth"), Color("#C9B896"))
	var body: Color = c(spec.get("body"), Color("#D2A047"))
	var trim: Color = c(spec.get("trim"), Color("#3E7E8C"))
	var edge: Color = c(spec.get("edge"), Color("#8A6524"))
	var tall: float = f(spec.get("height"), 44.0)
	var lid_r: Vector2 = v2(spec.get("lid_r"), Vector2(17.0, 20.0))
	var shoulder: float = f(spec.get("shoulder"), 30.0)
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, at + Vector2(0.06, 0.10), base + Vector2(0.1, 0.1), 0.22)
		Iso.box(ci, at, base, base_h, stone)
		var mid: Vector2 = Iso.to_screen(at + base * 0.5) + Vector2(0.0, -base_h)
		var lid := PackedVector2Array()
		for k in 13:
			var a: float = PI + PI * float(k) / 12.0
			lid.append(mid + Vector2(0, -shoulder)
				+ Vector2(cos(a) * lid_r.x, sin(a) * lid_r.y))
		lid.append(mid + Vector2(lid_r.x, 0))
		lid.append(mid + Vector2(-lid_r.x, 0))
		ci.draw_colored_polygon(lid, body)
		ci.draw_line(mid + Vector2(-8, -tall), mid + Vector2(-8, -4),
			Color(1, 1, 1, 0.22), 5.0)
		ci.draw_colored_polygon(PackedVector2Array([
			mid + Vector2(-11, -tall + 4), mid + Vector2(11, -tall + 4),
			mid + Vector2(11, -tall + 16), mid + Vector2(-11, -tall + 16)]), trim)
		Iso.pip(ci, mid + Vector2(-5, -tall + 10), 2.6, UI.PANEL)
		Iso.pip(ci, mid + Vector2(5, -tall + 10), 2.6, UI.PANEL)
		ci.draw_line(mid + Vector2(-10, -20), mid + Vector2(10, -20), trim, 3.4)
		ci.draw_line(mid + Vector2(-8, -12), mid + Vector2(8, -12), trim.darkened(0.12), 2.6)
		var ring := lid.duplicate()
		ring.append(lid[0])
		Iso.stroke(ci, ring, edge, 2.2)

## Stone figure on a plinth.
static func _statue(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var size: Vector2 = v2(spec.get("size"), Vector2(1.0, 1.0))
	var base_h: float = f(spec.get("plinth_h"), 26.0)
	var plinth: Color = c(spec.get("plinth"), Color("#C9B896"))
	var stone: Color = c(spec.get("stone"), Color("#E6DCC4"))
	var edge: Color = c(spec.get("edge"), Color("#9C8C6E"))
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, at + Vector2(0.06, 0.10), size + Vector2(0.06, 0.06), 0.22)
		Iso.box(ci, at, size, base_h, plinth)
		var t: Vector2 = Iso.to_screen(at + size * 0.5) + Vector2(0.0, -base_h)
		ci.draw_colored_polygon(PackedVector2Array([
			t + Vector2(-7, 0), t + Vector2(7, 0),
			t + Vector2(5, -25), t + Vector2(-5, -25)]), stone)
		ci.draw_line(t + Vector2(-6, -21), t + Vector2(-13, -33), stone, 4.6)
		ci.draw_line(t + Vector2(6, -21), t + Vector2(12, -29), stone, 4.6)
		ci.draw_circle(t + Vector2(0, -32), 6.2, stone)
		ci.draw_arc(t + Vector2(0, -32), 6.2, 0.0, TAU, 16, edge, 1.6)
		ci.draw_line(t + Vector2(-7, -1), t + Vector2(7, -1), edge, 1.8)

## Glass display case with a single faceted artefact standing inside it.
static func _vitrine(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var size: Vector2 = v2(spec.get("size"), Vector2(1.5, 0.7))
	var base_h: float = f(spec.get("plinth_h"), 15.0)
	var base: Color = c(spec.get("base"), Color("#7E6C52"))
	var art: Color = c(spec.get("art"), Color("#7FD4E8"))
	var glass_h: float = f(spec.get("glass_h"), 30.0)
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, at + Vector2(0.06, 0.10), size + Vector2(0.06, 0.06), 0.20)
		Iso.box(ci, at, size, base_h, base)
		var t: Vector2 = Iso.to_screen(at + size * 0.5) + Vector2(0.0, -base_h)
		ci.draw_colored_polygon(PackedVector2Array([
			t + Vector2(-9, -10), t + Vector2(0, -21),
			t + Vector2(9, -10), t + Vector2(0, 1)]), art)
		ci.draw_colored_polygon(PackedVector2Array([
			t + Vector2(-4, -12), t + Vector2(0, -18),
			t + Vector2(3, -11), t + Vector2(0, -5)]), art.lightened(0.42))
		ci.draw_line(t + Vector2(-8, -6), t + Vector2(8, -6), art.darkened(0.30), 2.0)
		Iso.box(ci, at + Vector2(0.05, 0.05), size - Vector2(0.10, 0.10), glass_h,
			Color(0.78, 0.92, 1.0, 0.20), Color(1, 1, 1, 0.34))

## Low cabinet with a lit glass top and a row of small specimens.
static func _case(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var size: Vector2 = v2(spec.get("size"), Vector2(1.5, 0.7))
	var base_h: float = f(spec.get("plinth_h"), 17.0)
	var base: Color = c(spec.get("base"), Color("#7E6C52"))
	var specimens: Array = cols(spec.get("specimens"),
		[Color("#7ED8F0"), Color("#F08CC4"), Color("#9CE8A8")])
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, at + Vector2(0.06, 0.10), size + Vector2(0.06, 0.06), 0.20)
		Iso.box(ci, at, size, base_h, base)
		var t: Vector2 = Iso.to_screen(at + size * 0.5) + Vector2(0.0, -base_h)
		var n: int = specimens.size()
		for k in n:
			var p: Vector2 = t + Vector2(lerpf(-10.0, 10.0, float(k) / float(maxi(n - 1, 1))), 0.0)
			ci.draw_colored_polygon(PackedVector2Array([
				p + Vector2(-4, -1), p + Vector2(0, -8),
				p + Vector2(4, -1), p + Vector2(0, 3)]), specimens[k])
		Iso.box(ci, at + Vector2(0.04, 0.04), size - Vector2(0.08, 0.08), base_h + 4.0,
			Color(0.80, 0.93, 1.0, 0.28), Color(1, 1, 1, 0.36))

## Water tank: a glazed volume with fauna suspended in it. The aquarium's
## workhorse, and the reason the registry exists — a tank is a display case with
## a tinted interior and swimmers, not a new drawing system.
static func _tank(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var size: Vector2 = v2(spec.get("size"), Vector2(1.6, 1.0))
	var base_h: float = f(spec.get("plinth_h"), 16.0)
	var glass_h: float = f(spec.get("height"), 46.0)
	var frame: Color = c(spec.get("frame"), Color("#4E6B84"))
	var water: Color = c(spec.get("water"), Color("#2FA9C8"))
	var fauna: Array = cols(spec.get("fauna"), [UI.BRASS, Color("#FF8F5A")])
	var swimmers: int = i(spec.get("fauna_count"), 4)
	var weed: Color = c(spec.get("weed"), Color("#2F8F52"))
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, at + Vector2(0.06, 0.10), size + Vector2(0.06, 0.06), 0.22)
		Iso.box(ci, at, size, base_h, frame)
		# The frame's back board goes in BEFORE the water. Drawn last it was a
		# billboard: 0.10 tiles deep but full width and full height, so from this
		# camera it stood in front of the volume it frames and every tank on the
		# aquarium floor rendered as a flat grey slab with no fish in it.
		Iso.box(ci, at, Vector2(size.x, 0.10), base_h + glass_h + 4.0, frame.lightened(0.10))
		var inner: Vector2 = at + Vector2(0.06, 0.06)
		var isize: Vector2 = size - Vector2(0.12, 0.12)
		# Water volume first, then everything living in it, then the glass. That
		# order is what makes the fauna read as being INSIDE rather than painted
		# on the front pane.
		Iso.box(ci, inner, isize, base_h + glass_h * 0.92,
			Color(water.r, water.g, water.b, 0.62), Color(0, 0, 0, 0))
		var t: Vector2 = Iso.to_screen(at + size * 0.5) + Vector2(0.0, -base_h)
		for k in 3:
			var wx: float = lerpf(-16.0, 16.0, float(k) / 2.0)
			var blade := PackedVector2Array([
				t + Vector2(wx - 3.0, -2.0), t + Vector2(wx + 1.0, -glass_h * 0.55),
				t + Vector2(wx + 4.0, -2.0)])
			ci.draw_colored_polygon(blade, weed.darkened(0.10 * float(k % 2)))
		for k in swimmers:
			var u: float = (float(k) + 0.5) / float(maxi(swimmers, 1))
			var p: Vector2 = t + Vector2(lerpf(-17.0, 17.0, u),
				-glass_h * lerpf(0.30, 0.80, fmod(u * 2.7, 1.0)))
			var col: Color = fauna[k % fauna.size()]
			ci.draw_colored_polygon(PackedVector2Array([
				p + Vector2(-6, 0), p + Vector2(1, -4),
				p + Vector2(6, 0), p + Vector2(1, 4)]), col)
			ci.draw_colored_polygon(PackedVector2Array([
				p + Vector2(-6, 0), p + Vector2(-11, -4), p + Vector2(-11, 4)]),
				col.darkened(0.18))
		Iso.box(ci, inner, isize, base_h + glass_h,
			Color(0.80, 0.94, 1.0, 0.16), Color(1, 1, 1, 0.30))

## A piece suspended from the ceiling on wires — a whale, a pterosaur, a flock.
## Anchored on the floor tile it hangs over, so it Y-sorts with the room rather
## than floating in front of everything.
static func _hanging(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var ceiling: float = f(spec.get("ceiling"), Iso.WALL_H)
	var drop: float = f(spec.get("drop"), 18.0)
	var span: float = f(spec.get("span"), 34.0)
	var body: Color = c(spec.get("body"), Color("#5FA8C8"))
	var edge: Color = c(spec.get("edge"), Color("#2E5F78"))
	var wire: Color = c(spec.get("wire"), Color(1, 1, 1, 0.35))
	var wings: bool = bool(spec.get("wings", false))
	return func(ci: CanvasItem) -> void:
		var top: Vector2 = Iso.to_screen(at) + Vector2(0.0, -ceiling)
		var mid: Vector2 = top + Vector2(0.0, drop)
		for dx in [-span * 0.45, span * 0.35]:
			ci.draw_line(top + Vector2(dx, 0.0), mid + Vector2(dx, 0.0), wire, 1.2)
		if wings:
			ci.draw_colored_polygon(PackedVector2Array([
				mid + Vector2(0, -3), mid + Vector2(-span, -span * 0.34),
				mid + Vector2(-span * 0.4, 5)]), body.darkened(0.18))
			ci.draw_colored_polygon(PackedVector2Array([
				mid + Vector2(0, -3), mid + Vector2(span, -span * 0.30),
				mid + Vector2(span * 0.4, 5)]), body)
		var hull := PackedVector2Array([
			mid + Vector2(-span * 0.62, 0), mid + Vector2(-span * 0.2, -span * 0.20),
			mid + Vector2(span * 0.5, -span * 0.14), mid + Vector2(span * 0.62, 0),
			mid + Vector2(span * 0.4, span * 0.16), mid + Vector2(-span * 0.3, span * 0.18)])
		ci.draw_colored_polygon(hull, body)
		ci.draw_colored_polygon(PackedVector2Array([
			mid + Vector2(-span * 0.62, 0), mid + Vector2(-span * 0.95, -span * 0.24),
			mid + Vector2(-span * 0.92, span * 0.20)]), body.darkened(0.22))
		var ring := hull.duplicate()
		ring.append(hull[0])
		Iso.stroke(ci, ring, edge, 1.8)
		Iso.pip(ci, mid + Vector2(span * 0.40, -span * 0.05), 2.0, edge)

## Articulated skeleton slung from the ceiling on wires — the whale hall's
## headline piece. `skeleton` cannot do this job: it mounts on a plinth and its
## silhouette is a spine over four legs. This one has no footprint at all, so it
## anchors on the tile it hangs OVER and Y-sorts with that tile rather than
## floating in front of everyone in the room.
static func _hung_skeleton(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var ceiling: float = f(spec.get("ceiling"), Iso.WALL_H)
	var drop: float = f(spec.get("drop"), 16.0)
	var span: float = f(spec.get("span"), 56.0)
	var arch: float = f(spec.get("arch"), 9.0)
	var bone: Color = c(spec.get("bone"), Color("#F3EAD6"))
	var edge: Color = c(spec.get("edge"), Color("#6E5C3C"))
	var wire: Color = c(spec.get("wire"), Color(1, 1, 1, 0.35))
	var ribs: int = clampi(i(spec.get("ribs"), 7), 0, 9)
	var rib_len: float = f(spec.get("rib_len"), 15.0)
	var fluke: float = f(spec.get("fluke"), 12.0)
	var skull: float = f(spec.get("skull"), 22.0)
	return func(ci: CanvasItem) -> void:
		var top: Vector2 = Iso.to_screen(at) + Vector2(0.0, -ceiling)
		var mid: Vector2 = top + Vector2(0.0, drop)
		var spine := PackedVector2Array()
		for k in 13:
			var t: float = float(k) / 12.0
			spine.append(mid + Vector2(lerpf(-span, span, t), -sin(t * PI) * arch))
		for w in [2, 6, 10]:
			ci.draw_line(Vector2(spine[w].x, top.y), spine[w], wire, 1.2)
		Iso.stroke(ci, spine, edge, 7.0)
		Iso.stroke(ci, spine, bone, 4.0)
		# Every rib is two straight segments rather than an arc: draw_arc costs a
		# draw call apiece and lines batch (see Iso.stroke), so a seven-rib cage
		# that would have been seven calls is two.
		var cage: Array[PackedVector2Array] = []
		for k in ribs:
			var s: Vector2 = spine[k + 2]
			cage.append(PackedVector2Array([
				s, s + Vector2(-1.5, rib_len * 0.58), s + Vector2(-6.5, rib_len)]))
		for rib in cage:
			Iso.stroke(ci, rib, edge, 3.4)
		for rib in cage:
			Iso.stroke(ci, rib, bone, 1.8)
		var head: Vector2 = spine[12]
		ci.draw_colored_polygon(PackedVector2Array([
			head + Vector2(-5, -7), head + Vector2(skull - 4, -3),
			head + Vector2(skull, 2), head + Vector2(-5, 6)]), bone)
		var tail: Vector2 = spine[0]
		ci.draw_colored_polygon(PackedVector2Array([
			tail + Vector2(3, 0), tail + Vector2(-9, -fluke),
			tail + Vector2(-15, 0), tail + Vector2(-9, fluke)]), bone)
		ci.draw_line(head + Vector2(-3, 1), head + Vector2(skull - 3, 0), edge, 1.6)
		Iso.pip(ci, head + Vector2(2, -2), 2.0, edge)

## Open touch pool: a walled basin of shallow water over sand, with tide-pool
## animals in it. The one exhibit visitors look DOWN into rather than through, so
## it is a low box with a sunken water plane instead of a glazed volume — and
## that is why it is its own kind and not a short `tank`.
static func _touch_pool(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var size: Vector2 = v2(spec.get("size"), Vector2(2.0, 1.4))
	var rim_h: float = f(spec.get("rim_h"), 14.0)
	var rim: Color = c(spec.get("rim"), Color("#8FA9B4"))
	var water: Color = c(spec.get("water"), Color("#2FA9C8"))
	var sand: Color = c(spec.get("sand"), Color("#E8D9A8"))
	var life: Array = cols(spec.get("life"), [Color("#FF7A6B"), Color("#FFC53D")])
	var life_count: int = i(spec.get("life_count"), 5)
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, at + Vector2(0.06, 0.10), size + Vector2(0.06, 0.06), 0.22)
		Iso.box(ci, at, size, rim_h, rim)
		# The water sits a few pixels below the coping, so the near wall reads as
		# something the player is looking over rather than as a painted lid.
		var lift := Vector2(0.0, -rim_h + 4.0)
		var bed: PackedVector2Array = Iso.quad(at + Vector2(0.14, 0.14),
			size - Vector2(0.28, 0.28))
		for k in bed.size():
			bed[k] = bed[k] + lift
		ci.draw_colored_polygon(bed, sand)
		ci.draw_colored_polygon(bed, Color(water.r, water.g, water.b, 0.52))
		for k in 3:
			var t: float = (float(k) + 1.0) / 4.0
			ci.draw_line(bed[0].lerp(bed[3], t), bed[1].lerp(bed[2], t),
				Color(1, 1, 1, 0.14), 2.0)
		var centre: Vector2 = Iso.to_screen(at + size * 0.5) + lift
		var reach: Vector2 = (bed[1] - bed[3]) * 0.34
		for k in life_count:
			var u: float = (float(k) + 0.5) / float(maxi(life_count, 1))
			var p: Vector2 = centre + reach * lerpf(-1.0, 1.0, u) \
				+ Vector2(0.0, lerpf(-6.0, 7.0, fmod(u * 2.3, 1.0)))
			var col: Color = life[k % life.size()]
			ci.draw_colored_polygon(PackedVector2Array([
				p + Vector2(-5, 0), p + Vector2(0, -3),
				p + Vector2(5, 0), p + Vector2(0, 3)]), col)
		for k in life_count:
			var u: float = (float(k) + 0.5) / float(maxi(life_count, 1))
			var p: Vector2 = centre + reach * lerpf(-1.0, 1.0, u) \
				+ Vector2(0.0, lerpf(-6.0, 7.0, fmod(u * 2.3, 1.0)))
			ci.draw_line(p + Vector2(-4, 2), p + Vector2(4, -2),
				(life[k % life.size()] as Color).lightened(0.28), 1.6)
		var ring := bed.duplicate()
		ring.append(bed[0])
		Iso.stroke(ci, ring, Color(1, 1, 1, 0.22), 1.6)
		Iso.box(ci, at, Vector2(size.x, 0.11), rim_h + 3.0, rim.lightened(0.16))

## Framed feature piece hung on a wall plane. The only exhibit kind with no
## footprint: it draws into the ground item and occupies no floor.
static func _mural(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var length: float = f(spec.get("len"), 2.2)
	var axis: String = str(spec.get("axis", "x"))
	var y0: float = f(spec.get("y0"), 16.0)
	var y1: float = f(spec.get("y1"), 44.0)
	var frame: Color = c(spec.get("frame"), UI.BRASS.darkened(0.28))
	var sky: Color = c(spec.get("sky"), Color("#BFDCF2"))
	var land: Color = c(spec.get("land"), Color("#7E9E78"))
	var horizon: float = f(spec.get("horizon"), 27.0)
	var inset: float = f(spec.get("inset"), 0.16)
	var motif: Color = c(spec.get("motif"), Color("#F7DE93"))
	var motif_at: Vector2 = v2(spec.get("motif_at"), Vector2(1.5, 0.0))
	var motif_dy: float = f(spec.get("motif_dy"), 35.0)
	var motif_r: float = f(spec.get("motif_r"), 5.0)
	return func(ci: CanvasItem) -> void:
		var step: Vector2 = Vector2(inset, 0.0) if axis == "x" else Vector2(0.0, inset)
		Iso.panel(ci, at, length, axis, y0, y1, frame)
		Iso.panel(ci, at + step, length - inset * 2.0, axis, y0 + 3.0, y1 - 3.0, sky)
		Iso.panel(ci, at + step, length - inset * 2.0, axis, y0 + 3.0, horizon, land,
			Color(0, 0, 0, 0))
		if motif_r > 0.0:
			Iso.pip(ci, Iso.to_screen(at + motif_at) + Vector2(0.0, -motif_dy),
				motif_r, motif)

## Bare pedestal. Useful on its own for a small artefact, and it is what every
## other exhibit kind stands on.
static func _plinth(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var size: Vector2 = v2(spec.get("size"), Vector2(1.0, 1.0))
	var height: float = f(spec.get("height"), 22.0)
	var col: Color = c(spec.get("col"), Color("#C9B896"))
	var lip: Color = c(spec.get("lip"), Color("#B3A281"))
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, at + Vector2(0.06, 0.10), size + Vector2(0.06, 0.06), 0.22)
		Iso.box(ci, at, size, height, col)
		Iso.box(ci, at + Vector2(0.0, size.y - 0.12), Vector2(size.x, 0.12),
			height + 2.0, lip)

# --- Fixture kinds ------------------------------------------------------------

## Service counter with a till, a monitor, a paper tray, a glass screen and a
## window number. Everything inside ONE node: consecutive polygons in a canvas
## item batch, where a second node would have cost its own draw calls.
static func _counter(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var size: Vector2 = v2(spec.get("size"), Vector2(1.7, 0.6))
	var height: float = f(spec.get("height"), 21.0)
	var body: Color = c(spec.get("col"), UI.ROOM_TICKET.darkened(0.06))
	var trim: Color = c(spec.get("trim"), UI.BRASS)
	var label: String = str(spec.get("label", ""))
	var font: Font = ThemeDB.fallback_font
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, at + Vector2(0.05, 0.10), size + Vector2(0.0, 0.02), 0.20)
		Iso.box(ci, at, size, height, body)
		Iso.box(ci, at + Vector2(-0.05, -0.05), size + Vector2(0.1, 0.1), height + 3.0,
			trim, Color(0, 0, 0, 0.22))
		# 0.28 tiles back from `at` is the working face of the counter — the strip
		# the clerk's kit stands on, whatever the counter's width.
		var top: float = -height - 3.0
		var mon: Vector2 = Iso.to_screen(at + Vector2(size.x - 0.33, 0.28)) + Vector2(0, top)
		ci.draw_colored_polygon(PackedVector2Array([
			mon + Vector2(-8, -17), mon + Vector2(8, -17),
			mon + Vector2(8, -4), mon + Vector2(-8, -4)]), Color("#2B2245"))
		ci.draw_colored_polygon(PackedVector2Array([
			mon + Vector2(-6, -15), mon + Vector2(6, -15),
			mon + Vector2(6, -6), mon + Vector2(-6, -6)]), UI.SLATE.lightened(0.25))
		var tray: Vector2 = Iso.to_screen(at + Vector2(0.30, 0.28)) + Vector2(0, top)
		for k in 3:
			var ty: float = -float(k) * 2.6
			ci.draw_colored_polygon(PackedVector2Array([
				tray + Vector2(-8, ty), tray + Vector2(0, ty - 4),
				tray + Vector2(8, ty), tray + Vector2(0, ty + 4)]),
				UI.PANEL if k % 2 == 0 else UI.FLOOR_CREAM)
		Iso.panel(ci, at + Vector2(0.06, size.y + 0.02), size.x - 0.12, "x", 24.0, 43.0,
			Color(0.76, 0.92, 1.0, 0.28), Color(1, 1, 1, 0.34))
		if label != "":
			ci.draw_string(font, Iso.to_screen(at + Vector2(size.x * 0.5, 0.28))
				+ Vector2(-4, -6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
				UI.FLOOR_CREAM)

## Reception desk with a lit sign board over it.
static func _info_desk(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var size: Vector2 = v2(spec.get("size"), Vector2(2.2, 0.7))
	var height: float = f(spec.get("height"), 20.0)
	var body: Color = c(spec.get("col"), UI.ROOM_TICKET.darkened(0.18))
	var trim: Color = c(spec.get("trim"), UI.BRASS)
	var board: Color = c(spec.get("board"), UI.PANEL)
	var text: String = str(spec.get("label", "INFO"))
	var font: Font = ThemeDB.fallback_font
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, at + Vector2(0.06, 0.10), size + Vector2(0.1, 0.1), 0.20)
		Iso.box(ci, at, size, height, body)
		Iso.box(ci, at + Vector2(-0.05, -0.05), size + Vector2(0.1, 0.1), height + 3.0,
			trim, Color(0, 0, 0, 0.22))
		var sign: Vector2 = Iso.to_screen(at + Vector2(size.x * 0.5, size.y * 0.5)) \
			+ Vector2(0, -height - 3.0)
		ci.draw_colored_polygon(PackedVector2Array([
			sign + Vector2(-16, -22), sign + Vector2(16, -22),
			sign + Vector2(16, -10), sign + Vector2(-16, -10)]), board)
		ci.draw_string(font, sign + Vector2(-13, -13), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UI.INK)

## Plain working desk with a screen on it — the promotions clerks' station.
static func _desk(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var size: Vector2 = v2(spec.get("size"), Vector2(1.9, 0.6))
	var height: float = f(spec.get("height"), 18.0)
	var body: Color = c(spec.get("col"), Color("#9C7550"))
	var screen: Color = c(spec.get("screen"), UI.SLATE.lightened(0.2))
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, at + Vector2(0.06, 0.10), size + Vector2(0.0, 0.06), 0.20)
		Iso.box(ci, at, size, height, body)
		var mon: Vector2 = Iso.to_screen(at + Vector2(size.x * 0.5, size.y * 0.5)) \
			+ Vector2(0, -height)
		ci.draw_colored_polygon(PackedVector2Array([
			mon + Vector2(-9, -20), mon + Vector2(9, -20),
			mon + Vector2(9, -6), mon + Vector2(-9, -6)]), Color("#2B2245"))
		ci.draw_colored_polygon(PackedVector2Array([
			mon + Vector2(-7, -18), mon + Vector2(7, -18),
			mon + Vector2(7, -8), mon + Vector2(-7, -8)]), screen)

## Heavy door on a wall plane with a spoked dial. The archive's signature piece;
## a bulkhead or a cage gate for another venue.
static func _vault_door(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var length: float = f(spec.get("len"), 1.4)
	var axis: String = str(spec.get("axis", "y"))
	var height: float = f(spec.get("height"), 40.0)
	var leaf: Color = c(spec.get("col"), UI.ROOM_VAULT.darkened(0.42))
	var rim: Color = c(spec.get("rim"), Color("#3C5068"))
	var ring: Color = c(spec.get("ring"), Color("#5B7896"))
	var dial: Color = c(spec.get("dial"), Color("#8FA9C8"))
	var spoke: Color = c(spec.get("spoke"), Color("#4A627E"))
	var hub: Color = c(spec.get("hub"), UI.BRASS)
	var dial_dy: float = f(spec.get("dial_dy"), 21.0)
	return func(ci: CanvasItem) -> void:
		Iso.panel(ci, at, length, axis, 0.0, height, leaf)
		var step: Vector2 = Vector2(length * 0.5, 0.0) if axis == "x" \
			else Vector2(0.0, length * 0.5)
		var vc: Vector2 = Iso.to_screen(at + step) + Vector2(0, -dial_dy)
		ci.draw_circle(vc, 19.0, rim)
		ci.draw_circle(vc, 16.0, ring)
		ci.draw_circle(vc, 13.5, dial)
		for k in 8:
			var a: float = TAU * float(k) / 8.0
			ci.draw_line(vc + Vector2(cos(a), sin(a)) * 4.5,
				vc + Vector2(cos(a), sin(a)) * 12.0, spoke, 2.2)
		ci.draw_circle(vc, 4.6, rim)
		ci.draw_circle(vc, 2.8, hub)

## Entrance facade: a short wall with a double door, a fanlight and daylight
## spilling over the threshold.
static func _facade(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var length: float = f(spec.get("len"), 3.0)
	var height: float = f(spec.get("height"), 46.0)
	var leaf: float = f(spec.get("leaf"), 0.62)
	var door_at: float = f(spec.get("door_at"), 0.88)
	var wall_col: Color = c(spec.get("col"), UI.ROOM_TICKET.darkened(0.34))
	var reveal: Color = c(spec.get("reveal"), UI.WALL_BROWN.darkened(0.30))
	var left: Color = c(spec.get("door_a"), Color("#9A7350"))
	var right: Color = c(spec.get("door_b"), Color("#8A6543"))
	var fan: Color = c(spec.get("fanlight"), UI.BRASS.darkened(0.18))
	return func(ci: CanvasItem) -> void:
		Iso.wall(ci, at, length, "x", wall_col, height)
		var d0: Vector2 = at + Vector2(door_at, 0.0)
		Iso.panel(ci, d0 - Vector2(0.14, 0.0), leaf * 2.0 + 0.28, "x", 0.0, height - 4.0,
			reveal)
		Iso.panel(ci, d0, leaf, "x", 2.0, height - 9.0, left)
		Iso.panel(ci, d0 + Vector2(leaf, 0.0), leaf, "x", 2.0, height - 9.0, right)
		Iso.panel(ci, d0 + Vector2(0.16, 0.0), leaf * 2.0 - 0.32, "x", height - 4.0,
			height + 6.0, fan)
		var mid: Vector2 = Iso.to_screen(d0 + Vector2(leaf, 0.0))
		Iso.pip(ci, mid + Vector2(-4, -18), 2.6, UI.BRASS)
		Iso.pip(ci, mid + Vector2(4, -16), 2.6, UI.BRASS)
		Iso.floor_patch(ci, d0 - Vector2(0.0, 0.85), Vector2(leaf * 2.0, 0.85),
			Color(1.0, 0.95, 0.75, 0.14))

## Audio-guide pedestal: a stalk with a raked screen.
static func _kiosk(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var size: Vector2 = v2(spec.get("size"), Vector2(0.34, 0.34))
	var height: float = f(spec.get("height"), 30.0)
	var body: Color = c(spec.get("col"), Color("#5C6B8A"))
	var screen: Color = c(spec.get("screen"), UI.SAGE.darkened(0.10))
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, at - Vector2(0.02, 0.02), size + Vector2(0.16, 0.16), 0.18)
		Iso.box(ci, at, size, height, body)
		var t: Vector2 = Iso.to_screen(at + size * 0.5) + Vector2(0, -height)
		ci.draw_colored_polygon(PackedVector2Array([
			t + Vector2(-11, -6), t + Vector2(2, -12),
			t + Vector2(11, -5), t + Vector2(-2, 1)]), Color("#2B2245"))
		ci.draw_colored_polygon(PackedVector2Array([
			t + Vector2(-8, -6), t + Vector2(2, -10),
			t + Vector2(8, -5), t + Vector2(-2, -1)]), screen)

## Shelving bank: uprights carrying bundles and boxes.
static func _shelf(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var size: Vector2 = v2(spec.get("size"), Vector2(2.0, 0.5))
	var height: float = f(spec.get("height"), 30.0)
	var body: Color = c(spec.get("col"), Color("#5D7B96"))
	var goods: Color = c(spec.get("goods"), Color("#4ADE80"))
	var boxes: Color = c(spec.get("boxes"), Color("#C9B896"))
	var strap: Color = c(spec.get("strap"), Color("#22A45A"))
	var bays: int = i(spec.get("bays"), 4)
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, at + Vector2(0.06, 0.10), size + Vector2(0.06, 0.06), 0.20)
		Iso.box(ci, at, size, height, body)
		var step: float = (size.x - 0.5) / float(maxi(bays - 1, 1))
		var tops: Array[Vector2] = []
		for k in bays:
			tops.append(Iso.to_screen(Vector2(at.x + 0.25 + float(k) * step,
				at.y + size.y * 0.5)) + Vector2(0, -height))
		for top in tops:
			ci.draw_colored_polygon(PackedVector2Array([
				top + Vector2(-7, -3), top + Vector2(2, -7),
				top + Vector2(9, -3), top + Vector2(0, 1)]), goods)
		for k in bays:
			if k % 2 == 0:
				ci.draw_colored_polygon(PackedVector2Array([
					tops[k] + Vector2(-6, -10), tops[k] + Vector2(1, -14),
					tops[k] + Vector2(7, -10), tops[k] + Vector2(0, -6)]), boxes)
		for top in tops:
			ci.draw_line(top + Vector2(-4, -3), top + Vector2(5, -6), strap, 1.4)

## Posts and a swagged rope through a run of grid points. Queue lanes and the
## barriers in front of an exhibit are the same shape at different scales.
##
## Grouped BY PRIMITIVE, not by post. The GL Compatibility batcher only merges
## consecutive commands of the same kind, so shadow/rope/post/knob per post made
## one lane cost about thirty draw calls; issuing all the ropes, then all the
## posts, costs five, and the painted order is the same because the groups never
## overlap each other.
static func _rope_line(spec: Dictionary) -> Callable:
	var pts_g: Array[Vector2] = points(spec.get("points"))
	if pts_g.is_empty() and spec.has("from") and spec.has("to"):
		var a: Vector2 = v2(spec["from"])
		var b: Vector2 = v2(spec["to"])
		var n: int = i(spec.get("posts"), 3)
		for k in n:
			pts_g.append(a.lerp(b, float(k) / float(maxi(n - 1, 1))))
	var post_h: float = f(spec.get("post_h"), 21.0)
	var rope_h: float = f(spec.get("rope_h"), post_h - 1.0)
	var sag: float = f(spec.get("sag"), 5.0)
	var rope: Color = c(spec.get("rope"), UI.ROPE_RED)
	var post: Color = c(spec.get("post"), UI.WALL_BROWN)
	var knob: Color = c(spec.get("knob"), UI.BRASS)
	var wide: float = f(spec.get("width"), 1.8)
	var segs: int = i(spec.get("segments"), 7)
	var gloss: bool = bool(spec.get("gloss", false))
	return func(ci: CanvasItem) -> void:
		var pts: Array[Vector2] = []
		for g in pts_g:
			pts.append(Iso.to_screen(g))
		var ropes: Array = []
		for k in range(1, pts.size()):
			var curve := PackedVector2Array()
			for j in segs:
				var u: float = float(j) / float(segs - 1)
				var p: Vector2 = (pts[k - 1] + Vector2(0, -rope_h)).lerp(
					pts[k] + Vector2(0, -rope_h), u)
				p.y += sin(u * PI) * sag
				curve.append(p)
			ropes.append(curve)
		for curve in ropes:
			Iso.stroke(ci, curve, rope.darkened(0.3), wide * 1.78)
		for curve in ropes:
			Iso.stroke(ci, curve, rope, wide)
		for p in pts:
			ci.draw_line(p, p + Vector2(0, -post_h), post, wide * 1.33)
		for p in pts:
			Iso.pip(ci, p + Vector2(0, -post_h - 2.0), wide * 1.78, knob)
		if gloss:
			for p in pts:
				Iso.pip(ci, p + Vector2(-1, -post_h - 3.0), wide * 0.79, knob.lightened(0.4))

# --- Furniture kinds ----------------------------------------------------------

static func _bench(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var length: float = f(spec.get("len"), 1.5)
	var col: Color = c(spec.get("col"), Color("#A9793F"))
	var rail: Color = c(spec.get("rail"), Color("#8A6033"))
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, at + Vector2(0.05, 0.08), Vector2(length, 0.5), 0.18)
		Iso.box(ci, at, Vector2(length, 0.42), 9.0, col)
		Iso.box(ci, at + Vector2(0.0, 0.06), Vector2(length, 0.10), 22.0, rail)

## Potted plant. Cheap, and the single most effective thing for making a floor
## look furnished rather than empty.
static func _planter(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var r: float = f(spec.get("r"), 0.24)
	var pot: Color = c(spec.get("pot"), Color("#B4653C"))
	var leaf: Color = c(spec.get("leaf"), Color("#2F8F52"))
	var tip: Color = c(spec.get("tip"), Color("#46B86A"))
	var blades: int = i(spec.get("blades"), 6)
	var reach: float = f(spec.get("reach"), 17.0)
	return func(ci: CanvasItem) -> void:
		var base: Vector2 = Iso.to_screen(at)
		Iso.shadow(ci, at - Vector2(r + 0.04, r + 0.04),
			Vector2(r, r) * 2.0 + Vector2(0.08, 0.08), 0.20)
		Iso.box(ci, at - Vector2(r, r), Vector2(r, r) * 2.0, 13.0, pot)
		var top: Vector2 = base + Vector2(0, -13.0)
		var tips: Array[Vector2] = []
		for k in blades:
			var a: float = -PI * 0.5 + lerpf(-1.0, 1.0, float(k) / float(maxi(blades - 1, 1)))
			tips.append(top + Vector2(cos(a), sin(a)) * reach)
		for t in tips:
			ci.draw_line(top, t, leaf, 3.2)
		for t in tips:
			ci.draw_line(top, t.lerp(top, 0.35), tip, 2.0)

## Kelp column: a holdfast rock on the floor with fronds streaming up out of it.
## The aquarium's answer to the planter, and the cheapest thing that makes a hall
## of tanks read as underwater rather than as a room with tanks in it. Every
## frond is a stroke and every bladelet a pip, so a stand of five costs three
## batched draw calls.
static func _kelp(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var r: float = f(spec.get("r"), 0.22)
	var height: float = f(spec.get("height"), 50.0)
	var blades: int = i(spec.get("blades"), 5)
	var col: Color = c(spec.get("col"), Color("#1F7A4D"))
	var tip: Color = c(spec.get("tip"), Color("#4FC07A"))
	var rock: Color = c(spec.get("rock"), Color("#4A6470"))
	var sway: float = f(spec.get("sway"), 11.0)
	return func(ci: CanvasItem) -> void:
		var base: Vector2 = Iso.to_screen(at)
		Iso.shadow(ci, at - Vector2(r + 0.05, r + 0.05),
			Vector2(r, r) * 2.0 + Vector2(0.1, 0.1), 0.20)
		Iso.box(ci, at - Vector2(r, r), Vector2(r, r) * 2.0, 9.0, rock)
		var fronds: Array[PackedVector2Array] = []
		for k in blades:
			var u: float = (float(k) + 0.5) / float(maxi(blades, 1))
			var lean: float = lerpf(-1.0, 1.0, u) * sway
			var tall: float = height * lerpf(0.70, 1.0, absf(sin(u * 3.1)))
			var stem := PackedVector2Array()
			for j in 5:
				var t: float = float(j) / 4.0
				stem.append(base + Vector2(lean * t * t + sin(t * PI) * lean * 0.6,
					-9.0 - tall * t))
			fronds.append(stem)
		for stem in fronds:
			Iso.stroke(ci, stem, col.darkened(0.24), 5.0)
		for stem in fronds:
			Iso.stroke(ci, stem, col, 3.0)
		for stem in fronds:
			for j in [2, 3]:
				Iso.pip(ci, stem[j], 2.0, col.lightened(0.16))
		for stem in fronds:
			Iso.pip(ci, stem[4], 2.6, tip)

## Lidded drum. The one prop that says "public building".
static func _bin(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var col: Color = c(spec.get("col"), Color("#5C6B8A"))
	var lid: Color = c(spec.get("lid"), Color("#46536D"))
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, at - Vector2(0.20, 0.20), Vector2(0.40, 0.40), 0.18)
		Iso.cyl(ci, at, 0.18, 20.0, col)
		Iso.cyl(ci, at, 0.20, 22.0, lid)

## Leaflet or merchandise rack.
static func _rack(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var size: Vector2 = v2(spec.get("size"), Vector2(1.2, 0.5))
	var col: Color = c(spec.get("col"), Color("#9C7550"))
	var sheets: Array = cols(spec.get("sheets"), [UI.SAGE, UI.SLATE, UI.PLUM, UI.ACCENT])
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, at + Vector2(0.05, 0.08), size + Vector2(0.05, 0.05), 0.20)
		Iso.box(ci, at, size, 16.0, col)
		var t: Vector2 = Iso.to_screen(at + size * 0.5) + Vector2(0, -16.0)
		for k in sheets.size():
			var p: Vector2 = t + Vector2(-13.0 + float(k) * 8.5, -float(k % 2) * 2.0)
			ci.draw_colored_polygon(PackedVector2Array([
				p + Vector2(-4, 0), p + Vector2(0, -14),
				p + Vector2(4, -12), p + Vector2(0, 2)]), sheets[k])

static func _cabinet(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var size: Vector2 = v2(spec.get("size"), Vector2(0.7, 0.5))
	var height: float = f(spec.get("height"), 34.0)
	var col: Color = c(spec.get("col"), Color("#4E6B84"))
	var pull: Color = c(spec.get("pull"), Color("#8FA9C8"))
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, at + Vector2(0.05, 0.08), size + Vector2(0.05, 0.05), 0.20)
		Iso.box(ci, at, size, height, col)
		var face: Vector2 = Iso.to_screen(at + Vector2(size.x * 0.5, size.y))
		for k in 3:
			var y: float = -8.0 - float(k) * 9.0
			ci.draw_line(face + Vector2(-10, y), face + Vector2(10, y - 6), pull, 2.0)

## Stack of crates, tapering as it goes up.
static func _crate(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var size: Vector2 = v2(spec.get("size"), Vector2(0.8, 0.6))
	var col: Color = c(spec.get("col"), Color("#A9793F"))
	var mid: Color = c(spec.get("mid"), Color("#BE8B4E"))
	var top: Color = c(spec.get("top"), Color("#8A6033"))
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, at + Vector2(0.06, 0.10), size, 0.20)
		Iso.box(ci, at, size, 15.0, col)
		Iso.box(ci, at + Vector2(0.10, 0.08), size - Vector2(0.22, 0.16), 27.0, mid)
		Iso.box(ci, at + Vector2(0.20, 0.16), size - Vector2(0.40, 0.30), 36.0, top)

static func _trolley(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var col: Color = c(spec.get("col"), Color("#46536D"))
	var load: Color = c(spec.get("load"), Color("#BE8B4E"))
	return func(ci: CanvasItem) -> void:
		var base: Vector2 = Iso.to_screen(at)
		Iso.shadow(ci, at - Vector2(0.24, 0.16), Vector2(0.48, 0.32), 0.18)
		ci.draw_line(base + Vector2(-7, 0), base + Vector2(-7, -30), col, 2.6)
		ci.draw_line(base + Vector2(7, 0), base + Vector2(7, -30), col, 2.6)
		ci.draw_line(base + Vector2(-8, -30), base + Vector2(8, -30), col, 2.6)
		Iso.box(ci, at - Vector2(0.20, 0.14), Vector2(0.40, 0.28), 18.0, load)
		Iso.pip(ci, base + Vector2(-7, -1), 3.0, Color("#2B2245"))
		Iso.pip(ci, base + Vector2(7, -1), 3.0, Color("#2B2245"))

## Self-service machine: raked screen, card slot, ticket mouth.
static func _machine(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var size: Vector2 = v2(spec.get("size"), Vector2(0.7, 0.55))
	var col: Color = c(spec.get("col"), Color("#46536D"))
	var screen: Color = c(spec.get("screen"), UI.SAGE.darkened(0.10))
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, at + Vector2(0.05, 0.08), size + Vector2(0.0, 0.05), 0.20)
		Iso.box(ci, at, size, 32.0, col)
		var t: Vector2 = Iso.to_screen(at + Vector2(size.x * 0.5, size.y)) + Vector2(0, -32.0)
		ci.draw_colored_polygon(PackedVector2Array([
			t + Vector2(-13, -2), t + Vector2(0, -9),
			t + Vector2(13, -2), t + Vector2(0, 5)]), Color("#2B2245"))
		ci.draw_colored_polygon(PackedVector2Array([
			t + Vector2(-10, -2), t + Vector2(0, -7),
			t + Vector2(10, -2), t + Vector2(0, 3)]), screen)
		ci.draw_line(t + Vector2(-8, 12), t + Vector2(8, 12), UI.BRASS, 2.6)
		ci.draw_line(t + Vector2(-6, 19), t + Vector2(6, 19), UI.PANEL, 2.2)

## Roll-up banner on a weighted foot.
static func _banner(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var cloth: Color = c(spec.get("col"), UI.ROOM_PROMO)
	var field: Color = c(spec.get("field"), UI.PANEL)
	var motif: Color = c(spec.get("motif"), UI.BRASS)
	var height: float = f(spec.get("height"), 52.0)
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, at - Vector2(0.22, 0.10), Vector2(0.44, 0.20), 0.18)
		var base: Vector2 = Iso.to_screen(at)
		ci.draw_line(base + Vector2(-12, 0), base + Vector2(12, 0), UI.SLATE.darkened(0.4), 3.0)
		ci.draw_colored_polygon(PackedVector2Array([
			base + Vector2(-11, -4), base + Vector2(11, -4),
			base + Vector2(11, -height), base + Vector2(-11, -height)]), cloth)
		ci.draw_colored_polygon(PackedVector2Array([
			base + Vector2(-8, -10), base + Vector2(8, -10),
			base + Vector2(8, -30), base + Vector2(-8, -30)]), field)
		Iso.pip(ci, base + Vector2(0, -height + 12.0), 6.0, motif)

static func _balloons(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var palette: Array = cols(spec.get("cols"), [UI.ROOM_PROMO, UI.ROOM_TICKET, UI.SLATE])
	var offsets: Array = [Vector2(-8.0, -46.0), Vector2(4.0, -54.0), Vector2(11.0, -42.0)]
	return func(ci: CanvasItem) -> void:
		var base: Vector2 = Iso.to_screen(at)
		for k in offsets.size():
			ci.draw_line(base + Vector2(0, -6), base + (offsets[k] as Vector2),
				Color(1, 1, 1, 0.45), 1.2)
		for k in offsets.size():
			ci.draw_circle(base + (offsets[k] as Vector2), 7.0,
				palette[k % palette.size()])
		for k in offsets.size():
			Iso.pip(ci, base + (offsets[k] as Vector2) - Vector2(2.0, 2.0), 2.4,
				Color(1, 1, 1, 0.55))

# --- Dressing kinds -----------------------------------------------------------
##
## These occlude nothing, so VenueFloor draws them straight into the shared
## ground item: no node, no Y-sort slot, and a run of them costs a handful of
## draw calls between them.

static func _rug(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var size: Vector2 = v2(spec.get("size"), Vector2(2.0, 1.5))
	var col: Color = c(spec.get("col"), UI.FLOOR_CREAM.darkened(0.08))
	var border: Color = c(spec.get("border"), Color(0, 0, 0, 0))
	return func(ci: CanvasItem) -> void:
		Iso.rug(ci, at, size, col, border)

static func _patch(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var size: Vector2 = v2(spec.get("size"), Vector2(1.0, 1.0))
	var col: Color = c(spec.get("col"), UI.CARPET_RED)
	return func(ci: CanvasItem) -> void:
		Iso.floor_patch(ci, at, size, col)

static func _picture(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var length: float = f(spec.get("len"), 0.8)
	var axis: String = str(spec.get("axis", "x"))
	var y0: float = f(spec.get("y0"), 22.0)
	var y1: float = f(spec.get("y1"), 38.0)
	var art: Color = c(spec.get("col"), UI.SLATE)
	return func(ci: CanvasItem) -> void:
		Iso.picture(ci, at, length, axis, y0, y1, art)

## Porthole: a round window onto water, set into a wall plane. Does for an
## aquarium's walls what framed pictures do for a museum's, and because it lives
## in the dressing band it costs no node and no Y-sort slot. The disc is built in
## the WALL's basis rather than in screen space, so it shears with the wall it is
## set into instead of reading as a sticker on top of it.
static func _porthole(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var length: float = f(spec.get("len"), 0.7)
	var axis: String = str(spec.get("axis", "x"))
	var dy: float = f(spec.get("dy"), 30.0)
	var rim: Color = c(spec.get("rim"), Color("#8FA9B4"))
	var water: Color = c(spec.get("water"), Color("#1B7FA8"))
	var fauna: Color = c(spec.get("fauna"), UI.BRASS)
	var ry: float = f(spec.get("ry"), 11.0)
	return func(ci: CanvasItem) -> void:
		var a: Vector2 = Iso.to_screen(at)
		var b: Vector2 = Iso.to_screen(at
			+ (Vector2(length, 0.0) if axis == "x" else Vector2(0.0, length)))
		var mid: Vector2 = a.lerp(b, 0.5) + Vector2(0.0, -dy)
		var along: Vector2 = (b - a) * 0.5
		for ring in [[1.00, rim], [0.78, water.darkened(0.30)], [0.62, water]]:
			var scale: float = ring[0]
			var poly := PackedVector2Array()
			for k in 12:
				var an: float = TAU * float(k) / 12.0
				poly.append(mid + along * (cos(an) * scale)
					+ Vector2(0.0, sin(an) * ry * scale))
			ci.draw_colored_polygon(poly, ring[1] as Color)
		Iso.pip(ci, mid + Vector2(0.0, -1.5), 2.8, fauna)

## Small framed notice on a low divider — the row of signs along the ticket hall.
static func _notice(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var length: float = f(spec.get("len"), 0.8)
	var axis: String = str(spec.get("axis", "x"))
	var frame: Color = c(spec.get("frame"), UI.PANEL)
	var field: Color = c(spec.get("col"), UI.ROOM_TICKET.darkened(0.10))
	var y0: float = f(spec.get("y0"), 3.0)
	var y1: float = f(spec.get("y1"), 13.0)
	return func(ci: CanvasItem) -> void:
		var step: Vector2 = Vector2(length * 0.15, 0.0) if axis == "x" \
			else Vector2(0.0, length * 0.15)
		Iso.panel(ci, at, length, axis, y0, y1, frame)
		Iso.panel(ci, at + step, length * 0.7, axis, y0 + 2.0, y1 - 5.0, field,
			Color(0, 0, 0, 0))

## Poster board on a wall, with a highlight pip for a headline.
static func _poster(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var length: float = f(spec.get("len"), 1.8)
	var axis: String = str(spec.get("axis", "x"))
	var y0: float = f(spec.get("y0"), 4.0)
	var y1: float = f(spec.get("y1"), 24.0)
	var board: Color = c(spec.get("col"), UI.PANEL)
	var motif: Color = c(spec.get("motif"), Color(0, 0, 0, 0))
	var motif_at: Vector2 = v2(spec.get("motif_at"), Vector2(0.5, 0.0))
	var motif_dy: float = f(spec.get("motif_dy"), 16.0)
	var motif_r: float = f(spec.get("motif_r"), 4.0)
	return func(ci: CanvasItem) -> void:
		Iso.panel(ci, at, length, axis, y0, y1, board)
		if motif.a > 0.0:
			Iso.pip(ci, Iso.to_screen(at + motif_at) + Vector2(0.0, -motif_dy),
				motif_r, motif)

static func _bunting(spec: Dictionary) -> Callable:
	var a: Vector2 = v2(spec.get("from"))
	var b: Vector2 = v2(spec.get("to"))
	var height: float = f(spec.get("height"), 46.0)
	var sag: float = f(spec.get("sag"), 9.0)
	var flags: int = i(spec.get("flags"), 7)
	var palette: Array = cols(spec.get("cols"),
		[UI.ROOM_TICKET, UI.ROOM_GALLERY, UI.SAGE, UI.SLATE, UI.PLUM])
	return func(ci: CanvasItem) -> void:
		Iso.bunting(ci, a, b, height, sag, palette, flags)
