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

const MuseumProps := preload("res://scenes/venue/floor/museum_props.gd")
const UI := preload("res://scripts/ui/ui_kit.gd")
const Iso := preload("res://scenes/venue/floor/iso.gd")

## Every kind this registry can draw, grouped by what a theme uses it for. The
## test suite renders one of each, so an entry here that has no painter fails
## loudly instead of silently drawing nothing on somebody's new venue.
const EXHIBIT_KINDS: Array[String] = [
	"skeleton", "casket", "statue", "vitrine", "case", "tank", "hanging",
	"hung_skeleton", "touch_pool", "fountain", "mural", "plinth", "orrery", "armor",
	"coral", "clockwork", "throne"]
const FIXTURE_KINDS: Array[String] = [
	"counter", "info_desk", "desk", "vault_door", "facade", "kiosk", "shelf",
	"rope_line"]
const FURNITURE_KINDS: Array[String] = [
	"bench", "cafe_table", "planter", "kelp", "bin", "rack", "cabinet", "crate", "trolley",
	"machine", "banner", "balloons", "recycle_bin"]
const DRESSING_KINDS: Array[String] = [
	"rug", "orbital_inlay", "patch", "picture", "porthole", "notice", "poster", "bunting"]

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
	if str(spec.get("kind","")) == "bench":
		# A centre-sorted long bench covers its first occupant with the whole
		# backrest while drawing the second occupant on top. The front-facing
		# backrest belongs behind BOTH seats; a reversed backrest is in front
		# of both. The painter still uses the same ground coordinates.
		var length := maxf(f(spec.get("len"),1.5),.7)
		var along := length-.075 if bool(spec.get("flip",false)) else .075
		return at+(Vector2(along,.22) if str(spec.get("axis","x"))=="x" else Vector2(.22,along))
	var size: Vector2 = footprint(spec)
	return at + size * 0.5

## Footprint in tiles. `size` wins; length-based kinds carry `len` instead. A
## kind with neither (a planter, a bin, a trolley) is placed BY its anchor rather
## than by a corner, so its footprint is zero and `at` is the anchor.
static func footprint(spec: Dictionary) -> Vector2:
	if spec.has("size"):
		return v2(spec["size"])
	if spec.has("len") or str(spec.get("kind", "")) == "bench":
		var length := f(spec.get("len"), 1.5)
		return Vector2(0.4, length) if str(spec.get("axis", "x")) == "y" else Vector2(length, 0.4)
	return Vector2.ZERO

# --- Registry -----------------------------------------------------------------

## Physical ground bounds; kelp is authored by its centre, other solid pieces
## by a footprint corner. Keep navigation and movement inspection in agreement.
static func solid_rect(spec: Dictionary) -> Rect2:
	var at := v2(spec.get("at"))
	if str(spec.get("kind","")) == "kelp":
		var radius := f(spec.get("r"),.22)
		return Rect2(at-Vector2.ONE*radius,Vector2.ONE*radius*2)
	var size := footprint(spec)
	if size == Vector2.ZERO:
		size = {"crate":Vector2(.8,.6),"cabinet":Vector2(.7,.5),"rack":Vector2(1.2,.5)}.get(str(spec.get("kind","")),Vector2.ZERO)
	var angle := deg_to_rad(f(spec.get("rot"),0))
	var extent := Vector2(absf(cos(angle))*size.x+absf(sin(angle))*size.y,
		absf(sin(angle))*size.x+absf(cos(angle))*size.y)
	return Rect2(at+size*.5-extent*.5,extent)

## The painter for one spec. Returns a Callable taking the CanvasItem to draw
## into, so VenueFloor can hand a floor kind its own node and a dressing kind the
## shared ground item without either knowing the difference.
## Build a painter, and wrap it in a rotation if the spec asks for one.
##
## One place, every kind. `rot` is degrees on the ground plane about the piece's
## own centre; Iso.to_screen does the work, so a painter never learns it is being
## turned. Pieces whose DETAIL is authored in screen space rather than grid space
## — the skeleton's bones, a hanging's wings — rotate as a whole but keep their
## internal offsets facing the camera; those use `flip` instead.
static func painter(kind: String, spec: Dictionary) -> Callable:
	var deg: float = f(spec.get("rot"), 0.0)
	var inner: Callable = _painter_for(kind, spec)
	inner = MuseumProps.painter(str(spec.get("museum_venue", "")), kind, spec, inner)
	if not inner.is_valid():
		return inner
	if is_zero_approx(deg) and str(spec.get("mirror", "")) == "":
		return inner
	var at: Vector2 = v2(spec.get("at"))
	# Turn about the piece's OWN CENTRE. Not every kind carries `size` — a bench
	# is described by `len` along an axis — and defaulting to zero put the pivot on
	# the corner, so rotating swung the piece away across the floor instead of
	# turning it where it stood. Every angle was available and none of them looked
	# like a rotation.
	var size: Vector2 = v2(spec.get("size"), Vector2.ZERO)
	if size == Vector2.ZERO and spec.has("len"):
		var ln: float = f(spec.get("len"), 1.5)
		size = Vector2(ln, 0.5) if str(spec.get("axis", "x")) == "x" \
			else Vector2(0.5, ln)
	var pivot: Vector2 = at + size * 0.5
	var rad: float = deg_to_rad(deg)
	var mir: String = str(spec.get("mirror", ""))
	return func(ci: CanvasItem) -> void:
		Iso.push_mirror(pivot, mir)
		Iso.push_rotation(pivot, rad)
		inner.call(ci)
		Iso.pop_rotation()
		Iso.pop_mirror()


