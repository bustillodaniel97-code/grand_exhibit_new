extends Node2D
## City — the block the museum stands in.
##
## The diorama used to be an island of floor on the app background, which read as
## a diagram rather than a place. This node draws everything OUTSIDE the museum
## footprint — lawn, kerbs, a street with moving traffic, trees, hedges, street
## furniture and the neighbouring buildings — in the SAME projection as the
## floor, so the two share one horizon and one light direction.
##
## Grid space is Iso's, extended past the 15x17 footprint:
##
##        gy < APRON_A.y   north verge  -> upper RIGHT of screen
##        gx < APRON_A.x   west verge   -> upper LEFT
##        gx > APRON_B.x   east verge   -> lower RIGHT
##        gy > APRON_B.y   the STREET   -> lower LEFT, and the way in
##
## Which corner a verge lands in is not obvious from the grid, so it is worth
## stating: the projection shears x by -gy, so +gx runs down-right and +gy runs
## down-left. The entrance is on the museum's gy = 17 face, which is the
## lower-left one, and that is why the road, the kerb and the forecourt are all
## on the south side — arrivals have to come off a street the player can see.
##
## COST. Every fill on this node goes through one triangle array rather than a
## draw_colored_polygon apiece, because polygons do not batch (see Iso.stroke):
## the whole surround — lawn, road, three buildings, thirteen trees, the hedges
## and the street furniture — lands in ONE canvas command, the markings in a
## couple more, and the traffic in one again. Static scenery is drawn once and
## never redrawn; only the four cars have a per-frame item. MEASURED against
## tools/perf.gd, the entire block costs about 25 draw calls on a ~1050-call
## frame, most of that the canopy prop rather than the surround itself.

const UI := preload("res://scripts/ui/ui_kit.gd")
const Iso := preload("res://scenes/venue/floor/iso.gd")

## Ground draws the museum shell at canvas y = 0 and relies on Y-sort putting it
## behind every prop. The surround has to sit behind GROUND, and a tie at y = 0
## would be decided by child order alone. Lifting this node a pixel and cancelling
## it with a draw transform makes the ordering a fact instead of an assumption.
const Y_LIFT := 1.0

## The world outside the museum's plinth sits this far below its floor plane, so
## the apron's south and east edges can show a skirt and read as a raised slab.
const DROP := 13.0

# --- Layout, in grid space ----------------------------------------------------
##
## The bands are packed tight on purpose. Screen area outside the footprint is
## scarce — the diamond is 960px wide against a 720px canvas — and every tile
## given to the pavement is a tile of road the player never sees. An earlier
## pass ran the kerb out at gy = 19.7 and the whole street ended up as a 40px
## sliver in the bottom corner under a 120px band of empty grey.
const APRON_A := Vector2(-1.1, -1.1)   # paved apron, NW corner
const APRON_B := Vector2(16.3, 18.05)  # paved apron, SE corner
const SIDEWALK_B := 18.72              # pavement runs from APRON_B.y to here
const KERB_B := 18.92
const ROAD_B := 21.25
const LANE_OUT := 19.52                # traffic running +gx
const LANE_IN := 20.62                 # traffic running -gx
const CENTRE_GY := 20.07

## Where an arriving visitor steps onto the forecourt. Pushed as far down the
## approach as Iso.on_canvas(g, 26) allows: at gx + gy = 32 it projects to
## y = 720 against a 760 canvas, so people walk on from the bottom of the frame
## instead of popping into existence at the door.
const STREET_G := Vector2(14.0, 18.0)
## Entrance canopy. VenueFloor hangs this on a Y-sorted prop node rather than
## drawing it here, because it stands in FRONT of the facade and this whole node
## is behind the museum.
const CANOPY_G := Vector2(12.9, 17.9)
const CANOPY_A := Vector2(12.08, 17.08)
const CANOPY_SIZE := Vector2(1.62, 0.88)

const CAR_COUNT := 4

# --- Surround styles -----------------------------------------------------------
##
## A venue theme says one thing about the world outside its walls: which STYLE
## the surround is. Everything a style controls — its palette and the grid
## positions of its scenery — lives in this table, so authoring "harbour" for the
## aquarium or "cliffside" for a mountain venue is an entry here and NOTHING
## else. In particular no caller changes: VenueFloor sets `style` from
## theme.surround and never learns what a style contains.
##
## A style's scenery entries are plain arrays because they are read once at
## build time: [gx, gy, ...] for a piece, [ax, ay, bx, by, ...] for a run.
const STYLES := {
	"parkland": {
		# Fragments at the frame edge, never whole — a complete building out
		# there competes with the one the player is running.
		"blocks": [
			[-7.0, 3.2, 2.6, 2.8, 46.0, 0],
			[0.9, -4.9, 3.2, 2.0, 50.0, 1],
			[18.2, 9.4, 2.8, 3.0, 52.0, 2],
		],
		"fences": [[-2.0, -1.8, 11.0, -1.8, 12], [-2.0, -1.8, -2.0, 7.0, 9]],
		"trees": [
			[-4.3, 0.4, 1.05], [-3.5, 3.1, 0.92], [-4.6, 5.4, 1.12], [-3.2, 7.6, 0.86],
			[1.4, -3.0, 0.98], [4.3, -2.8, 1.10], [6.9, -3.6, 0.88], [9.2, -2.9, 1.02],
			[17.6, 12.2, 1.06], [17.4, 14.4, 0.90],
		],
		"pines": [[-5.6, 2.0, 1.0], [7.9, -5.0, 1.1], [18.2, 6.6, 0.95]],
		"hedges": [[16.6, 2.0, 16.6, 16.2, 0.44], [-1.45, 9.2, -1.45, 15.2, 0.40]],
		"near_trees": [[9.2, 18.3, 0.84], [6.4, 18.3, 0.78]],
		"planters": [[11.55, 17.35], [14.15, 17.35]],
		"lamps": [[12.1, 18.36], [10.0, 18.36]],
		"bench": [7.7, 18.16],
		"bollards": [10.9, 17.84, 0.62, 3],
		"mown_stripes": true,
	},
	# The aquarium's block: open water where parkland puts lawn, so the apron
	# reads as a quay with the harbour behind it. Nothing here is a new drawing
	# routine — every piece keeps its job and changes its material. The boundary
	# fence becomes the quay railing, the neighbouring blocks become low warehouse
	# sheds, the bollards become mooring posts.
	"harbour": {
		# Colours are hex STRINGS rather than Colors because this table is a
		# const: Color("#...") is not a constant expression. palette_for parses
		# them over the derived scheme, key by key, so anything left unnamed
		# keeps its parkland value.
		"palette": {
			"lawn": "#17607A", "lawn_lit": "#1D7692", "lawn_dim": "#0E4459",
			"paving": "#7C8B96", "paving_lit": "#94A2AC", "kerb": "#57646F",
			"tree_dark": "#1B5F4A", "tree_mid": "#27795D", "tree_lit": "#369672",
			"hedge": "#2F6B57", "trunk": "#33424D",
			"neighbour": ["#2B4E6B", "#3C5A70", "#8A4F3C"],
			"runner": "#12B0C4",
		},
		# Sheds, not offices: kept low so the skyline stays flat and the museum is
		# still the only tall thing on the block.
		"blocks": [
			[-7.2, 3.0, 3.0, 3.0, 38.0, 0],
			[0.6, -5.1, 3.6, 2.2, 34.0, 1],
			[18.2, 9.0, 2.8, 3.2, 42.0, 2],
		],
		# Railings, all the way round the water edge — the one thing a quay must
		# have and a lawn does not.
		"fences": [
			[-2.0, -1.8, 11.0, -1.8, 13], [-2.0, -1.8, -2.0, 7.0, 9],
			[16.9, 1.6, 16.9, 16.4, 14],
		],
		"trees": [
			[-4.1, 1.2, 0.86], [-3.6, 6.4, 0.94], [3.2, -3.0, 0.90],
			[8.6, -3.2, 0.84], [17.7, 13.2, 0.88],
		],
		"pines": [],
		"hedges": [[15.9, 3.0, 15.9, 15.4, 0.38], [-1.45, 9.4, -1.45, 15.0, 0.36]],
		"near_trees": [[9.0, 18.3, 0.80], [6.2, 18.3, 0.74]],
		"planters": [[11.55, 17.35], [14.15, 17.35]],
		"lamps": [[12.1, 18.36], [10.0, 18.36]],
		"bench": [7.7, 18.16],
		"bollards": [10.5, 17.84, 0.58, 5],
		# Left on: the constant-gx bands that read as mowing on grass read as
		# swell catching the light on water.
		"mown_stripes": true,
	},
}

static func style_def(style_name: String) -> Dictionary:
	if STYLES.has(style_name):
		return STYLES[style_name]
	push_warning("City: unknown surround style '%s', falling back to parkland" % style_name)
	return STYLES["parkland"]