static func _painter_for(kind: String, spec: Dictionary) -> Callable:
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
		"fountain": return _fountain(spec)
		"mural": return _mural(spec)
		"plinth": return _plinth(spec)
		"orrery": return _orrery(spec)
		"armor": return _armor(spec)
		"coral": return _coral(spec)
		"clockwork": return _clockwork(spec)
		"throne": return _throne(spec)
		"counter": return _counter(spec)
		"info_desk": return _info_desk(spec)
		"desk": return _desk(spec)
		"vault_door": return _vault_door(spec)
		"facade": return _facade(spec)
		"kiosk": return _kiosk(spec)
		"shelf": return _shelf(spec)
		"rope_line": return _rope_line(spec)
		"bench": return _bench(spec)
		"cafe_table": return _cafe_table(spec)
		"planter": return _planter(spec)
		"kelp": return _kelp(spec)
		"bin": return _bin(spec)
		"recycle_bin": return _recycle_bin(spec)
		"rack": return _rack(spec)
		"cabinet": return _cabinet(spec)
		"crate": return _crate(spec)
		"trolley": return _trolley(spec)
		"machine": return _machine(spec)
		"banner": return _banner(spec)
		"balloons": return _balloons(spec)
		"rug": return _rug(spec)
		"orbital_inlay": return _orbital_inlay(spec)
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
	# Which way the animal LOOKS. Neck, skull, tail and legs are screen-space
	# offsets hung off the spine, so mirroring x is what turns it round — swapping
	# `size` would only rotate the plinth underneath and leave the skeleton facing
	# the same way, which is not what "turn the exhibit round" means.
	var face: float = -1.0 if bool(spec.get("flip", false)) else 1.0
	if face < 0.0:
		var mneck: Array[Vector2] = []
		for q in neck:
			mneck.append(Vector2(-q.x, q.y))
		neck = mneck
		var mtail: Array[Vector2] = []
		for q in tail:
			mtail.append(Vector2(-q.x, q.y))
		tail = mtail
		skull_at = Vector2(-skull_at.x, skull_at.y)
		var mlegs: Array = []
		for q in legs:
			mlegs.append(-float(q))
		legs = mlegs
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
		Iso.fill(ci, head, bone)
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
		Iso.fill(ci, lid, body)
		ci.draw_line(mid + Vector2(-8, -tall), mid + Vector2(-8, -4),
			Color(1, 1, 1, 0.22), 5.0)
		Iso.fill(ci, PackedVector2Array([
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
		Iso.fill(ci, PackedVector2Array([
			t + Vector2(-7, 0), t + Vector2(7, 0),
			t + Vector2(5, -25), t + Vector2(-5, -25)]), stone)
		ci.draw_line(t + Vector2(-6, -21), t + Vector2(-13, -33), stone, 4.6)
		ci.draw_line(t + Vector2(6, -21), t + Vector2(12, -29), stone, 4.6)
		ci.draw_circle(t + Vector2(0, -32), 6.2, stone)
		ci.draw_arc(t + Vector2(0, -32), 6.2, 0.0, TAU, 16, edge, 1.6)
		ci.draw_line(t + Vector2(-7, -1), t + Vector2(7, -1), edge, 1.8)

## Ringed astronomical instrument. Its open circles and orbiting pips remain a
## distinct silhouette at the late venues' small camera zooms.
static func _orrery(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var size: Vector2 = v2(spec.get("size"), Vector2(1.5, 1.2))
	var base_h: float = f(spec.get("plinth_h"), 14.0)
	var base: Color = c(spec.get("base"), Color("#657C86"))
	var metal: Color = c(spec.get("metal"), UI.BRASS)
	var orbit: Color = c(spec.get("orbit"), Color("#B9E8F0"))
	var sun: Color = c(spec.get("sun"), Color("#FFD65A"))
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, at + Vector2(0.06, 0.10), size + Vector2(0.06, 0.06), 0.22)
		Iso.box(ci, at, size, base_h, base)
		var centre := Iso.to_screen(at + size * 0.5) + Vector2(0.0, -base_h - 26.0)
		ci.draw_line(centre + Vector2(0.0, 28.0), centre + Vector2(0.0, 8.0), metal, 4.0)
		for radius in [13.0, 21.0, 29.0]:
			ci.draw_arc(centre, radius, 0.0, TAU, 28, orbit, 2.0, true)
		ci.draw_line(centre + Vector2(-29.0, 9.0), centre + Vector2(29.0, -9.0),
			metal.darkened(0.12), 2.0, true)
		ci.draw_line(centre + Vector2(-18.0, -22.0), centre + Vector2(18.0, 22.0),
			metal, 1.8, true)
		Iso.pip(ci, centre, 6.0, sun)
		for planet in [Vector2(12.0, -5.0), Vector2(-18.0, 9.0), Vector2(25.0, -8.0)]:
			Iso.pip(ci, centre + planet, 2.8, metal.lightened(0.24))

## Full ceremonial armour: breastplate, helm, shield and spear on one mount.
static func _armor(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var size: Vector2 = v2(spec.get("size"), Vector2(1.3, 1.1))
	var base_h: float = f(spec.get("plinth_h"), 15.0)
	var base: Color = c(spec.get("base"), Color("#756A5E"))
	var metal: Color = c(spec.get("metal"), Color("#AAB2B8"))
	var cloth: Color = c(spec.get("cloth"), Color("#8C342C"))
	var trim: Color = c(spec.get("trim"), UI.BRASS)
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, at + Vector2(0.06, 0.10), size + Vector2(0.06, 0.06), 0.22)
		Iso.box(ci, at, size, base_h, base)
		var t := Iso.to_screen(at + size * 0.5) + Vector2(0.0, -base_h)
		Iso.fill(ci, PackedVector2Array([
			t + Vector2(-13, -4), t + Vector2(13, -4),
			t + Vector2(10, -34), t + Vector2(-10, -34)]), cloth)
		Iso.fill(ci, PackedVector2Array([
			t + Vector2(-11, -13), t + Vector2(0, -5), t + Vector2(11, -13),
			t + Vector2(8, -31), t + Vector2(-8, -31)]), metal)
		ci.draw_circle(t + Vector2(0, -42), 9.0, metal)
		ci.draw_line(t + Vector2(-8, -42), t + Vector2(8, -42), trim, 2.4)
		ci.draw_line(t + Vector2(-20, -8), t + Vector2(-20, -54), trim, 3.0)
		ci.draw_circle(t + Vector2(19, -20), 12.0, cloth.darkened(0.15))
		ci.draw_arc(t + Vector2(19, -20), 12.0, 0.0, TAU, 18, trim, 2.2)
		Iso.pip(ci, t + Vector2(19, -20), 3.0, trim)

## Branching coral garden on a flooded plinth. Lines batch, while the irregular
## forked crown gives the ocean palaces a silhouette no tank can provide.
static func _coral(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var size: Vector2 = v2(spec.get("size"), Vector2(1.7, 1.2))
	var rim_h: float = f(spec.get("rim_h"), 11.0)
	var rim: Color = c(spec.get("rim"), Color("#6F96A4"))
	var water: Color = c(spec.get("water"), Color("#2CAFC1"))
	var branches: Array = cols(spec.get("branches"),
		[Color("#F07D78"), Color("#F3C969"), Color("#CF89D8")])
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, at + Vector2(0.06, 0.10), size + Vector2(0.06, 0.06), 0.22)
		Iso.box(ci, at, size, rim_h, rim)
		var bed := Iso.quad(at + Vector2(0.12, 0.12), size - Vector2(0.24, 0.24))
		for k in bed.size():
			bed[k] += Vector2(0.0, -rim_h + 3.0)
		Iso.fill(ci, bed, Color(water.r, water.g, water.b, 0.72))
		var centre := Iso.to_screen(at + size * 0.5) + Vector2(0.0, -rim_h)
		for k in 5:
			var root := centre + Vector2(lerpf(-22.0, 22.0, float(k) / 4.0), 2.0)
			var top := root + Vector2(float((k % 3) - 1) * 5.0, -lerpf(18.0, 35.0,
				float((k * 3) % 5) / 4.0))
			var col: Color = branches[k % branches.size()]
			ci.draw_line(root, top, col.darkened(0.12), 5.0, true)
			ci.draw_line(top, top + Vector2(-8.0, -8.0), col, 3.6, true)
			ci.draw_line(top, top + Vector2(8.0, -6.0), col.lightened(0.12), 3.6, true)
			Iso.pip(ci, top + Vector2(-8.0, -8.0), 2.2, col.lightened(0.22))

## Tall mechanical timepiece with an exposed face and swinging-weight chamber.
static func _clockwork(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var size: Vector2 = v2(spec.get("size"), Vector2(1.2, 1.0))
	var base_h: float = f(spec.get("plinth_h"), 12.0)
	var base: Color = c(spec.get("base"), Color("#777B84"))
	var body: Color = c(spec.get("body"), Color("#6E4A2E"))
	var metal: Color = c(spec.get("metal"), UI.BRASS)
	var face: Color = c(spec.get("face"), Color("#F4E8C5"))
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, at + Vector2(0.06, 0.10), size + Vector2(0.06, 0.06), 0.22)
		Iso.box(ci, at, size, base_h, base)
		var t := Iso.to_screen(at + size * 0.5) + Vector2(0.0, -base_h)
		Iso.fill(ci, PackedVector2Array([
			t + Vector2(-17, 0), t + Vector2(17, 0),
			t + Vector2(14, -58), t + Vector2(-14, -58)]), body)
		ci.draw_rect(Rect2(t + Vector2(-11, -34), Vector2(22, 27)),
			body.lightened(0.12))
		ci.draw_line(t + Vector2(0, -29), t + Vector2(0, -13), metal, 2.2)
		Iso.pip(ci, t + Vector2(0, -10), 5.0, metal)
		ci.draw_circle(t + Vector2(0, -47), 12.0, metal.darkened(0.16))
		ci.draw_circle(t + Vector2(0, -47), 9.5, face)
		ci.draw_line(t + Vector2(0, -47), t + Vector2(0, -54), body, 1.8)
		ci.draw_line(t + Vector2(0, -47), t + Vector2(6, -44), body, 1.8)
		for a in [0.0, PI * 0.5, PI, PI * 1.5]:
			Iso.pip(ci, t + Vector2(0, -47) + Vector2(cos(a), sin(a)) * 7.0,
				1.15, metal)

## Raised ceremonial throne with a crown-shaped back and contrasting cushion.
static func _throne(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var size: Vector2 = v2(spec.get("size"), Vector2(1.5, 1.2))
	var base_h: float = f(spec.get("plinth_h"), 14.0)
	var base: Color = c(spec.get("base"), Color("#B99EBB"))
	var body: Color = c(spec.get("body"), Color("#5C426E"))
	var cushion: Color = c(spec.get("cushion"), Color("#D35F8D"))
	var trim: Color = c(spec.get("trim"), UI.BRASS)
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, at + Vector2(0.06, 0.10), size + Vector2(0.06, 0.06), 0.22)
		Iso.box(ci, at, size, base_h, base)
		var t := Iso.to_screen(at + size * 0.5) + Vector2(0.0, -base_h)
		Iso.fill(ci, PackedVector2Array([
			t + Vector2(-20, -4), t + Vector2(20, -4),
			t + Vector2(17, -48), t + Vector2(8, -58),
			t + Vector2(0, -49), t + Vector2(-8, -58), t + Vector2(-17, -48)]), body)
		Iso.fill(ci, PackedVector2Array([
			t + Vector2(-15, -4), t + Vector2(15, -4),
			t + Vector2(13, -18), t + Vector2(-13, -18)]), cushion)
		ci.draw_line(t + Vector2(-17, -45), t + Vector2(17, -45), trim, 3.0)
		ci.draw_line(t + Vector2(-22, -18), t + Vector2(-22, -2), trim, 4.0)
		ci.draw_line(t + Vector2(22, -18), t + Vector2(22, -2), trim, 4.0)
		for crown_x in [-9.0, 0.0, 9.0]:
			Iso.pip(ci, t + Vector2(crown_x, -53.0 - (4.0 if crown_x == 0.0 else 0.0)),
				2.8, trim)

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
		Iso.fill(ci, PackedVector2Array([
			t + Vector2(-9, -10), t + Vector2(0, -21),
			t + Vector2(9, -10), t + Vector2(0, 1)]), art)
		Iso.fill(ci, PackedVector2Array([
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
			Iso.fill(ci, PackedVector2Array([
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
			Iso.fill(ci, blade, weed.darkened(0.10 * float(k % 2)))
		for k in swimmers:
			var u: float = (float(k) + 0.5) / float(maxi(swimmers, 1))
			var p: Vector2 = t + Vector2(lerpf(-17.0, 17.0, u),
				-glass_h * lerpf(0.30, 0.80, fmod(u * 2.7, 1.0)))
			var col: Color = fauna[k % fauna.size()]
			Iso.fill(ci, PackedVector2Array([
				p + Vector2(-6, 0), p + Vector2(1, -4),
				p + Vector2(6, 0), p + Vector2(1, 4)]), col)
			Iso.fill(ci, PackedVector2Array([
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
			Iso.fill(ci, PackedVector2Array([
				mid + Vector2(0, -3), mid + Vector2(-span, -span * 0.34),
				mid + Vector2(-span * 0.4, 5)]), body.darkened(0.18))
			Iso.fill(ci, PackedVector2Array([
				mid + Vector2(0, -3), mid + Vector2(span, -span * 0.30),
				mid + Vector2(span * 0.4, 5)]), body)
		var hull := PackedVector2Array([
			mid + Vector2(-span * 0.62, 0), mid + Vector2(-span * 0.2, -span * 0.20),
			mid + Vector2(span * 0.5, -span * 0.14), mid + Vector2(span * 0.62, 0),
			mid + Vector2(span * 0.4, span * 0.16), mid + Vector2(-span * 0.3, span * 0.18)])
		Iso.fill(ci, hull, body)
		Iso.fill(ci, PackedVector2Array([
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
		Iso.fill(ci, PackedVector2Array([
			head + Vector2(-5, -7), head + Vector2(skull - 4, -3),
			head + Vector2(skull, 2), head + Vector2(-5, 6)]), bone)
		var tail: Vector2 = spine[0]
		Iso.fill(ci, PackedVector2Array([
			tail + Vector2(3, 0), tail + Vector2(-9, -fluke),
			tail + Vector2(-15, 0), tail + Vector2(-9, fluke)]), bone)
		ci.draw_line(head + Vector2(-3, 1), head + Vector2(skull - 3, 0), edge, 1.6)
		Iso.pip(ci, head + Vector2(2, -2), 2.0, edge)

## Open touch pool: a walled basin of shallow water over sand, with tide-pool
## animals in it. The one exhibit visitors look DOWN into rather than through, so
## it is a low box with a sunken water plane instead of a glazed volume — and
## that is why it is its own kind and not a short `tank`.
## A purchased brass fountain has a raised tier and falling water, rather than
## sharing the shallow aquarium touch-pool silhouette.
static func _fountain(spec: Dictionary) -> Callable:
	var at := v2(spec.get("at"))
	var size := v2(spec.get("size"), Vector2(1.3, 1.0))
	var centre := at + size * 0.5
	var brass := c(spec.get("rim"), Color("#B08A4A"))
	var water := c(spec.get("water"), Color("#4FA8D8"))
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, at, size, 0.24)
		Iso.cyl(ci, centre, 0.48, 12, brass)
		var p := Iso.to_screen(centre)
		var pool := PackedVector2Array()
		for j in 40:
			var a := TAU * j / 40.0
			pool.append(p + Vector2(cos(a) * 0.40 * Iso.TILE.x, sin(a) * 0.40 * Iso.TILE.y - 12))
		Iso.fill(ci, pool, water)
		Iso.cyl(ci, centre, 0.09, 43, brass.lightened(0.15))
		var tier := PackedVector2Array()
		for j in 40:
			var a := TAU * j / 40.0
			tier.append(p + Vector2(cos(a) * 12, sin(a) * 5 - 37))
		Iso.fill(ci, tier, brass.lightened(0.35))
		for side in [-1, 1]:
			var stream := PackedVector2Array()
			for j in 16:
				var t := j / 15.0
				stream.append(p + Vector2(side * (9 + 13 * t), -37 + 25 * t * t))
			ci.draw_polyline(stream, Color("#B9EEEF"), 2.4, true)
			ci.draw_arc(p + Vector2(side * 22, -12), 4, 0, TAU, 16, Color("#C9F4F1"), 1, true)
		ci.draw_line(p + Vector2(0, -43), p + Vector2(0, -50), Color("#C9F4F1"), 2, true)

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
		Iso.fill(ci, bed, sand)
		Iso.fill(ci, bed, Color(water.r, water.g, water.b, 0.52))
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
			Iso.fill(ci, PackedVector2Array([
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
	var original_body := func(ci: CanvasItem) -> void:
		Iso.shadow(ci, at + Vector2(0.05, 0.10), size + Vector2(0.0, 0.02), 0.20)
		Iso.box(ci, at, size, height, body)
		Iso.box(ci, at + Vector2(-0.05, -0.05), size + Vector2(0.1, 0.1), height + 3.0,
			trim, Color(0, 0, 0, 0.22))
	var body_painter := MuseumProps.painter(str(spec.get("museum_venue", "")), "counter_body", spec, original_body)
	return func(ci: CanvasItem) -> void:
		body_painter.call(ci)
		# 0.28 tiles back from `at` is the working face of the counter — the strip
		# the clerk's kit stands on, whatever the counter's width.
		var top: float = -height - 3.0
		var mon: Vector2 = Iso.to_screen(at + Vector2(size.x - 0.33, 0.28)) + Vector2(0, top)
		Iso.fill(ci, PackedVector2Array([
			mon + Vector2(-8, -17), mon + Vector2(8, -17),
			mon + Vector2(8, -4), mon + Vector2(-8, -4)]), Color("#2B2245"))
		Iso.fill(ci, PackedVector2Array([
			mon + Vector2(-6, -15), mon + Vector2(6, -15),
			mon + Vector2(6, -6), mon + Vector2(-6, -6)]), UI.SLATE.lightened(0.25))
		var tray: Vector2 = Iso.to_screen(at + Vector2(0.30, 0.28)) + Vector2(0, top)
		for k in 3:
			var ty: float = -float(k) * 2.6
			Iso.fill(ci, PackedVector2Array([
				tray + Vector2(-8, ty), tray + Vector2(0, ty - 4),
				tray + Vector2(8, ty), tray + Vector2(0, ty + 4)]),
				UI.PANEL if k % 2 == 0 else UI.FLOOR_CREAM)
		# Wide frosted cashier display. VenueFloor projects the station's live
		# cash text into this exact face; the old narrow pane read as a stray
		# light-blue square rather than a purposeful display.
		Iso.panel(ci, at + Vector2(-0.12, size.y + 0.02), size.x + 0.24, "x", 20.0, 44.0,
			Color(0.66, 0.88, 0.98, 0.58), Color(1, 1, 1, 0.52))
		# Crisp rim and diagonal glints make this read as polished cashier glass,
		# while keeping the live cash label unobstructed in its center.
		var glass_l := Iso.to_screen(at + Vector2(-0.06, size.y + 0.04)) + Vector2(0, -30)
		var glass_r := Iso.to_screen(at + Vector2(size.x + 0.06, size.y + 0.04)) + Vector2(0, -30)
		ci.draw_line(glass_l, glass_r, Color(1, 1, 1, 0.82), 2.0, true)
		var glint_mid := glass_l.lerp(glass_r, 0.30)
		ci.draw_line(glint_mid + Vector2(-7, 9), glint_mid + Vector2(5, -7),
			Color(1, 1, 1, 0.62), 2.2, true)
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
	var original_body := func(ci: CanvasItem) -> void:
		Iso.shadow(ci, at + Vector2(0.06, 0.10), size + Vector2(0.1, 0.1), 0.20)
		Iso.box(ci, at, size, height, body)
		Iso.box(ci, at + Vector2(-0.05, -0.05), size + Vector2(0.1, 0.1), height + 3.0,
			trim, Color(0, 0, 0, 0.22))
	var body_painter := MuseumProps.painter(str(spec.get("museum_venue","")),"info_body",spec,original_body)
	return func(ci: CanvasItem) -> void:
		body_painter.call(ci)
		var sign: Vector2 = Iso.to_screen(at + Vector2(size.x * 0.5, size.y * 0.5)) \
			+ Vector2(0, -height - 3.0)
		Iso.fill(ci, PackedVector2Array([
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
		Iso.fill(ci, PackedVector2Array([
			mon + Vector2(-9, -20), mon + Vector2(9, -20),
			mon + Vector2(9, -6), mon + Vector2(-9, -6)]), Color("#2B2245"))
		Iso.fill(ci, PackedVector2Array([
			mon + Vector2(-7, -18), mon + Vector2(7, -18),
			mon + Vector2(7, -8), mon + Vector2(-7, -8)]), screen)

## Glazed secure-room doors used by the porters.
##
## The old painter was a round vault dial on a solid slab. At gameplay scale it
## read as machinery rather than an entrance, and its brass centre looked like a
## knob the porter never touched. Two framed panes, a centre split and an access
## pad retain the secure-room read while making the route through it explicit.
static func _vault_door(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var length: float = f(spec.get("len"), 1.4)
	var axis: String = str(spec.get("axis", "y"))
	var height: float = f(spec.get("height"), 40.0)
	var recess: Color = c(spec.get("col"), UI.ROOM_VAULT.darkened(0.42))
	var rim: Color = c(spec.get("rim"), Color("#3C5068"))
	var glass: Color = c(spec.get("glass"), Color("#7196B3"))
	glass.a = f(spec.get("glass_alpha"), 0.68)
	var keypad: Color = c(spec.get("keypad"), Color("#24354C"))
	var state: Dictionary = spec.get("_door_state", {}) as Dictionary
	var along := Vector2(1.0, 0.0) if axis == "x" else Vector2(0.0, 1.0)
	var gap := 0.055
	var inset := 0.055
	var leaf_len := length * 0.5 - gap - inset
	return func(ci: CanvasItem) -> void:
		var open := clampf(float(state.get("open", spec.get("open", 0.0))), 0.0, 1.0)
		# Recess first, then a full frame. The dark strip visible between moving
		# panes is what makes an open door read as somewhere a porter can pass.
		Iso.panel(ci, at, length, axis, 0.0, height, recess.darkened(0.38))
		Iso.panel(ci, at, length, axis, 0.0, height, rim)
		var travel := leaf_len * 0.82 * open
		var left_at := at + along * (inset - travel)
		var right_at := at + along * (length * 0.5 + gap + travel)
		for pane_at in [left_at, right_at]:
			Iso.panel(ci, pane_at, leaf_len, axis, 3.0, height - 3.0, glass, rim)
			var glint_a := Iso.to_screen(pane_at + along * (leaf_len * 0.28)) \
				+ Vector2(0.0, -height * 0.76)
			var glint_b := Iso.to_screen(pane_at + along * (leaf_len * 0.62)) \
				+ Vector2(0.0, -height * 0.43)
			ci.draw_line(glint_a, glint_b, Color(1.0, 1.0, 1.0, 0.42), 1.8, true)
		# Access pad belongs to the right-hand pane and travels with it. Its four
		# lit keys survive the phone camera better than tiny text would.
		var key_c := Iso.to_screen(right_at + along * (leaf_len * 0.72)) \
			+ Vector2(0.0, -height * 0.46)
		ci.draw_rect(Rect2(key_c - Vector2(5.0, 8.0), Vector2(10.0, 16.0)), keypad)
		for ky in 2:
			for kx in 2:
				Iso.pip(ci, key_c + Vector2(-2.3 + float(kx) * 4.6,
					-3.0 + float(ky) * 5.2), 1.15, UI.BRASS.lightened(0.16))

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
	var state: Dictionary = spec.get("_door_state", {}) as Dictionary
	return func(ci: CanvasItem) -> void:
		var open := clampf(float(state.get("open", spec.get("open", 0.0))), 0.0, 1.0)
		Iso.wall(ci, at, length, "x", wall_col, height)
		var d0: Vector2 = at + Vector2(door_at, 0.0)
		Iso.panel(ci, d0 - Vector2(0.14, 0.0), leaf * 2.0 + 0.28, "x", 0.0, height - 4.0,
			reveal)
		# Automatic leaves slide apart while an NPC is on either threshold. The
		# underlying reveal remains fixed, so the moving gap reads as an opening
		# rather than two doors stretching thinner.
		var travel := leaf * 0.78 * open
		var left_at := d0 - Vector2(travel, 0.0)
		var right_at := d0 + Vector2(leaf + travel, 0.0)
		Iso.panel(ci, left_at, leaf, "x", 2.0, height - 9.0, left)
		Iso.panel(ci, right_at, leaf, "x", 2.0, height - 9.0, right)
		Iso.panel(ci, d0 + Vector2(0.16, 0.0), leaf * 2.0 - 0.32, "x", height - 4.0,
			height + 6.0, fan)
		var left_handle: Vector2 = Iso.to_screen(left_at + Vector2(leaf * 0.86, 0.0))
		var right_handle: Vector2 = Iso.to_screen(right_at + Vector2(leaf * 0.14, 0.0))
		Iso.pip(ci, left_handle + Vector2(0.0, -18.0), 2.6, UI.BRASS)
		Iso.pip(ci, right_handle + Vector2(0.0, -16.0), 2.6, UI.BRASS)
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
		Iso.fill(ci, PackedVector2Array([
			t + Vector2(-11, -6), t + Vector2(2, -12),
			t + Vector2(11, -5), t + Vector2(-2, 1)]), Color("#2B2245"))
		Iso.fill(ci, PackedVector2Array([
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
	# Which way the bays RUN. Shelving stepped along size.x unconditionally, so a
	# unit turned to face a side wall collapsed every bay onto one point (the step
	# becomes zero). Same defect the bench had: furniture with a long axis needs to
	# know which way that axis points before it can be put against a wall.
	var along_x: bool = str(spec.get("axis", "x")) == "x"
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, at + Vector2(0.06, 0.10), size + Vector2(0.06, 0.06), 0.20)
		Iso.box(ci, at, size, height, body)
		var run: float = size.x if along_x else size.y
		var across: float = size.y if along_x else size.x
		var step: float = (run - 0.5) / float(maxi(bays - 1, 1))
		var tops: Array[Vector2] = []
		for k in bays:
			var a: float = 0.25 + float(k) * step
			tops.append(Iso.to_screen(at + (Vector2(a, across * 0.5)
				if along_x else Vector2(across * 0.5, a))) + Vector2(0, -height))
		for top in tops:
			Iso.fill(ci, PackedVector2Array([
				top + Vector2(-7, -3), top + Vector2(2, -7),
				top + Vector2(9, -3), top + Vector2(0, 1)]), goods)
		for k in bays:
			if k % 2 == 0:
				Iso.fill(ci, PackedVector2Array([
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

## Gallery bench: slatted timber on cast-iron end frames.
##
## Was two slabs — one box for the seat, one for the back — which read as a board
## built into the floor rather than as furniture anyone could sit on. Reported as
## exactly that, by a player who had not realised they were benches at all.
##
## What buys the read, in order of how much each contributes:
##   · END FRAMES standing proud of the timber, in dark metal. The biggest single
##     cue: the piece now has legs and a silhouette instead of being a plinth
##     flush with the ground.
##   · SLATS with gaps. `box` extrudes upward from the grid plane and cannot float
##     a slab, so the seat is three shallow boxes at stepped heights and the back
##     is two boxes whose TOP faces land where the rails belong. The eye reads
##     slats and a gap, which is all that matters at this size.
##   · ARMRESTS, so the ends read as finished rather than sawn off, and the
##     length stays legible.
static func _bench(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var length: float = maxf(f(spec.get("len"), 1.5), 0.7)
	# Which way the bench RUNS. Benches used to be x-only, so one placed against a
	# north-south wall lay across it at right angles and read as bolted to it, or as
	# a plank wedged between two rooms. A bench belongs ALONG a wall, and "along"
	# means it has to know which way the wall goes.
	var along_x: bool = str(spec.get("axis", "x")) == "x"
	# Which side the BACK is on. `axis` alone gives two orientations; a bench also
	# has a front, so without this its occupants can only ever face one way and
	# "put it facing the hall" is unanswerable for half the walls in a room.
	# Together the two flags give the four facings the projection actually has.
	var flip: bool = bool(spec.get("flip", false))
	var col: Color = c(spec.get("col"), Color("#A9793F"))
	var rail: Color = c(spec.get("rail"), Color("#8A6033"))
	var metal: Color = c(spec.get("metal"), Color("#3A3340"))
	return func(ci: CanvasItem) -> void:
		# `a` runs with the bench, `across` spans its depth, so one body of code
		# draws every orientation instead of four copies that drift apart. When
		# flipped, each element is mirrored about the bench's own depth span
		# [-0.04, 0.48] — hence the 0.44 — which reverses the seat slats and moves
		# the back and armrests to the far side without moving the footprint.
		var v := func(a: float, across: float, depth: float = 0.0) -> Vector2:
			var cc: float = (0.44 - across - depth) if flip else across
			return Vector2(a, cc) if along_x else Vector2(cc, a)
		Iso.shadow(ci, at + v.call(0.05, 0.10, 0.54), v.call(length, 0.54), 0.20)
		var slat_w: float = length - 0.30
		# Painted back to front, and mirroring the bench MIRRORS THAT ORDER too.
		#
		# Turning the bench around does not just move its parts: it swaps which of
		# them is nearer the camera. Facing away, the backrest stands between you
		# and the seat and has to cover it. Mirroring the geometry while keeping
		# the original order left the seat painting over the back, so a flipped
		# bench read as a normal bench with its slats in the wrong place rather
		# than as one seen from behind.
		var back := func() -> void:
			Iso.box(ci, at + v.call(0.14, -0.015, 0.05), v.call(slat_w + 0.02, 0.05),
				24.5, rail.lightened(0.20))
			Iso.box(ci, at + v.call(0.15, 0.03, 0.07), v.call(slat_w, 0.07), 17.5, rail)
		var frames := func() -> void:
			for ex in [0.0, length - 0.15]:
				Iso.box(ci, at + v.call(ex, -0.04, 0.52), v.call(0.15, 0.52), 7.5, metal)
		var seat := func() -> void:
			for i in 3:
				Iso.box(ci, at + v.call(0.15, 0.13 + float(i) * 0.13, 0.09),
					v.call(slat_w, 0.09), 8.5, col)
			for ex in [0.01, length - 0.18]:
				Iso.box(ci, at + v.call(ex, 0.10, 0.36), v.call(0.17, 0.36), 15.5, metal)
		if flip:
			seat.call()
			frames.call()
			back.call()          # nearest the camera when the bench faces away
		else:
			back.call()
			frames.call()
			seat.call()

## Café table with four stools.
##
## The top is a `disc`, not a `cyl`. Drawn as a cylinder it was a 22px-tall barrel
## the full width of the table, and in a pale palette that made every table the
## brightest object in the room — the lounges read as a row of white drums. A thin
## top on a slim pedestal reads as a table, and the stools are sized to be seen:
## at r 0.13 they vanished against the pedestal, which left the drum with nothing
## around it to explain what it was.
## One source for drawn stools and visitor destinations. Two-seat bistro
## tables leave room for the approved adult silhouettes at the phone camera.
static func cafe_seat_offsets(spec: Dictionary) -> Array[Vector2]:
	if str(spec.get("seating", "four")) == "pair":
		return [Vector2(-0.50, 0.25), Vector2(0.50, -0.25)]
	return [Vector2(-0.44, -0.14), Vector2(0.44, -0.14),
		Vector2(-0.30, 0.34), Vector2(0.30, 0.34)]

static func _cafe_table(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var top: Color = c(spec.get("col"), Color("#E8D9A8"))
	var stool: Color = c(spec.get("stool"), Color("#2F5B66"))
	var seats: Array[Vector2] = cafe_seat_offsets(spec)
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, at - Vector2(0.48, 0.42), Vector2(0.96, 0.84), 0.22)
		# Back stools first, then the table, then the near stools, so the table
		# occludes what is behind it and is occluded by what is in front.
		for off in seats:
			if off.x + off.y > 0.0:
				continue
			Iso.cyl(ci, at + off, 0.17, 8.5, stool)
			Iso.disc(ci, at + off, 0.19, 8.5, stool.lightened(0.18), 2.0)
		Iso.cyl(ci, at, 0.10, 18.0, stool.darkened(0.34))
		# Narrower and thicker than the first pass: a wide thin top read as a
		# pancake lying on the floor rather than as a table standing on a leg.
		Iso.disc(ci, at, 0.26, 19.5, top, 5.0)
		for off in seats:
			if off.x + off.y <= 0.0:
				continue
			Iso.cyl(ci, at + off, 0.17, 8.5, stool)
			Iso.disc(ci, at + off, 0.19, 8.5, stool.lightened(0.18), 2.0)

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
	# Silhouette, not just palette. Every planter in the game was the same fan of
	# straight blades in a square pot, so a floor with a dozen of them read as one
	# plant stamped twelve times. These change the OUTLINE, which is the only part
	# that survives being minified onto a phone.
	var style: String = str(spec.get("style", "fern"))
	var bloom: Color = c(spec.get("bloom"), Color("#E8698F"))
	return func(ci: CanvasItem) -> void:
		var base: Vector2 = Iso.to_screen(at)
		Iso.shadow(ci, at - Vector2(r + 0.04, r + 0.04),
			Vector2(r, r) * 2.0 + Vector2(0.08, 0.08), 0.20)
		Iso.box(ci, at - Vector2(r, r), Vector2(r, r) * 2.0, 13.0, pot)
		var top: Vector2 = base + Vector2(0, -13.0)
		if style == "bush" or style == "flower":
			# A dense mound rather than a fan: three stacked ellipses.
			for k in 3:
				var rr: float = reach * (0.86 - 0.16 * float(k))
				Iso.pip(ci, top + Vector2(0.0, -rr * 0.34 - float(k) * 3.0),
					rr * 0.60, leaf.lightened(0.06 * float(k)))
			if style == "flower":
				for k in 5:
					var an: float = TAU * float(k) / 5.0
					Iso.pip(ci, top + Vector2(cos(an) * reach * 0.44,
						sin(an) * reach * 0.26 - 7.0), 2.6, bloom)
			return
		if style == "topiary":
			# Clipped spheres on a stem — the formal one, for a grand hall.
			ci.draw_line(top, top + Vector2(0.0, -reach), leaf.darkened(0.34), 3.0)
			Iso.pip(ci, top + Vector2(0.0, -reach * 0.52), reach * 0.34, leaf)
			Iso.pip(ci, top + Vector2(0.0, -reach * 1.02), reach * 0.26,
				leaf.lightened(0.10))
			return
		var spread: float = 0.55 if style == "palm" else 1.0
		var droop: float = 0.42 if style == "palm" else 0.0
		var tips: Array[Vector2] = []
		for k in blades:
			var a: float = -PI * 0.5 + lerpf(-1.0, 1.0,
				float(k) / float(maxi(blades - 1, 1))) * spread
			tips.append(top + Vector2(cos(a), sin(a) + droop) * reach)
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

## Recycling bin. Same body as the litter bin so they read as a matched pair,
## distinguished by lid colour and the chevron ring — which is how they are told
## apart in a real foyer too.
static func _recycle_bin(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var col: Color = c(spec.get("col"), Color("#3E7A5A"))
	var lid: Color = c(spec.get("lid"), Color("#2F5F46"))
	var mark: Color = c(spec.get("mark"), Color("#B9E8C8"))
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, at - Vector2(0.20, 0.20), Vector2(0.40, 0.40), 0.18)
		Iso.cyl(ci, at, 0.18, 20.0, col)
		Iso.cyl(ci, at, 0.20, 22.0, lid)
		var c0: Vector2 = Iso.to_screen(at) + Vector2(0.0, -14.0)
		for k in 3:
			var a: float = TAU * float(k) / 3.0 - PI * 0.5
			var tip: Vector2 = c0 + Vector2(cos(a) * 6.0, sin(a) * 4.0)
			var nxt: float = a + TAU / 3.0
			ci.draw_line(tip, c0 + Vector2(cos(nxt) * 6.0, sin(nxt) * 4.0), mark, 1.8)

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
			Iso.fill(ci, PackedVector2Array([
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
		Iso.fill(ci, PackedVector2Array([
			t + Vector2(-13, -2), t + Vector2(0, -9),
			t + Vector2(13, -2), t + Vector2(0, 5)]), Color("#2B2245"))
		Iso.fill(ci, PackedVector2Array([
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
		Iso.fill(ci, PackedVector2Array([
			base + Vector2(-11, -4), base + Vector2(11, -4),
			base + Vector2(11, -height), base + Vector2(-11, -height)]), cloth)
		Iso.fill(ci, PackedVector2Array([
			base + Vector2(-8, -10), base + Vector2(8, -10),
			base + Vector2(8, -30), base + Vector2(-8, -30)]), field)
		Iso.pip(ci, base + Vector2(0, -height + 12.0), 6.0, motif)

static func _balloons(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var tie_height: float = f(spec.get("tie_height"), 6.0)
	var palette: Array = cols(spec.get("cols"), [UI.ROOM_PROMO, UI.ROOM_TICKET, UI.SLATE])
	var offsets: Array = [Vector2(-8.0, -46.0), Vector2(4.0, -54.0), Vector2(11.0, -42.0)]
	return func(ci: CanvasItem) -> void:
		var base: Vector2 = Iso.to_screen(at)
		for k in offsets.size():
			ci.draw_line(base + Vector2(0, -tie_height), base + (offsets[k] as Vector2),
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
			Iso.fill(ci, poly, ring[1] as Color)
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

## Walkable stone inlay: projected rings and compass ticks, no raised geometry.
static func _orbital_inlay(spec: Dictionary) -> Callable:
	var at: Vector2 = v2(spec.get("at"))
	var radius: float = maxf(.25,f(spec.get("radius"),2.5))
	var fill: Color = c(spec.get("col"),Color("#344D68"))
	var line: Color = c(spec.get("line"),Color("#A9CCC7"))
	return func(ci: CanvasItem) -> void:
		var disc := PackedVector2Array()
		for n in 96:
			var a: float = TAU*n/96.0
			disc.append(Iso.to_screen(at+Vector2(cos(a),sin(a))*radius))
		Iso.fill(ci, disc,fill)
		for fraction in [1.0,.93,.62]:
			var ring := PackedVector2Array()
			for n in 97:
				var a: float = TAU*n/96.0
				ring.append(Iso.to_screen(at+Vector2(cos(a),sin(a))*radius*fraction))
			ci.draw_polyline(ring,line,1.3,true)
		for n in 24:
			var a: float = TAU*n/24.0
			var direction := Vector2(cos(a),sin(a))
			var inner: float = .81 if n%6==0 else .88
			ci.draw_line(Iso.to_screen(at+direction*radius*inner),Iso.to_screen(at+direction*radius*.93),line,1.5,true)