# --- Palette ------------------------------------------------------------------
## Derived from ui_kit rather than picked by eye: the surround has to recede
## behind a floor that is already high-chroma, so every colour here is a ui_kit
## hue pulled down in value. Built per style through a static factory because
## draw_canopy() is called from VenueFloor's prop painter, which has no instance
## to reach through.
static func palette_for(style_name: String) -> Dictionary:
	# Warmed off pure lilac: PANEL_SOFT has a violet cast that read as a dead
	# lavender field once the apron got large.
	var lawn: Color = UI.SAGE.darkened(0.24).lerp(UI.BRASS, 0.16)
	var paving: Color = UI.PANEL_SOFT.darkened(0.36).lerp(UI.WALL_BROWN, 0.09)
	var pal := {
		"lawn": lawn, "lawn_lit": lawn.lightened(0.07), "lawn_dim": lawn.darkened(0.18),
		"paving": paving, "paving_lit": paving.lightened(0.13),
		"kerb": paving.darkened(0.24),
		"road": UI.BG.lightened(0.13), "marking": UI.PANEL.darkened(0.10),
		"tree_dark": UI.SAGE.darkened(0.62), "tree_mid": UI.SAGE.darkened(0.46),
		"tree_lit": UI.SAGE.darkened(0.26), "hedge": UI.SAGE.darkened(0.54),
		"trunk": UI.WALL_BROWN.darkened(0.10),
		"neighbour": [UI.PLUM.darkened(0.56), UI.SLATE.darkened(0.58),
			UI.ACCENT.darkened(0.54)],
		"cars": [UI.ACCENT, UI.BRASS.darkened(0.10), UI.PANEL_SOFT, UI.SLATE],
		"shadow": Color(0.06, 0.03, 0.14, 0.22),
		# The strip of entrance carpet that runs out of the doors to the kerb. A
		# style owns it because it lands on the style's paving, not on the floor.
		"runner": UI.CARPET_RED,
	}
	if style_name != "parkland" and not STYLES.has(style_name):
		push_warning("City: no palette for style '%s', using parkland" % style_name)
		return pal
	# A style repaints the derived scheme key by key. Arrays (the neighbouring
	# blocks, the traffic) are lists of colours; everything else is one colour.
	for key in (STYLES.get(style_name, {}) as Dictionary).get("palette", {}):
		var value: Variant = (STYLES[style_name]["palette"] as Dictionary)[key]
		if value is Array:
			var list: Array = []
			for entry in value:
				list.append(Color(str(entry)))
			pal[str(key)] = list
		else:
			pal[str(key)] = Color(str(value))
	return pal

## The surround this block draws. Set by VenueFloor from theme.surround, either
## before the node enters the tree or on a prestige, when the museum moves to a
## venue whose world outside the walls is a different one. The scenery table and
## the palette are both cached, so assigning the style has to refresh them —
## a bare field left a re-themed floor drawing the previous venue's block.
var style: String = "parkland":
	set(value):
		style = value
		_pal = palette_for(style)
		_def = style_def(style)
		if not _cars.is_empty():
			var cars: Array = _pal["cars"]
			for i in _cars.size():
				_cars[i]["col"] = cars[i % cars.size()] as Color
		if is_inside_tree():
			queue_redraw()

var _pal: Dictionary = {}
var _def: Dictionary = {}
var _band := Rect2()          # visible area in canvas space; see set_visible_band
var _traffic: Node2D
var _cars: Array[Dictionary] = []

# Triangle batch, reused by both canvas items.
var _pts := PackedVector2Array()
var _cols := PackedColorArray()
var _idx := PackedInt32Array()

func _ready() -> void:
	name = "City"
	position = Vector2(0.0, -Y_LIFT)
	_pal = palette_for(style)
	_def = style_def(style)
	_build_cars()
	_traffic = Node2D.new()
	_traffic.name = "Traffic"
	_traffic.position = Vector2(0.0, Y_LIFT)
	add_child(_traffic)
	_traffic.draw.connect(_draw_traffic)

# --- Traffic ------------------------------------------------------------------

func _build_cars() -> void:
	_cars.clear()
	# Two lanes, opposed, staggered so a car is nearly always inside the visible
	# wedge of road. Speeds are deliberately under 1.3 tiles/s: at this scale
	# anything faster reads as a glitch rather than as traffic.
	var spec := [
		{"gy": LANE_OUT, "gx": 7.4, "dir": 1.0, "speed": 1.15},
		{"gy": LANE_OUT, "gx": 11.9, "dir": 1.0, "speed": 1.02},
		{"gy": LANE_IN, "gx": 12.6, "dir": -1.0, "speed": 0.94},
		{"gy": LANE_IN, "gx": 9.1, "dir": -1.0, "speed": 1.08},
	]
	for i in CAR_COUNT:
		var s: Dictionary = spec[i]
		_cars.append({
			"gx": float(s["gx"]), "gy": float(s["gy"]),
			"dir": float(s["dir"]), "speed": float(s["speed"]),
			"col": _pal["cars"][i % _pal["cars"].size()] as Color,
		})

## Visible gx span of a lane, plus a car length of run-off at each end. Wrapping
## outside this is what stops cars popping into existence mid-street.
static func lane_span(gy: float) -> Vector2:
	return Vector2(gy - 14.4, 35.4 - gy)

## Advance the traffic. VenueFloor drives this from its own _process so the cars
## honour time_scale and stop when the sim stops.
func advance(dt: float) -> void:
	if _cars.is_empty():
		return
	for car in _cars:
		var span: Vector2 = lane_span(float(car["gy"]))
		var gx: float = float(car["gx"]) + float(car["dir"]) * float(car["speed"]) * dt
		if gx > span.y:
			gx = span.x
		elif gx < span.x:
			gx = span.y
		car["gx"] = gx
	_traffic.queue_redraw()

## Test hook: [gx, gy] of every car, in grid space.
func car_positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for car in _cars:
		out.append(Vector2(float(car["gx"]), float(car["gy"])))
	return out

func _draw_traffic() -> void:
	for car in _cars:
		var col: Color = car["col"]
		var g := Vector2(float(car["gx"]) - 0.62, float(car["gy"]) - 0.27)
		var mid: Vector2 = _p(g + Vector2(0.62, 0.27), DROP + 3.0)
		_disc(mid + Vector2(0.0, 2.0), 18.0, 7.0, _pal["shadow"])
		_prism(g, Vector2(1.24, 0.54), 12.0, col, DROP + 3.0)
		# Greenhouse: a slab SITTING ON the body, not a second prism off the road.
		# Drawn as a prism it grew its own full-height side faces and every car
		# read as a truck cab bolted to a coloured pallet.
		_slab(g + Vector2(0.38, 0.12), Vector2(0.52, 0.30), 12.0, 9.0,
			col.darkened(0.46), DROP + 3.0)
		# Headlamps on the leading face, so a car reads as pointing somewhere.
		var nose: float = 1.17 if float(car["dir"]) > 0.0 else 0.07
		for dy in [0.11, 0.43]:
			var lamp: Vector2 = _p(g + Vector2(nose, dy), DROP + 3.0) + Vector2(0.0, -7.0)
			_fill(PackedVector2Array([
				lamp + Vector2(-2.4, -2.0), lamp + Vector2(2.4, -2.0),
				lamp + Vector2(2.4, 2.0), lamp + Vector2(-2.4, 2.0)]), UI.BRASS)
	_flush(_traffic)

# --- Static surround ----------------------------------------------------------

func _draw() -> void:
	draw_set_transform(Vector2(0.0, Y_LIFT))
	_draw_ground_plane()
	_draw_street()
	_draw_far_scenery()
	_draw_apron()
	_draw_near_scenery()
	_flush(self)
	_draw_lines()
	_draw_edge_fade()

## Lawn, everywhere. Filling the whole canvas rather than a polygon around the
## museum is what removes the "floating island" read; the top and bottom edges
## are dissolved back into the app background by _draw_edge_fade().
func _draw_ground_plane() -> void:
	# Fill the VISIBLE band, not the nominal 720x760 canvas. VenueFloor letterboxes
	# the canvas inside a taller Control (_fit_canvas fits by min), so there is bare
	# app background above and below it. The lawn used to stop at the canvas edge
	# while the mown stripes were authored out to gy = -9, which projects past that
	# edge — so the stripes painted bright green diagonals directly onto the indigo
	# shell with no grass under them. Covering the real band fixes both the missing
	# ground and the stripes-on-nothing.
	var vb: Rect2 = _visible_band()
	_fill(PackedVector2Array([
		vb.position, Vector2(vb.end.x, vb.position.y), vb.end, Vector2(vb.position.x, vb.end.y)]),
		_pal["lawn"])
	# Mown stripes on the two lawns that carry real screen area. Constant-gx
	# bands so they run with the projection instead of across it. Kept to a 7%
	# lift — at 10% they read as ramps cut into the grass, not as mowing.
	if not bool(_def.get("mown_stripes", false)):
		return
	for i in 5:
		var gx: float = -8.0 + float(i) * 1.9
		_patch(Vector2(gx, -9.0), Vector2(0.95, 8.4), _pal["lawn_lit"], DROP)
	for i in 4:
		var gy: float = -8.4 + float(i) * 2.1
		_patch(Vector2(16.4, gy), Vector2(7.0, 1.0), _pal["lawn_lit"], DROP)

## Visible band in this node's own space. Defaults to a generous overscan around
## the nominal canvas so the fill is still correct before VenueFloor reports the
## real one (and in tests, which never resize).
func _visible_band() -> Rect2:
	if _band.size.x > 1.0 and _band.size.y > 1.0:
		return _band.grow(24.0)
	return Rect2(-120.0, -120.0, Iso.VIEW.x + 240.0, Iso.VIEW.y + 240.0)


## Called by VenueFloor._fit_canvas with the Control's rect expressed in canvas
## coordinates, so the surround always reaches the actual screen edges.
func set_visible_band(band: Rect2) -> void:
	if band.is_equal_approx(_band):
		return
	_band = band
	queue_redraw()


func _draw_street() -> void:
	var gx0: float = -4.0
	var span: float = 24.0
	_patch(Vector2(gx0, APRON_B.y), Vector2(span, SIDEWALK_B - APRON_B.y), _pal["paving"], DROP)
	_patch(Vector2(gx0, SIDEWALK_B), Vector2(span, KERB_B - SIDEWALK_B), _pal["kerb"], DROP)
	_skirt(Vector2(gx0, KERB_B), Vector2(gx0 + span, KERB_B), 5.0, _pal["kerb"].darkened(0.30), DROP)
	_patch(Vector2(gx0, KERB_B), Vector2(span, ROAD_B - KERB_B), _pal["road"], DROP + 5.0)
	# Far kerb and verge, mostly off the bottom edge but it closes the road.
	_patch(Vector2(gx0, ROAD_B), Vector2(span, 0.3), _pal["kerb"], DROP)
	_patch(Vector2(gx0, ROAD_B + 0.3), Vector2(span, 3.0), _pal["lawn_dim"], DROP)
	# Crossing, aimed at the forecourt so the approach has somewhere to come from.
	for i in 5:
		var gx: float = 10.4 + float(i) * 0.46
		_patch(Vector2(gx, KERB_B + 0.16), Vector2(0.26, ROAD_B - KERB_B - 0.32),
			_pal["marking"].darkened(0.06), DROP + 5.0)

## Everything on the far side of the building: neighbouring blocks, the boundary
## fence, the north and west treelines. Drawn back to front by depth.
func _draw_far_scenery() -> void:
	var hues: Array = _pal["neighbour"]
	for b in _def.get("blocks", []):
		_block(Vector2(float(b[0]), float(b[1])), Vector2(float(b[2]), float(b[3])),
			float(b[4]), hues[int(b[5]) % hues.size()])
	for f in _def.get("fences", []):
		_fence(Vector2(float(f[0]), float(f[1])), Vector2(float(f[2]), float(f[3])), int(f[4]))
	for t in _def.get("trees", []):
		_tree(Vector2(float(t[0]), float(t[1])), float(t[2]))
	for t in _def.get("pines", []):
		_pine(Vector2(float(t[0]), float(t[1])), float(t[2]))
	for h in _def.get("hedges", []):
		_hedge(Vector2(float(h[0]), float(h[1])), Vector2(float(h[2]), float(h[3])),
			float(h[4]))

## The paved plinth the museum stands on, plus its shadow and its skirt.
func _draw_apron() -> void:
	var size: Vector2 = APRON_B - APRON_A
	_patch(APRON_A + Vector2(0.3, 0.4), size, _pal["shadow"], DROP)
	_skirt(Vector2(APRON_A.x, APRON_B.y), APRON_B, DROP + 2.0, _pal["paving"].darkened(0.42), 0.0)
	_skirt(APRON_B, Vector2(APRON_B.x, APRON_A.y), DROP + 2.0, _pal["paving"].darkened(0.30), 0.0)
	_patch(APRON_A, size, _pal["paving"])
	# Paving joints. A slab this size with no grain reads as a hole in the world,
	# and thin quads inside the batch cost nothing where strokes would not batch
	# with the fills around them.
	for i in 13:
		var gy: float = APRON_A.y + float(i) * 1.55
		if gy > APRON_B.y:
			break
		_patch(Vector2(APRON_A.x, gy), Vector2(size.x, 0.045), _pal["paving"].darkened(0.09))
	for i in 12:
		var gx: float = APRON_A.x + float(i) * 1.55
		if gx > APRON_B.x:
			break
		_patch(Vector2(gx, APRON_A.y), Vector2(0.045, size.y), _pal["paving"].darkened(0.09))
	# Darker edging strip and its highlight, along the two faces that show. This
	# is what makes the apron read as a step up from the pavement.
	_patch(Vector2(APRON_A.x, APRON_B.y - 0.34), Vector2(size.x, 0.34), _pal["kerb"])
	_patch(Vector2(APRON_B.x - 0.34, APRON_A.y), Vector2(0.34, size.y), _pal["kerb"])
	_patch(Vector2(APRON_A.x, APRON_B.y - 0.07), Vector2(size.x, 0.07), _pal["paving_lit"])
	_patch(Vector2(APRON_B.x - 0.07, APRON_A.y), Vector2(0.07, size.y), _pal["paving_lit"])
	# Forecourt: the interior red runner continues out of the doors to the kerb,
	# which is the whole reason an arrival reads as walking IN off the street.
	var runner: Color = _pal["runner"]
	_patch(Vector2(12.1, 17.35), Vector2(1.6, APRON_B.y - 17.35), runner.darkened(0.06))
	_patch(Vector2(12.25, 17.35), Vector2(1.3, APRON_B.y - 17.35), runner.lightened(0.10))

## Anything between the facade and the kerb. Drawn after the apron so it sits on
## it, and kept under ~46px tall so it cannot reach up into the museum silhouette.
func _draw_near_scenery() -> void:
	for p in _def.get("planters", []):
		_planter(Vector2(float(p[0]), float(p[1])))
	for t in _def.get("near_trees", []):
		_tree(Vector2(float(t[0]), float(t[1])), float(t[2]), DROP)
	for l in _def.get("lamps", []):
		_lamp(Vector2(float(l[0]), float(l[1])))
	# Bench and litter bin on the pavement, facing the crossing.
	var bench: Array = _def.get("bench", [])
	if bench.size() >= 2:
		var bx: float = float(bench[0])
		var by: float = float(bench[1])
		_prism(Vector2(bx, by), Vector2(1.1, 0.22), 9.0, _pal["trunk"].lightened(0.16), DROP)
		_prism(Vector2(bx, by + 0.08), Vector2(1.1, 0.06), 17.0,
			_pal["trunk"].lightened(0.06), DROP)
		_prism(Vector2(bx - 0.45, by - 0.02), Vector2(0.16, 0.16), 15.0,
			_pal["kerb"].darkened(0.20), DROP)
	# Bollards guarding the forecourt lip.
	var posts: Array = _def.get("bollards", [])
	if posts.size() >= 4:
		for i in int(posts[3]):
			_prism(Vector2(float(posts[0]) + float(i) * float(posts[2]), float(posts[1])),
				Vector2(0.12, 0.12), 9.0, _pal["kerb"].darkened(0.30))

## Outlines and road markings. Lines batch where polygons do not, so every stroke
## on the surround is deferred to here and lands in one draw call.
func _draw_lines() -> void:
	var mark := Color(_pal["marking"].r, _pal["marking"].g, _pal["marking"].b, 0.85)
	for i in 9:
		var gx: float = 4.4 + float(i) * 1.35
		Iso.stroke(self, PackedVector2Array([
			_p(Vector2(gx, CENTRE_GY), DROP + 5.0),
			_p(Vector2(gx + 0.72, CENTRE_GY), DROP + 5.0)]), mark, 2.6)
	for gy in [KERB_B + 0.16, ROAD_B - 0.16]:
		Iso.stroke(self, PackedVector2Array([
			_p(Vector2(2.0, gy), DROP + 5.0), _p(Vector2(17.0, gy), DROP + 5.0)]),
			Color(_pal["marking"].r, _pal["marking"].g, _pal["marking"].b, 0.45), 1.8)

## The floor Control is a band inside a taller screen, so a hard horizontal edge
## where the lawn stops reads as a pasted-in picture. Ramp it back to the app
## background instead. Rects batch, so the whole ramp is one draw call.
func _draw_edge_fade() -> void:
	# Ramp from the REAL top and bottom of the visible band. Ramping the nominal
	# canvas edge instead left a hard bright line partway down the screen, because
	# the canvas is letterboxed and its edge is not where the picture ends.
	var vb: Rect2 = _visible_band()
	var steps: int = 12
	for i in steps:
		var t: float = float(i) / float(steps)
		var a: float = (1.0 - t) * (1.0 - t)
		draw_rect(Rect2(vb.position.x, vb.position.y + float(i) * 6.0, vb.size.x, 6.5),
			Color(UI.BG.r, UI.BG.g, UI.BG.b, a))
		# The bottom ramp is half the height of the top one: it lands on the road,
		# and a deep wash there took the traffic with it.
		draw_rect(Rect2(vb.position.x, vb.end.y - float(i + 1) * 3.0, vb.size.x, 3.5),
			Color(UI.BG.r, UI.BG.g, UI.BG.b, a * 0.9))

# --- Entrance canopy (drawn by VenueFloor, on a Y-sorted prop) -----------------

## The awning over the doors. It stands in front of the facade, so it cannot live
## on this node — VenueFloor hands it to _add_prop() at CANOPY_G and Y-sort puts
## it where it belongs. Static so it needs no City instance.
static func draw_canopy(ci: CanvasItem, style_name: String = "parkland") -> void:
	var pal: Dictionary = palette_for(style_name)
	var post_h := 36.0
	var back := CANOPY_A + Vector2(0.0, CANOPY_SIZE.y)
	Iso.rug(ci, CANOPY_A + Vector2(0.14, 0.18), CANOPY_SIZE, Color(0.06, 0.03, 0.14, 0.15))
	for gx in [CANOPY_A.x + 0.04, CANOPY_A.x + CANOPY_SIZE.x - 0.14]:
		Iso.box(ci, Vector2(gx, back.y - 0.1), Vector2(0.1, 0.1), post_h,
			(pal["paving"] as Color).darkened(0.26), Color(0, 0, 0, 0.24))
	var q := Iso.quad(CANOPY_A, CANOPY_SIZE)
	var up := Vector2(0.0, -post_h - 5.0)
	var lo := Vector2(0.0, -post_h)
	# Warmed off pure white. At UI.PANEL the awning was the brightest thing on the
	# screen and pulled the eye off the doors it is supposed to frame.
	var cloth: Color = UI.PANEL.lerp(UI.ROOM_TICKET, 0.14)
	ci.draw_colored_polygon(PackedVector2Array([q[3] + up, q[2] + up, q[2] + lo, q[3] + lo]),
		cloth.darkened(0.38))
	ci.draw_colored_polygon(PackedVector2Array([q[2] + up, q[1] + up, q[1] + lo, q[2] + lo]),
		cloth.darkened(0.22))
	ci.draw_colored_polygon(PackedVector2Array([q[0] + up, q[1] + up, q[2] + up, q[3] + up]),
		cloth)
	# Scalloped valance down BOTH lips. One run read as a folded card; two give the
	# awning a hem and tell the eye which way it hangs. Each run is ONE saw-tooth
	# polygon rather than a triangle per scallop: polygons do not batch, and ten
	# of them here would have cost more draw calls than the entire surround.
	for edge in [[q[3] + lo, q[2] + lo, 6], [q[2] + lo, q[1] + lo, 4]]:
		var a: Vector2 = edge[0]
		var b: Vector2 = edge[1]
		var n: int = edge[2]
		# One polygon per lip, but with a 2px solid band along the top that the
		# teeth hang from. The previous shape ran tooth-tip / top-edge / tooth-tip
		# with the polygon's implicit closing edge (b back to a) lying exactly
		# along the top line — which put every interior top vertex ON that edge,
		# and a vertex incident to another edge is degenerate to the triangulator.
		# That was the "Invalid polygon data, triangulation failed" pair spamming
		# every boot: one per lip, twice per floor build. The band keeps the tooth
		# valleys 2px clear of the closing edge and reads as the hem's tape.
		var hem := PackedVector2Array()
		hem.append(a)
		hem.append(b)
		for i in range(n - 1, -1, -1):
			hem.append(a.lerp(b, (float(i) + 0.5) / float(n)) + Vector2(0.0, 8.0))
			hem.append(a.lerp(b, float(i) / float(n)) + Vector2(0.0, 2.0))
		ci.draw_colored_polygon(hem, UI.ROOM_TICKET.darkened(0.10))
	Iso.stroke(ci, PackedVector2Array([q[3] + up, q[0] + up, q[1] + up]),
		Color(0, 0, 0, 0.18), 1.4)

# --- Scenery pieces -----------------------------------------------------------

func _tree(g: Vector2, s: float, drop: float = DROP) -> void:
	var base: Vector2 = _p(g, drop)
	_disc(base + Vector2(2.0, 1.0), 16.0 * s, 7.0 * s, _pal["shadow"])
	_prism(g - Vector2(0.07, 0.07) * s, Vector2(0.14, 0.14) * s, 13.0 * s, _pal["trunk"], drop)
	var r: float = 17.0 * s
	_disc(base + Vector2(0.0, -20.0 * s), r, r * 0.92, _pal["tree_dark"])
	_disc(base + Vector2(-4.0 * s, -30.0 * s), r * 0.86, r * 0.80, _pal["tree_mid"])
	_disc(base + Vector2(4.5 * s, -34.0 * s), r * 0.62, r * 0.58, _pal["tree_lit"])

func _pine(g: Vector2, s: float, drop: float = DROP) -> void:
	var base: Vector2 = _p(g, drop)
	_disc(base + Vector2(2.0, 1.0), 13.0 * s, 6.0 * s, _pal["shadow"])
	_prism(g - Vector2(0.06, 0.06) * s, Vector2(0.12, 0.12) * s, 10.0 * s, _pal["trunk"], drop)
	for i in 3:
		var w: float = (16.0 - float(i) * 4.2) * s
		var y: float = base.y - (10.0 + float(i) * 13.0) * s
		var tip: float = y - 19.0 * s
		var col: Color = _pal["tree_dark"] if i == 0 else (_pal["tree_mid"] if i == 1 else _pal["tree_lit"])
		_fill(PackedVector2Array([
			Vector2(base.x, tip), Vector2(base.x + w, y), Vector2(base.x - w, y)]), col)

func _hedge(a: Vector2, b: Vector2, w: float) -> void:
	var d: Vector2 = b - a
	var len_g: float = d.length()
	var n: int = maxi(1, int(round(len_g / 1.1)))
	var step: Vector2 = d / float(n)
	for i in n:
		var g: Vector2 = a + step * float(i)
		var size := Vector2(w, step.y * 0.94) if absf(d.x) < absf(d.y) \
			else Vector2(step.x * 0.94, w)
		_prism(g, size, 17.0, _pal["hedge"], DROP)
		_prism(g + Vector2(0.03, 0.03), size - Vector2(0.06, 0.06), 19.0,
			_pal["hedge"].lightened(0.14), DROP)

func _fence(a: Vector2, b: Vector2, posts: int) -> void:
	var rail_h := 15.0
	for i in posts + 1:
		var g: Vector2 = a.lerp(b, float(i) / float(posts))
		_prism(g, Vector2(0.09, 0.09), 20.0, _pal["trunk"].darkened(0.20), DROP)
	for h in [8.0, rail_h]:
		_skirt(a, b, 2.4, _pal["trunk"].darkened(0.10), DROP - h)

func _planter(g: Vector2) -> void:
	# Cast stone, not the kerb grey it started as — at that value the tub read as
	# a dropped block rather than as planting.
	_prism(g, Vector2(0.62, 0.62), 15.0, _pal["paving"].lightened(0.08))
	var top: Vector2 = _p(g + Vector2(0.31, 0.31)) + Vector2(0.0, -15.0)
	_disc(top, 17.0, 9.0, _pal["hedge"])
	_disc(top + Vector2(-3.5, -8.0), 13.0, 10.0, _pal["hedge"].lightened(0.18))
	_disc(top + Vector2(4.5, -5.0), 9.0, 8.0, UI.ROOM_PROMO.darkened(0.16))

func _lamp(g: Vector2) -> void:
	var base: Vector2 = _p(g, DROP)
	_disc(base + Vector2(2.0, 1.0), 9.0, 4.0, _pal["shadow"])
	_prism(g, Vector2(0.1, 0.1), 42.0, _pal["kerb"].darkened(0.34), DROP)
	var head: Vector2 = base + Vector2(0.0, -44.0)
	_fill(PackedVector2Array([
		head + Vector2(-6.0, 0.0), head + Vector2(6.0, 0.0),
		head + Vector2(4.0, -7.0), head + Vector2(-4.0, -7.0)]), UI.BRASS.darkened(0.14))

## Neighbouring block: a plinth of its own, walls, and a flat roof, so it reads
## as a building rather than a coloured slab.
func _block(g: Vector2, size: Vector2, h: float, col: Color) -> void:
	_patch(g + Vector2(-0.45, -0.45), size + Vector2(0.9, 0.9), _pal["paving"].darkened(0.18), DROP)
	_patch(g + Vector2(0.22, 0.32), size, _pal["shadow"], DROP)
	_prism(g, size, h, col, DROP)
	# Parapet, so the roof has a lip instead of ending in a flat plane.
	_slab(g + Vector2(-0.12, -0.12), size + Vector2(0.24, 0.24), h, 5.0,
		col.lightened(0.18), DROP)
	# Windows as individual panes on the two lit faces. Banding the full width
	# instead read as painted stripes, which is what the first pass shipped.
	var glass: Color = UI.SLATE.darkened(0.34)
	var rows: int = maxi(1, int((h - 14.0) / 15.0))
	for r in rows:
		var y: float = 12.0 + float(r) * 15.0
		if y + 9.0 > h - 5.0:
			break
		_panes(g + Vector2(0.0, size.y), g + size, y, 9.0, glass, maxi(2, int(size.x / 0.8)))
		_panes(g + size, g + Vector2(size.x, 0.0), y, 9.0, glass.lightened(0.10),
			maxi(2, int(size.y / 0.8)))

## A row of window panes along one grid edge, at height `y`.
func _panes(a: Vector2, b: Vector2, y: float, hgt: float, col: Color, n: int) -> void:
	for i in n:
		_skirt(a.lerp(b, (float(i) + 0.26) / float(n)),
			a.lerp(b, (float(i) + 0.74) / float(n)), hgt, col, DROP - y)

# --- Batched primitives -------------------------------------------------------

## Project a grid point, dropped to the outside-world ground plane.
func _p(g: Vector2, drop: float = 0.0) -> Vector2:
	return Iso.to_screen(g) + Vector2(0.0, drop)

## Convex polygon into the batch, fanned from its first vertex.
func _fill(poly: PackedVector2Array, col: Color) -> void:
	var base: int = _pts.size()
	for pt in poly:
		_pts.append(pt)
		_cols.append(col)
	for i in range(1, poly.size() - 1):
		_idx.append(base)
		_idx.append(base + i)
		_idx.append(base + i + 1)

## Flat iso patch on the ground plane.
func _patch(g: Vector2, size: Vector2, col: Color, drop: float = 0.0) -> void:
	_fill(PackedVector2Array([
		_p(g, drop), _p(g + Vector2(size.x, 0.0), drop),
		_p(g + size, drop), _p(g + Vector2(0.0, size.y), drop)]), col)

## Vertical face hanging below the grid segment a->b. Kerbs, plinth skirts and
## the window bands on the neighbouring blocks are all this one shape.
func _skirt(a: Vector2, b: Vector2, depth: float, col: Color, drop: float = 0.0) -> void:
	var pa: Vector2 = _p(a, drop)
	var pb: Vector2 = _p(b, drop)
	var down := Vector2(0.0, depth)
	_fill(PackedVector2Array([pa, pb, pb + down, pa + down]), col)

## Extruded box — the same three faces Iso.box draws, routed into the batch.
func _prism(g: Vector2, size: Vector2, h: float, col: Color, drop: float = 0.0) -> void:
	var back: Vector2 = _p(g, drop)
	var right: Vector2 = _p(g + Vector2(size.x, 0.0), drop)
	var front: Vector2 = _p(g + size, drop)
	var left: Vector2 = _p(g + Vector2(0.0, size.y), drop)
	var up := Vector2(0.0, -h)
	_fill(PackedVector2Array([left, front, front + up, left + up]), col.darkened(0.30))
	_fill(PackedVector2Array([front, right, right + up, front + up]), col.darkened(0.14))
	_fill(PackedVector2Array([back + up, right + up, front + up, left + up]), col)

## Floating slab — a box lifted clear of the ground, for roofs and parapets.
func _slab(g: Vector2, size: Vector2, h: float, thick: float, col: Color,
		drop: float = 0.0) -> void:
	var q: PackedVector2Array = Iso.quad(g, size)
	var off := Vector2(0.0, drop)
	var up := Vector2(0.0, -h - thick)
	var lo := Vector2(0.0, -h)
	_fill(PackedVector2Array([
		q[3] + off + up, q[2] + off + up, q[2] + off + lo, q[3] + off + lo]),
		col.darkened(0.30))
	_fill(PackedVector2Array([
		q[2] + off + up, q[1] + off + up, q[1] + off + lo, q[2] + off + lo]),
		col.darkened(0.14))
	_fill(PackedVector2Array([
		q[0] + off + up, q[1] + off + up, q[2] + off + up, q[3] + off + up]), col)

## Screen-space ellipse as a 12-gon. Tree canopies read as round blobs in the
## reference, not as iso ellipses, so these are deliberately NOT projected.
func _disc(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var poly := PackedVector2Array()
	for i in 12:
		var an: float = TAU * float(i) / 12.0
		poly.append(c + Vector2(cos(an) * rx, sin(an) * ry))
	_fill(poly, col)

func _flush(ci: CanvasItem) -> void:
	if _idx.is_empty():
		return
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), _idx, _pts, _cols)
	_pts.clear()
	_cols.clear()
	_idx.clear()
