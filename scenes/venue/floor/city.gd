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
## Static architecture and streets share the existing triangle batch. The main
## street keeps four traffic actors; district traffic, moored boats and bounded
## sidewalk walkers are separate live elements. Target-device cost remains to
## be profiled; old draw-call measurements no longer describe this richer scene.

const Routes := preload("res://scenes/venue/floor/traffic_routes.gd")
const Vehicles := preload("res://scenes/venue/floor/vehicle_sprites.gd")
const District := preload("res://scenes/venue/floor/city_district.gd")
var district = District.new(self)
var transit = preload("res://scenes/venue/floor/city_transit.gd").new(self)
var venue_id: String = "":
	set(value):
		venue_id=value
		district.select(value)
		for i in _cars.size():
			Vehicles.assign(_cars[i],value,i)
			Routes.start(_cars[i],Routes.main_route(self,bool(_cars[i].forward)),true)
		if not _cars.is_empty():transit.configure()
		queue_redraw()

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
## The building footprint every position in this file was authored against — the
## constants below and the whole STYLES table alike. A venue whose plan is a
## different size or shape gets remapped onto it by _g(), so a surround style
## stays ONE fixed table instead of needing a variant per venue.
const NOMINAL := Rect2(0.0, 0.0, 15.0, 17.0)

const APRON_A := Vector2(-1.1, -1.1)   # paved apron, NW corner
const APRON_B := Vector2(16.3, 18.05)  # paved apron, SE corner
const SIDEWALK_B := 18.72              # pavement runs from APRON_B.y to here
const KERB_B := 18.92
const ROAD_B := 21.25
const LANE_OUT := 19.52                # traffic running +gx
const LANE_IN := 20.62                 # traffic running -gx
const CENTRE_GY := 20.07
const CROSS_GX := 11.45
const CROSS_MIN_GX := 10.22
const CROSS_MAX_GX := 12.72
const CROSS_NEAR := Vector2(CROSS_GX, 18.55)
const CROSS_FAR := Vector2(CROSS_GX, 21.48)
const WALK_LEFT := Vector2(7.3, 21.62)
const WALK_RIGHT := Vector2(14.8, 21.62)
const NEAR_WALK_LEFT := Vector2(4.75, 18.42)
const NEAR_WALK_RIGHT := Vector2(15.70, 18.42)
const TRAFFIC_PHASE_S := 6.5
const WALK_PHASE_S := 2.2

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
	"worlds_campus": {
		"palette": {
			"lawn": "#40595A", "lawn_lit": "#50696A", "lawn_dim": "#33494D",
			"paving": "#7D8A8F", "paving_lit": "#9BA5A4", "kerb": "#58676E",
			"road": "#344250", "marking": "#B7B9B0",
			"tree_dark": "#294443", "tree_mid": "#41605A", "tree_lit": "#638170",
			"hedge": "#3C5A50", "trunk": "#4D5051",
			"neighbour": ["#536875", "#71858C", "#657574"], "runner": "#786C8B",
		},
		"blocks": [[-7.0,3.2,3.2,2.0,36.0,0],[1.1,-5.0,4.0,1.8,32.0,1],[18.6,9.6,2.2,3.2,37.0,2]],
		"fences": [[-2.0,-1.8,11.0,-1.8,12],[-2.0,-1.8,-2.0,7.0,9]],
		"trees": [[-4.3,.4,1.05],[-4.6,5.4,.95],[1.4,-3.0,.9],[6.9,-3.4,.9],[17.8,12.2,.9]],
		"pines": [],
		"hedges": [[16.6,2.0,16.6,16.2,.44],[-1.45,9.2,-1.45,15.2,.40]],
		"near_trees": [[9.2,18.3,.84],[6.4,18.3,.78]],
		"lamps": [[12.1,18.36],[10.0,18.36]], "bench": [7.7,18.16],
		"bollards": [10.9,17.84,.62,3], "mown_stripes": false,
	},
	"palace_gardens": {
		"palette": {
			"lawn": "#89967B", "lawn_lit": "#9AA78A", "lawn_dim": "#718268",
			"paving": "#B5AC96", "paving_lit": "#CCC0A7", "kerb": "#8E8C78",
			"tree_dark": "#465A40", "tree_mid": "#718365", "tree_lit": "#A1AF80",
			"hedge": "#5F7653", "trunk": "#766252",
			"neighbour": ["#A78E78", "#B5AA90", "#8D7A75"], "runner": "#965A65",
		},
		"blocks": [[-7.0,3.2,2.8,2.2,32.0,0],[1.1,-5.2,4.2,1.8,30.0,1],[18.6,9.4,2.4,3.0,31.0,2]],
		"fences": [[-2.0,-1.8,11.0,-1.8,12],[-2.0,-1.8,-2.0,7.0,9]],
		"trees": [[-4.3,.4,.95],[-4.3,5.4,.95],[1.4,-3.0,.95],[6.9,-3.0,.95],[17.8,12.2,.95],[17.8,15.0,.95]],
		"pines": [],
		"hedges": [[16.6,2.0,16.6,16.2,.50],[-1.45,9.2,-1.45,15.2,.50]],
		"near_trees": [[9.2,18.3,.8],[6.4,18.3,.8]],
		"lamps": [[12.1,18.36],[10.0,18.36]], "bench": [7.7,18.16],
		"bollards": [10.9,17.84,.62,3], "mown_stripes": false,
	},
	"clock_district": {
		"palette": {
			"lawn": "#68776D", "lawn_lit": "#738277", "lawn_dim": "#56665D",
			"paving": "#999D91", "paving_lit": "#AEB0A2", "kerb": "#66736D",
			"tree_dark": "#354E43", "tree_mid": "#4E6A55", "tree_lit": "#7B8D68",
			"hedge": "#4A6453", "trunk": "#605849",
			"neighbour": ["#6F786E", "#516572", "#857765"], "runner": "#937654",
		},
		"blocks": [[-7.2,3.0,2.4,3.4,35.0,0],[1.2,-5.2,3.6,1.9,38.0,1],[18.5,10.0,2.3,3.8,36.0,2]],
		"fences": [[-2.0,-1.8,11.0,-1.8,12],[-2.0,-1.8,-2.0,7.0,9]],
		"trees": [[-4.3,.4,1.05],[-4.6,5.4,.90],[1.4,-3.0,.95],[6.9,-3.6,.9],[17.6,12.2,1.0]],
		"pines": [],
		"hedges": [[16.6,2.0,16.6,16.2,.44],[-1.45,9.2,-1.45,15.2,.40]],
		"near_trees": [[9.2,18.3,.84],[6.4,18.3,.78]],
		"lamps": [[12.1,18.36],[10.0,18.36]], "bench": [7.7,18.16],
		"bollards": [10.9,17.84,.62,3], "mown_stripes": false,
	},
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
		"lamps": [[12.1, 18.36], [10.0, 18.36]],
		"bench": [7.7, 18.16],
		"bollards": [10.5, 17.84, 0.58, 5],
		# Water uses thin curved reflections, authored in _draw_ground_plane.
		"mown_stripes": false,
	},
	# Sunspire's block: sand instead of lawn, adobe instead of offices, date
	# palms instead of broadleaves. No conifers — a pine on a dune is the one
	# thing that would give the whole surround away.
	"dunes": {
		"palette": {
			"lawn": "#D9AE6A", "lawn_lit": "#E6C185", "lawn_dim": "#B88C4C",
			"paving": "#C9BFA6", "paving_lit": "#DFD6BF", "kerb": "#9B907A",
			"tree_dark": "#3E6B3A", "tree_mid": "#4F8547", "tree_lit": "#6AA75E",
			"hedge": "#8C7C4E", "trunk": "#7A5330",
			"neighbour": ["#B4784A", "#9A5F3E", "#C99763"],
			"runner": "#E8622F",
		},
		# Flat-roofed and low: a desert skyline is horizontal, and a tall
		# neighbour here read as an office block someone had painted beige.
		"blocks": [
			[-7.0, 3.2, 3.2, 3.0, 34.0, 0],
			[0.9, -4.9, 3.6, 2.2, 30.0, 1],
			[18.2, 9.4, 3.0, 3.2, 36.0, 2],
		],
		"fences": [[-2.0, -1.8, 11.0, -1.8, 10], [-2.0, -1.8, -2.0, 7.0, 8]],
		"trees": [
			[-4.3, 0.8, 0.94], [-3.8, 5.0, 1.02], [-3.2, 7.6, 0.86],
			[2.2, -3.0, 0.98], [6.9, -3.6, 0.90], [17.6, 12.2, 0.96],
		],
		"pines": [],
		"hedges": [[16.6, 2.4, 16.6, 15.8, 0.40], [-1.45, 9.4, -1.45, 15.0, 0.36]],
		"near_trees": [[9.2, 18.3, 0.86], [6.4, 18.3, 0.76]],
		"lamps": [[12.1, 18.36], [10.0, 18.36]],
		"bench": [7.7, 18.16],
		"bollards": [10.9, 17.84, 0.62, 3],
		# On: constant-gx bands on sand read as wind ripple, which is the one
		# texture that stops a desert apron looking like a blank beige field.
		"mown_stripes": true,
	},
	# Cloudrest's block: the citadel stands above the treeline, so the ground is
	# cold meadow going to rock, the neighbours are slate and timber, and the
	# conifers do the work the broadleaves do at sea level.
	"alpine": {
		"palette": {
			"lawn": "#9FB6A6", "lawn_lit": "#B6CBBC", "lawn_dim": "#7E9689",
			"paving": "#AFBCC7", "paving_lit": "#C8D3DC", "kerb": "#7D8A95",
			"tree_dark": "#1F4A3E", "tree_mid": "#2C6350", "tree_lit": "#3C7F66",
			"hedge": "#365C4C", "trunk": "#4A3B30",
			"neighbour": ["#4C5F72", "#5E6E7E", "#7A6553"],
			"runner": "#2E86AB",
		},
		"blocks": [
			[-7.2, 3.0, 2.6, 2.8, 54.0, 0],
			[0.6, -5.1, 3.0, 2.0, 58.0, 1],
			[18.2, 9.0, 2.6, 3.0, 50.0, 2],
		],
		"fences": [[-2.0, -1.8, 11.0, -1.8, 12], [-2.0, -1.8, -2.0, 7.0, 9]],
		"trees": [[-4.6, 5.4, 0.82], [9.2, -2.9, 0.78], [17.4, 14.4, 0.80]],
		# The treeline is the whole point of the style, so most of the planting
		# is conifers rather than the two token ones parkland carries.
		"pines": [
			[-5.6, 1.2, 1.14], [-4.2, 3.4, 0.96], [-5.0, 6.8, 1.06],
			[1.4, -3.2, 1.10], [4.6, -3.8, 0.94], [7.9, -5.0, 1.16],
			[17.8, 6.6, 1.02], [18.4, 11.8, 0.92],
		],
		"hedges": [[16.6, 2.0, 16.6, 16.2, 0.42], [-1.45, 9.2, -1.45, 15.2, 0.38]],
		"near_trees": [[9.0, 18.3, 0.78], [6.2, 18.3, 0.72]],
		"lamps": [[12.1, 18.36], [10.0, 18.36]],
		"bench": [7.7, 18.16],
		"bollards": [10.9, 17.84, 0.62, 3],
		# Off: mown bands on a rock-and-meadow shelf read as terracing cut into
		# the mountain, which fights the flat plane the museum stands on.
		"mown_stripes": false,
	},
	# Aurora's block, after dark. Every value is pulled down and the hues run
	# cold, so the museum's own lit windows and the traffic are the only bright
	# things outside the walls — which is what makes a night scene read as night
	# rather than as a daylight scene with the brightness turned down.
	"nightfall": {
		"palette": {
			"lawn": "#2C4A3E", "lawn_lit": "#38594B", "lawn_dim": "#20372E",
			"paving": "#4A4766", "paving_lit": "#5D5980", "kerb": "#34324B",
			"road": "#191436", "marking": "#8E86C4",
			"tree_dark": "#12302A", "tree_mid": "#1B4238", "tree_lit": "#255345",
			"hedge": "#1B4238", "trunk": "#2A2438",
			"neighbour": ["#2E2A5C", "#3A3568", "#4A2E5E"],
			"runner": "#7C4DFF",
		},
		"blocks": [
			[-7.0, 3.2, 2.6, 2.8, 62.0, 0],
			[0.9, -4.9, 3.2, 2.0, 68.0, 1],
			[18.2, 9.4, 2.8, 3.0, 58.0, 2],
		],
		"fences": [[-2.0, -1.8, 11.0, -1.8, 12], [-2.0, -1.8, -2.0, 7.0, 9]],
		"trees": [
			[-4.3, 0.4, 1.05], [-3.5, 3.1, 0.92], [-4.6, 5.4, 1.12],
			[1.4, -3.0, 0.98], [4.3, -2.8, 1.10], [9.2, -2.9, 1.02],
			[17.6, 12.2, 1.06],
		],
		"pines": [[-5.6, 2.0, 1.0], [7.9, -5.0, 1.1], [18.2, 6.6, 0.95]],
		"hedges": [[16.6, 2.0, 16.6, 16.2, 0.44], [-1.45, 9.2, -1.45, 15.2, 0.40]],
		"near_trees": [[9.2, 18.3, 0.84], [6.4, 18.3, 0.78]],
		"lamps": [[12.1, 18.36], [10.0, 18.36]],
		"bench": [7.7, 18.16],
		"bollards": [10.9, 17.84, 0.62, 3],
		# Off: a mown highlight is a SUNLIT band. At night it reads as light
		# spilling from nowhere.
		"mown_stripes": false,
	},
	# Foundry Row's block: a working yard, not a park. Cinder and oil-stained
	# concrete where the others put grass, brick sheds for neighbours, and the
	# planting cut right back — a landscaped verge would undo the whole read.
	"ironworks": {
		"palette": {
			"lawn": "#5A5048", "lawn_lit": "#6B6055", "lawn_dim": "#453D36",
			"paving": "#78706A", "paving_lit": "#8C847D", "kerb": "#4E4842",
			"tree_dark": "#3A4A33", "tree_mid": "#4A5E40", "tree_lit": "#5C724F",
			"hedge": "#4A5A44", "trunk": "#3E332A",
			"neighbour": ["#7A3F32", "#8C5040", "#5E4A3E"],
			"runner": "#E07A3C",
		},
		# Tall and close: the point of a foundry yard is that the sheds crowd it.
		"blocks": [
			[-7.0, 3.2, 3.0, 3.0, 66.0, 0],
			[0.9, -4.9, 3.4, 2.2, 58.0, 1],
			[18.2, 9.4, 3.0, 3.2, 62.0, 2],
		],
		"fences": [[-2.0, -1.8, 11.0, -1.8, 14], [-2.0, -1.8, -2.0, 7.0, 11]],
		"trees": [[-4.3, 6.2, 0.78], [3.2, -3.2, 0.74], [17.6, 13.4, 0.76]],
		"pines": [],
		"hedges": [[16.6, 3.0, 16.6, 15.4, 0.34], [-1.45, 10.0, -1.45, 14.6, 0.30]],
		"near_trees": [[9.2, 18.3, 0.72], [6.4, 18.3, 0.66]],
		"lamps": [[12.1, 18.36], [10.0, 18.36]],
		"bench": [7.7, 18.16],
		"bollards": [10.9, 17.84, 0.62, 4],
		"mown_stripes": false,
	},
	# The Verdant Vault stands in its own gardens, so this is the one style that
	# puts MORE planting outside than the museum has inside: deep lawn, hedging
	# on both flanks, and a full treeline instead of the token pair.
	"gardens": {
		"palette": {
			"lawn": "#4E8C3E", "lawn_lit": "#5FA64B", "lawn_dim": "#3C6E30",
			"paving": "#C3BCA8", "paving_lit": "#D6CFBC", "kerb": "#948D7C",
			"tree_dark": "#1F5230", "tree_mid": "#2C6E3F", "tree_lit": "#3E8C52",
			"hedge": "#2C6E3F", "trunk": "#4A3524",
			"neighbour": ["#7A6A4E", "#8E7C5C", "#5E6E4A"],
			"runner": "#C2410C",
		},
		"blocks": [
			[-7.0, 3.2, 2.6, 2.8, 40.0, 0],
			[0.9, -4.9, 3.0, 2.0, 44.0, 1],
			[18.2, 9.4, 2.6, 3.0, 42.0, 2],
		],
		"fences": [[-2.0, -1.8, 11.0, -1.8, 12], [-2.0, -1.8, -2.0, 7.0, 9]],
		"trees": [
			[-4.3, 0.4, 1.08], [-3.5, 2.6, 0.94], [-4.6, 5.0, 1.14],
			[-3.2, 7.4, 0.88], [-4.8, 9.6, 1.02],
			[1.4, -3.0, 1.00], [4.3, -2.8, 1.12], [6.9, -3.6, 0.90],
			[9.2, -2.9, 1.04], [11.8, -3.4, 0.96],
			[17.6, 12.2, 1.08], [17.4, 14.4, 0.92], [18.0, 9.8, 1.00],
		],
		"pines": [[-5.6, 4.0, 0.98], [7.9, -5.0, 1.06]],
		# Hedging on both flanks and a clipped run across the front verge: the
		# formal garden read comes from the hedges, not from the tree count.
		"hedges": [
			[16.6, 1.6, 16.6, 16.4, 0.50], [-1.45, 8.6, -1.45, 15.6, 0.46],
			[-1.2, 17.6, 4.4, 17.6, 0.38],
		],
		"near_trees": [[9.2, 18.3, 0.88], [6.4, 18.3, 0.82]],
		"lamps": [[12.1, 18.36], [10.0, 18.36]],
		"bench": [7.7, 18.16],
		"bollards": [10.9, 17.84, 0.62, 3],
		"mown_stripes": true,
	},
	# Borealis stands on the ice shelf. Distinct from alpine on purpose: alpine
	# is a treeline with rock under it, this is snow with almost nothing living
	# on it, so the neighbours and the traffic carry all the colour.
	"tundra": {
		"palette": {
			"lawn": "#D6E2EA", "lawn_lit": "#EAF2F7", "lawn_dim": "#B9C8D4",
			"paving": "#9FAEBA", "paving_lit": "#B9C6CF", "kerb": "#7C8A95",
			"tree_dark": "#244A44", "tree_mid": "#2F5E54", "tree_lit": "#3E7568",
			"hedge": "#2F5E54", "trunk": "#4A4038",
			"neighbour": ["#5B6E7E", "#6E7F8C", "#48596B"],
			"runner": "#3AA6D8",
		},
		"blocks": [
			[-7.2, 3.0, 2.8, 2.8, 44.0, 0],
			[0.6, -5.1, 3.2, 2.0, 48.0, 1],
			[18.2, 9.0, 2.8, 3.0, 42.0, 2],
		],
		"fences": [[-2.0, -1.8, 11.0, -1.8, 12], [-2.0, -1.8, -2.0, 7.0, 9]],
		"trees": [],
		# A thin, struggling treeline — enough to say "something grows here",
		# not enough to say "forest".
		"pines": [
			[-5.2, 2.4, 0.72], [-4.4, 6.8, 0.64], [8.2, -4.4, 0.70],
			[18.0, 7.4, 0.66],
		],
		"hedges": [[16.6, 4.0, 16.6, 14.2, 0.28], [-1.45, 10.4, -1.45, 14.2, 0.26]],
		"near_trees": [[9.0, 18.3, 0.62], [6.2, 18.3, 0.58]],
		"lamps": [[12.1, 18.36], [10.0, 18.36]],
		"bench": [7.7, 18.16],
		"bollards": [10.9, 17.84, 0.62, 4],
		# Off: a bright band on snow reads as glare, not as ground texture.
		"mown_stripes": false,
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
var public_depth: float = 0.0
var _entrance := Vector2.INF
var _fp := NOMINAL            # the building this surround is framing; see set_footprint


## Tell the surround how big the building actually is, as the union of the
## theme's room rects. Everything outside the walls is authored against NOMINAL,
## so without this a 16x18 plan gets the 15x17 plan's scenery: the east hedge
## runs THROUGH the east wing and a neighbouring block is drawn under the floor,
## which is exactly what "overlaid on a different plane" looks like.
##
## WHY A REMAP AND NOT A KEEP-OUT TEST. Skipping any piece that lands inside the
## footprint would leave a big venue bald on whichever side it grew. Moving the
## piece keeps the scenery and simply re-frames it around the real building.
##
## The map is the IDENTITY when the plan is the nominal 15x17, so every venue
## authored before this existed renders pixel-for-pixel unchanged.
func set_footprint(bounds: Rect2) -> void:
	if bounds.size.x < 1.0 or bounds.size.y < 1.0 or bounds.is_equal_approx(_fp):
		return
	_fp = bounds
	if is_node_ready():district.build_life()
	if not _cars.is_empty():transit.configure()
	queue_redraw()


## The authored lobby can be offset within the building's overall bounds.
## Canopy and entrance carpet must follow its door, not a remapped template.
func set_entrance(front_center: Vector2) -> void:
	_entrance = front_center
	queue_redraw()

func footprint() -> Rect2:
	return _fp


## Piecewise map on one axis. OUTSIDE the nominal edges a coordinate keeps its
## DISTANCE from the edge, so the kerb stays exactly as far from the facade as it
## was authored and the road never gets stretched into a motorway. INSIDE, it
## scales, so the entrance runner still meets the doors.
static func _remap(c: float, n0: float, n1: float, b0: float, b1: float) -> float:
	if c <= n0:
		return b0 + (c - n0)
	if c >= n1:
		return b1 + (c - n1)
	return b0 + (c - n0) / (n1 - n0) * (b1 - b0)


## Nominal grid point -> this venue's grid point. Public because it is the whole
## contract between an authored surround and a plan that is not 15x17: tests use
## it to prove no scenery lands inside a venue's rooms.
func map_point(g: Vector2) -> Vector2:
	return _g(g)


func _g(g: Vector2) -> Vector2:
	var mapped := Vector2(
		_remap(g.x, NOMINAL.position.x, NOMINAL.end.x, _fp.position.x, _fp.end.x),
		_remap(g.y, NOMINAL.position.y, NOMINAL.end.y, _fp.position.y, _fp.end.y))
	mapped.y += public_depth * clampf((g.y - NOMINAL.end.y) / (APRON_B.y - NOMINAL.end.y), 0.0, 1.0)
	return mapped


## Where an arrival steps onto the forecourt, and where the canopy hangs, both
## carried onto the actual footprint. VenueFloor reads these instead of the
## consts so the approach still meets the doors when the plan is a different size.
func apron_bounds() -> Rect2:
	return Rect2(_g(APRON_A), _g(APRON_B) - _g(APRON_A))

func ramp_top() -> Vector2:
	return Vector2(_entrance.x, _g(APRON_B).y - 1.0)

func ramp_bottom() -> Vector2:
	return Vector2(_entrance.x, _g(APRON_B).y + .05)

func surface_drop(g: Vector2) -> float:
	if public_depth <= 0.0:return 0.0
	var apron:=apron_bounds()
	if g.x<apron.position.x or g.x>apron.end.x or g.y<apron.position.y:return DROP
	var edge := _g(APRON_B).y
	if absf(g.x - _entrance.x) <= 1.1:
		return DROP * clampf((g.y - (edge - 1.0)) / 1.05, 0.0, 1.0)
	return DROP if g.y > edge else 0.0

func street_point() -> Vector2:
	return ramp_top() if public_depth > 0.0 else _g(STREET_G)

func arrival_route(from_right: bool) -> Array:
	var route: Array = [_g(WALK_RIGHT if from_right else WALK_LEFT), _g(CROSS_FAR), _g(CROSS_NEAR)]
	if public_depth > 0.0:
		route.append(Vector2(_entrance.x, _g(CROSS_NEAR).y))
		route.append(ramp_bottom())
	route.append(street_point())
	return route

func near_sidewalk_route(from_right: bool) -> Array:
	var route: Array = [_g(NEAR_WALK_RIGHT if from_right else NEAR_WALK_LEFT)]
	if public_depth > 0.0:
		route.append(Vector2(_entrance.x, _g(NEAR_WALK_LEFT).y))
		route.append(ramp_bottom())
	route.append(street_point())
	return route


func canopy_point() -> Vector2:
	return _entrance + Vector2(0,.9) if _entrance.is_finite() else _g(CANOPY_G)


## Grid-space offset from the authored canopy to this venue's, for the static
## painter (which has no instance to ask).
func canopy_offset() -> Vector2:
	return canopy_point() - CANOPY_G
var _traffic: Node2D
var _cars: Array[Dictionary] = []
var _signal_t: float = 0.0
const CAR_HALF_GX := 0.98
## Bumper-to-bumper minimum between two cars in the same lane, in tiles. Two car
## halves plus a little air, so a bunched pair reads as queuing traffic rather
## than as one car parked inside another.
const CAR_MIN_GAP_GX := CAR_HALF_GX * 2.0 + 0.55

# Triangle batch, reused by both canvas items.
var _pts := PackedVector2Array()
var _cols := PackedColorArray()
var _idx := PackedInt32Array()

func _ready() -> void:
	name = "City"
	position = Vector2(0.0, -Y_LIFT)
	_pal = palette_for(style)
	_def = style_def(style)
	district.apply_palette()
	_build_cars()
	_traffic = Node2D.new()
	_traffic.name = "Traffic"
	_traffic.position = Vector2(0.0, Y_LIFT)
	add_child(_traffic)
	_traffic.draw.connect(_draw_traffic)
	var signs:=Node2D.new();signs.name="TransitStops";add_child(signs)
	signs.draw.connect(func() -> void:
		for kind in transit.stops:
			var at: Vector2=transit.stops[kind]+Vector2(-.55,.28)
			var base:=_p(at,DROP)
			signs.draw_line(base,base+Vector2(0,-35),Color("70878a"),2)
			signs.draw_rect(Rect2(base+Vector2(-23,-46),Vector2(46,16)),Color("204e57"))
			signs.draw_string(ThemeDB.fallback_font,base+Vector2(-21,-34),"TAXI" if kind=="taxi" else "SHUTTLE",HORIZONTAL_ALIGNMENT_LEFT,-1,9,Color("f4e6c6"))
		var businesses=preload("res://scenes/venue/floor/city_businesses.gd")
		var doors: Array=businesses.connected(self)+businesses.frontage(self)
		for business in doors:
			var nominal: Vector2=business.get("nominal_door",business.door)
			var base:=_p(nominal,DROP)+Vector2(0,-47)
			signs.draw_rect(Rect2(base+Vector2(-28,-12),Vector2(56,15)),Color("24484a"))
			signs.draw_string(ThemeDB.fallback_font,base+Vector2(-26,-1),business.name,HORIZONTAL_ALIGNMENT_LEFT,-1,8,Color("f0e2c1")))
	district.build_life()
	transit.build_renderers()

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
			"model": i % 3,
		})

	for i in _cars.size():
		Vehicles.assign(_cars[i],venue_id,i)
		_cars[i].forward=float(_cars[i].dir)>0
		_cars[i].trip=i
		_cars[i].pool_id=i
		Routes.start(_cars[i],Routes.main_route(self,bool(_cars[i].forward)),true)
	transit.configure()

## Foreground avenue extent; actual trips continue into connected side streets.
static func lane_span(_gy: float) -> Vector2:
	return Vector2(-30.0, 36.0)

## Rendered vehicles keep a fixed world size while a small venue compresses
## nominal street coordinates. Convert their bumper envelope back to that space.
func car_half_extent(car: Dictionary) -> float:
	var models: Dictionary=Vehicles.manifest().get("models",{})
	var model: Dictionary=models.get(str(car.get("vehicle","")),{})
	var half:=float(model.get("length",CAR_HALF_GX*2.0))*.5
	return half/minf(1.0,maxf(_fp.size.x/NOMINAL.size.x,.1))

## Advance the traffic. VenueFloor drives this from its own _process so the cars
## honour time_scale and stop when the sim stops.
func advance(dt: float, pedestrian_crossing: bool = false) -> void:
	district.advance(dt)
	if _cars.is_empty():
		return
	_signal_t = fmod(_signal_t + dt, TRAFFIC_PHASE_S + WALK_PHASE_S)
	for car in _cars:
		if float(car.wait)>0:
			car.wait=maxf(0,float(car.wait)-dt)
			if car.wait==0:
				if not can_enter(car,car.route[0]):car.wait=.25;continue
				car.trip+=1
				Vehicles.assign_trip(car,venue_id,int(car.trip))
				transit.reset_trip(car)
				Routes.start(car,Routes.main_route(self,bool(car.forward)))
			continue
		var distance:=float(car.speed)*dt
		var gx:=float(car.gx);var gy:=float(car.gy);var dir:=float(car.dir)
		var half:=car_half_extent(car)
		if pedestrian_crossing and (is_equal_approx(gy,LANE_OUT) or is_equal_approx(gy,LANE_IN)):
			# Once a bumper is on the zebra, clear it before giving way. Stopping
			# by the centre trapped half-entered cars while pedestrians waited
			# for that same car to leave. Match crossing_has_car's tolerance.
			if dir>0 and gx+half<=CROSS_MIN_GX+.03:distance=minf(distance,maxf(0,CROSS_MIN_GX-half-gx))
			elif dir<0 and gx-half>=CROSS_MAX_GX-.03:distance=minf(distance,maxf(0,gx-CROSS_MAX_GX-half))
		# Following distance applies on side streets too, including district cars.
		var at:=Vector2(gx,gy);var heading: Vector2=car.axis*dir
		for other in _cars+district.traffic:
			if other==car or float(other.get("wait",0))>0:continue
			var offset:=Vector2(other.gx,other.gy)-at
			var ahead:=offset.dot(heading)
			if ahead>0 and absf(offset.cross(heading))<.65 and (absf(heading.dot(other.axis))>.9 or int(car.pool_id)>int(other.pool_id)):
				distance=minf(distance,maxf(0,ahead-half-car_half_extent(other)-.55))
		distance=transit.limit_step(car,distance,dt)
		if Routes.step(car,distance):car.wait=2.1+fmod(float(car.trip)*1.73,4.0)
		transit.after_step(car)
	transit.update_visuals()
	_traffic.queue_redraw()


## A replacement waits beyond the scene until its entrance lane is clear.
func can_enter(car: Dictionary,point: Vector2) -> bool:
	for other in _cars+district.traffic:
		if other==car or float(other.get("wait",0))>0:continue
		if point.distance_to(Vector2(other.gx,other.gy))<car_half_extent(car)+car_half_extent(other)+.55:return false
	return true

func walk_signal() -> bool:
	return _signal_t >= TRAFFIC_PHASE_S

func crossing_has_car() -> bool:
	for car in _cars:
		if float(car.get("wait",0))>0 or (not is_equal_approx(float(car.gy),LANE_OUT) and not is_equal_approx(float(car.gy),LANE_IN)):continue
		var gx: float = float(car["gx"])
		# A car held exactly at a stop line only touches the crossing boundary;
		# it must not count as occupying the zebra or pedestrians deadlock there.
		var half:=car_half_extent(car)
		if gx + half > CROSS_MIN_GX + 0.03 \
				and gx - half < CROSS_MAX_GX - 0.03:
			return true
	return false

## Test hook: [gx, gy] of every car, in grid space.
func car_positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for car in _cars:
		out.append(Vector2(float(car["gx"]), float(car["gy"])))
	return out

func _draw_traffic() -> void:
	district.draw_motion()
	_flush(_traffic)
	for car in _cars + district.traffic:
		if car.has("transit") and not transit.renderers.is_empty():continue
		if float(car.get("wait",0))>0:continue
		var col: Color = car["col"]
		var g := Vector2(float(car["gx"]) - 0.62, float(car["gy"]) - 0.27)
		var mid: Vector2 = _p(g + Vector2(0.62, 0.27), DROP + 3.0)
		var axis: Vector2 = (_p(g + (car.get("axis",Vector2(1.0,0.0)) as Vector2)) - _p(g)).normalized()
		var facing: float = float(car["dir"])
		var model: int = int(car.get("model", 0))
		# These share a world with the visitors: a seated adult must plausibly
		# fit beneath the glasshouse. The former 34 px bodies read as toy cars
		# beside a roughly 70 px standing character.
		var length: float = [56.0, 62.0, 53.0, 86.0][model]
		var width: float = [21.0, 23.0, 21.5, 25.0][model]
		var normal := Vector2(-axis.y, axis.x)
		if not Vehicles.sprite(car).is_empty():
			var dimensions: Dictionary=Vehicles.manifest().models.get(car.vehicle,{})
			var ground_length:=float(dimensions.get("length",1.8))*36.0555
			# Sprite origin is the tyre contact plane; the asphalt is DROP+5.
			var ground_center:=mid+Vector2(0,2)
			_capsule(ground_center,axis,ground_length+3,19,_pal["shadow"],5)
			_flush(_traffic)
			if Vehicles.draw(_traffic,car,ground_center):
				if car.get("transit","")=="taxi":
					var badge:=ground_center+Vector2(-9,-25)
					_traffic.draw_rect(Rect2(badge,Vector2(18,9)),Color("ead591"))
					_traffic.draw_string(ThemeDB.fallback_font,badge+Vector2(1,7),"TAXI",HORIZONTAL_ALIGNMENT_LEFT,-1,6,Color("253942"))
				continue
		# Soft shadow, tyres and a rounded lower body replace the old pair of
		# stacked rectangular prisms. Models vary between hatch, saloon and
		# compact crossover while retaining an intentionally toy-like scale.
		_capsule(mid + Vector2(0.0, 4.0), axis, length + 5.0, width + 5.0, _pal["shadow"], 4)
		for axle in [-0.29, 0.29]:
			for side in [-1.0, 1.0]:
				var wheel: Vector2 = mid + axis * length * axle + normal * width * 0.43 * side
				_disc(wheel + Vector2(0.0, 2.0), 4.8, 4.1, UI.INK.darkened(0.25))
				_disc(wheel + Vector2(0.0, 1.5), 2.0, 1.7, UI.SLATE.lightened(0.22))
		_capsule(mid, axis, length, width, col.darkened(0.12), 5)
		_capsule(mid + Vector2(0.0, -3.0), axis, length - 2.0, width - 2.0, col, 5)
		# Tapered glasshouse. Its slight rearward bias gives each vehicle a
		# readable nose and direction without bolting a square cab to the body.
		var cabin_shift: float = -facing * ([2.5, 0.0, 4.0, -2.0][model])
		var cabin_len: float = [29.0, 34.0, 27.0, 67.0][model]
		var cabin_mid := mid + axis * cabin_shift + Vector2(0.0, -10.0)
		_capsule(cabin_mid, axis, cabin_len, width * 0.68,
			UI.SLATE.darkened(0.34), 4)
		# Windscreen glint, headlights and a tiny red tail pair sell curvature
		# and direction at gameplay zoom.
		_capsule(cabin_mid - normal * 1.2, axis, cabin_len * 0.72, 2.1,
			Color(0.66, 0.87, 0.93, 0.72), 3)
		var nose := mid + axis * facing * (length * 0.44) + Vector2(0.0, -2.0)
		var tail := mid - axis * facing * (length * 0.44) + Vector2(0.0, -1.0)
		for side in [-1.0, 1.0]:
			_disc(nose + normal * width * 0.25 * side, 2.7, 2.0, UI.BRASS.lightened(0.2))
			_disc(tail + normal * width * 0.25 * side, 2.1, 1.6, Color("#D95256"))
	_flush(_traffic)

## Screen-space rounded vehicle panel. `rounds` controls the number of points on
## each end; keeping this in the triangle batch costs no extra canvas commands.
func _capsule(center: Vector2, axis: Vector2, length: float, width: float,
		col: Color, rounds: int = 4) -> void:
	var normal := Vector2(-axis.y, axis.x)
	var radius := width * 0.5
	var half_straight := maxf(length * 0.5 - radius, 0.0)
	var poly := PackedVector2Array()
	for end_sign in [1.0, -1.0]:
		var end_center: Vector2 = center + axis * half_straight * end_sign
		var base_angle: float = 0.0 if end_sign > 0.0 else PI
		for i in range(rounds + 1):
			var angle := base_angle - PI * 0.5 + PI * float(i) / float(rounds)
			poly.append(end_center + axis * cos(angle) * radius + normal * sin(angle) * radius)
	_fill(poly, col)

# --- Static surround ----------------------------------------------------------

func _draw() -> void:
	draw_set_transform(Vector2(0.0, Y_LIFT))
	_draw_ground_plane()
	_draw_street()
	district.ground()
	_draw_far_scenery()
	_draw_apron()
	_flush(self)
	_draw_access_ramp()
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
		Color(district.design.ground) if not district.design.is_empty() else _pal["lawn"])
	if not district.design.is_empty():return
	if style == "harbour":
		var reflection: Color = _pal["lawn_lit"]
		reflection.a = .32
		for bank in range(2):
			for row in range(6):
				for segment in range(28):
					var t0 := float(segment)/28.0
					var t1 := float(segment+1)/28.0
					var a := Vector2(-8+t0*18,-9+row*1.1+sin(t0*TAU+row*.6)*.18)
					var b := Vector2(-8+t1*18,-9+row*1.1+sin(t1*TAU+row*.6)*.18)
					if bank==1:
						a=Vector2(21+row*.9,2+t0*16+sin(t0*TAU+row*.6)*.18)
						b=Vector2(21+row*.9,2+t1*16+sin(t1*TAU+row*.6)*.18)
					var width := Vector2(0,.055) if bank==0 else Vector2(.055,0)
					_fill(PackedVector2Array([_p(a,DROP),_p(b,DROP),_p(b+width,DROP),_p(a+width,DROP)]),reflection)
		return
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
	var gx0: float = -30.0
	var span: float = 75.0
	_patch(Vector2(gx0, APRON_B.y), Vector2(span, SIDEWALK_B - APRON_B.y), _pal["paving"], DROP)
	_patch(Vector2(gx0, SIDEWALK_B), Vector2(span, KERB_B - SIDEWALK_B), _pal["kerb"], DROP)
	_skirt(Vector2(gx0, KERB_B), Vector2(gx0 + span, KERB_B), 5.0, _pal["kerb"].darkened(0.30), DROP)
	_patch(Vector2(gx0, KERB_B), Vector2(span, ROAD_B - KERB_B), _pal["road"], DROP + 5.0)
	# Far kerb and pavement. This is now a real pedestrian source rather than
	# scenery: arrivals walk in from either end, then turn onto the crossing.
	_patch(Vector2(gx0, ROAD_B), Vector2(span, 0.22), _pal["kerb"], DROP)
	_skirt(Vector2(gx0, ROAD_B), Vector2(gx0 + span, ROAD_B), 4.0,
		_pal["kerb"].darkened(0.30), DROP)
	_patch(Vector2(gx0, ROAD_B + 0.22), Vector2(span, 0.72), _pal["paving"], DROP)
	_patch(Vector2(gx0, ROAD_B + 0.94), Vector2(span, 3.0), _pal["lawn_dim"], DROP)
	# Crossing, aimed at the forecourt so the approach has somewhere to come from.
	for i in 5:
		var gx: float = 10.4 + float(i) * 0.46
		_patch(Vector2(gx, KERB_B + 0.16), Vector2(0.26, ROAD_B - KERB_B - 0.32),
			_pal["marking"].darkened(0.06), DROP + 5.0)

## Everything on the far side of the building: neighbouring blocks, the boundary
## fence, the north and west treelines. Drawn back to front by depth.
func _draw_far_scenery() -> void:
	if not district.design.is_empty():
		district.scenery()
		return
	# Drawn back-to-front by PROJECTED DEPTH, not by category.
	#
	# Drawing all the blocks, then all the trees, put every tree in front of
	# every block regardless of where it stood: a conifer authored well behind a
	# neighbouring shed was painted straight up its roof and front face. Reported
	# as trees "growing through" the buildings, and it happened in every style
	# because the ordering was the loop order.
	#
	# The rest of the diorama is Y-sorted by the scene tree; this node draws its
	# whole surround into one canvas item for the draw-call budget, so it has to
	# do the same sort itself. Key is the base point's projected y — the same
	# quantity Y-sort uses — so the two agree.
	var hues: Array = _pal["neighbour"]
	var items: Array = []
	for b in _def.get("blocks", []):
		var bg := Vector2(float(b[0]), float(b[1]))
		var bs := Vector2(float(b[2]), float(b[3]))
		# A block's depth is its FRONT corner, not its origin: keyed on the origin
		# a deep block sorts behind things standing beside it.
		items.append([_depth(bg + bs), "block", bg, bs, float(b[4]),
			hues[int(b[5]) % hues.size()]])
	for f in _def.get("fences", []):
		var fa := Vector2(float(f[0]), float(f[1]))
		var fb := Vector2(float(f[2]), float(f[3]))
		items.append([_depth((fa + fb) * 0.5), "fence", fa, fb, int(f[4]), null])
	for t in _def.get("trees", []):
		var tg := Vector2(float(t[0]), float(t[1]))
		items.append([_depth(tg), "tree", tg, float(t[2]), 0.0, null])
	for t in _def.get("pines", []):
		var pg := Vector2(float(t[0]), float(t[1]))
		items.append([_depth(pg), "pine", pg, float(t[2]), 0.0, null])
	for h in _def.get("hedges", []):
		var ha := Vector2(float(h[0]), float(h[1]))
		var hb := Vector2(float(h[2]), float(h[3]))
		items.append([_depth((ha + hb) * 0.5), "hedge", ha, hb, float(h[4]), null])
	items.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for it in items:
		match str(it[1]):
			"block": _block(it[2], it[3], float(it[4]), it[5])
			"fence": _fence(it[2], it[3], int(it[4]))
			"tree": _tree(it[2], float(it[3]))
			"pine": _pine(it[2], float(it[3]))
			"hedge": _hedge(it[2], it[3], float(it[4]))

## Sort key for the surround: the projected y of a grid point, which is what
## Y-sort uses for everything else in the diorama.
func _depth(g: Vector2) -> float:
	return _p(g).y

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
	if _entrance.is_finite():
		var start := _entrance + Vector2(-.8,.35)
		var depth := maxf(_g(APRON_B).y - start.y, .1)
		Iso.rug(self, start, Vector2(1.6,depth),runner.darkened(.06))
		Iso.rug(self, start+Vector2(.15,0),Vector2(1.3,depth),runner.lightened(.10))
	else:
		_patch(Vector2(12.1, 17.35), Vector2(1.6, APRON_B.y - 17.35), runner.darkened(0.06))
		_patch(Vector2(12.25, 17.35), Vector2(1.3, APRON_B.y - 17.35), runner.lightened(0.10))

## A lowered entrance in the slab. Its slope matches surface_drop exactly.
func _draw_access_ramp() -> void:
	if public_depth <= 0.0:return
	var a := ramp_top()
	var b := ramp_bottom()
	var p0 := Iso.to_screen(a + Vector2(-1.05,0))
	var p1 := Iso.to_screen(a + Vector2(1.05,0))
	var p2 := Iso.to_screen(b + Vector2(1.05,0)) + Vector2(0,DROP)
	var p3 := Iso.to_screen(b + Vector2(-1.05,0)) + Vector2(0,DROP)
	draw_colored_polygon(PackedVector2Array([p0,p1,p2,p3]), _pal["paving_lit"])
	for t in [.18,.40,.62,.84]:
		draw_line(p0.lerp(p3,t),p1.lerp(p2,t),_pal["kerb"].lightened(.15),1.4,true)
	for edge in [[p0,p3],[p1,p2]]:
		draw_line(edge[0],edge[1],_pal["paving_lit"].lightened(.18),3,true)

## Anything between the facade and the kerb. Drawn after the apron so it sits on
## it, and kept under ~46px tall so it cannot reach up into the museum silhouette.
func _draw_near_scenery() -> void:
	for p in _def.get("planters", []):
		_planter(Vector2(float(p[0]), float(p[1])))
	for t in _def.get("near_trees", []):
		_tree(Vector2(float(t[0]), 18.70 if public_depth > 0.0 else float(t[1])), float(t[2]), DROP)
	for l in _def.get("lamps", []):
		_lamp(Vector2(float(l[0]), 18.70 if public_depth > 0.0 else float(l[1])))
	# Bench and litter bin on the pavement, facing the crossing.
	var bench: Array = _def.get("bench", [])
	if bench.size() >= 2 and public_depth <= 0.0:
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
			_prism(Vector2(float(posts[0]) + float(i) * float(posts[2]), 18.76 if public_depth > 0.0 else float(posts[1])),
				Vector2(0.12, 0.12), 9.0, _pal["kerb"].darkened(0.30), DROP if public_depth > 0.0 else 0.0)

## Physical curbside contacts shared with public navigation. The old unused
## sidewalk bench is replaced by the plaza's usable benches; trees and lamps
## occupy the curbside furnishing strip, leaving a continuous pedestrian lane.
func public_obstacles() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if public_depth <= 0.0:return out
	for key in ["near_trees","lamps"]:
		for item in _def.get(key,[]):
			var at := _g(Vector2(float(item[0]),18.70))
			out.append(Rect2(at-Vector2(.05,.05),Vector2(.10,.10)))
	var posts: Array = _def.get("bollards",[])
	if posts.size() >= 4:
		for i in int(posts[3]):
			var at := _g(Vector2(float(posts[0])+i*float(posts[2]),18.76))
			out.append(Rect2(at,Vector2(.12,.12)))
	return out

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
## `shift` is the grid-space offset from the authored doors to this venue's,
## which the caller gets from canopy_offset() — without it the awning stays put
## while the entrance it covers moves with the footprint.
static func draw_canopy(ci: CanvasItem, style_name: String = "parkland",
		shift: Vector2 = Vector2.ZERO) -> void:
	var pal: Dictionary = palette_for(style_name)
	var post_h := 48.0
	var origin: Vector2 = CANOPY_A + shift
	var back := origin + Vector2(0.0, CANOPY_SIZE.y)
	Iso.rug(ci, origin + Vector2(0.14, 0.18), CANOPY_SIZE, Color(0.06, 0.03, 0.14, 0.15))
	for gx in [origin.x + 0.04, origin.x + CANOPY_SIZE.x - 0.14]:
		Iso.box(ci, Vector2(gx, back.y - 0.1), Vector2(0.1, 0.1), post_h,
			(pal["paving"] as Color).darkened(0.26), Color(0, 0, 0, 0.24))
	var q := Iso.quad(origin, CANOPY_SIZE)
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
	_soft_shadow(base + Vector2(2.0, 1.0) * s, 17.0 * s, 7.0 * s, _pal["shadow"])
	_soft_shadow(base, 4.0 * s, 2.2 * s, Color(0.12, 0.17, 0.13, 0.24))
	_prism(g - Vector2(0.07, 0.07) * s, Vector2(0.14, 0.14) * s, 13.0 * s, _pal["trunk"], drop)
	# Four overlapping, softly lit volumes keep the old crown bounds and trunk
	# anchor. Vertex shading belongs to the static batch, so no texture, light,
	# per-frame update or extra canvas draw call is needed for individual trees.
	var shade := _foliage_tone(_pal["tree_dark"])
	var leaf := _foliage_tone(_pal["tree_mid"])
	var light := _foliage_tone(_pal["tree_lit"]).lerp(Color("#CDD1B4"), 0.10)
	_foliage_volume(base + Vector2(0.0, -24.0) * s, 16.8 * s, 17.0 * s, shade, leaf)
	_foliage_volume(base + Vector2(7.4, -29.5) * s, 10.3 * s, 11.6 * s, shade.lerp(leaf, 0.30), light)
	_foliage_volume(base + Vector2(-7.0, -29.0) * s, 11.0 * s, 12.0 * s, shade.lerp(leaf, 0.45), light)
	_foliage_volume(base + Vector2(-1.8, -35.0) * s, 10.2 * s, 9.2 * s, leaf, light)

func _pine(g: Vector2, s: float, drop: float = DROP) -> void:
	var base: Vector2 = _p(g, drop)
	_soft_shadow(base + Vector2(2.0, 1.0), 14.0 * s, 6.0 * s, _pal["shadow"])
	_prism(g - Vector2(0.06, 0.06) * s, Vector2(0.12, 0.12) * s, 10.0 * s, _pal["trunk"], drop)
	for i in 3:
		var w: float = (16.0 - float(i) * 4.2) * s
		var y: float = base.y - (10.0 + float(i) * 13.0) * s
		var tip: float = y - 19.0 * s
		var col := _foliage_tone(_pal["tree_dark"] if i == 0 else (_pal["tree_mid"] if i == 1 else _pal["tree_lit"]))
		# Rounded lower branches and a continuous light gradient replace the
		# three flat triangles without changing their width or maximum height.
		var points := PackedVector2Array([Vector2(base.x, tip)])
		var colors := PackedColorArray([col.lightened(0.16)])
		for j in range(17):
			var angle := PI * float(j) / 16.0
			points.append(Vector2(base.x + cos(angle) * w, y + sin(angle) * 2.5 * s))
			colors.append(col.darkened(0.18).lerp(col.lightened(0.12), (1.0 - cos(angle)) * 0.5))
		_fill_shaded(points, colors)

func _hedge(a: Vector2, b: Vector2, w: float) -> void:
	var d: Vector2 = b - a
	var len_g: float = d.length()
	var n: int = maxi(1, int(round(len_g / 1.1)))
	var step: Vector2 = d / float(n)
	for i in n:
		var g: Vector2 = a + step * float(i)
		var size := Vector2(w, step.y * 0.94) if absf(d.x) < absf(d.y) \
			else Vector2(step.x * 0.94, w)
		var col := _foliage_tone(_pal["hedge"])
		var mid := _p(g + size * 0.5, DROP)
		_soft_shadow(mid + Vector2(1.5, 1.5), (size.x + size.y) * 16.0, (size.x + size.y) * 8.0,
			Color(0.12, 0.17, 0.13, 0.16))
		_hedge_volume(g, size, col)

## Keep venue hues, but bring bright flat foliage toward the quiet material
## saturation of the baked planters and cast. This affects decorative paint only.
func _foliage_tone(col: Color) -> Color:
	return Color.from_hsv(col.h, col.s * 0.78, col.v, col.a)

## Diffuse ellipsoid, sampled into the shared triangle batch. A narrow alpha
## fringe softens the silhouette even when the optional world AA pass is off.
func _foliage_volume(center: Vector2, rx: float, ry: float, dark: Color, light: Color) -> void:
	const SEGMENTS := 24
	const RINGS := 4
	var first := _pts.size()
	var key := Vector3(-0.46, -0.56, 0.69).normalized()
	_pts.append(center)
	_cols.append(dark.lerp(light, 0.22 + 0.78 * key.z))
	for ring in range(1, RINGS + 1):
		var radius := float(ring) / float(RINGS)
		for segment in range(SEGMENTS):
			var angle := TAU * float(segment) / float(SEGMENTS)
			var normal := Vector3(cos(angle) * radius, sin(angle) * radius, sqrt(maxf(0.0, 1.0 - radius * radius)))
			_pts.append(center + Vector2(normal.x * rx, normal.y * ry))
			_cols.append(dark.lerp(light, 0.16 + 0.84 * maxf(normal.dot(key), 0.0)))
			var current := first + 1 + (ring - 1) * SEGMENTS + segment
			var next := first + 1 + (ring - 1) * SEGMENTS + (segment + 1) % SEGMENTS
			if ring == 1:
				_idx.append_array(PackedInt32Array([first, current, next]))
			else:
				_idx.append_array(PackedInt32Array([current - SEGMENTS, current, next, current - SEGMENTS, next, next - SEGMENTS]))
	var outer := first + 1 + (RINGS - 1) * SEGMENTS
	var fringe := _pts.size()
	for segment in range(SEGMENTS):
		var angle := TAU * float(segment) / float(SEGMENTS)
		_pts.append(center + Vector2(cos(angle) * (rx + 0.45), sin(angle) * (ry + 0.45)))
		var color := _cols[outer + segment]
		color.a = 0.0
		_cols.append(color)
		var next := (segment + 1) % SEGMENTS
		_idx.append_array(PackedInt32Array([outer + segment, fringe + segment, fringe + next, outer + segment, fringe + next, outer + next]))

## A single fading mesh, rather than overlapping opaque discs, keeps contact
## shadows soft and restrained at both overview and close camera scales.
func _soft_shadow(center: Vector2, rx: float, ry: float, col: Color) -> void:
	const SEGMENTS := 24
	var first := _pts.size()
	_pts.append(center)
	_cols.append(col)
	for i in range(SEGMENTS):
		var angle := TAU * float(i) / float(SEGMENTS)
		_pts.append(center + Vector2(cos(angle) * rx, sin(angle) * ry))
		_cols.append(Color(col.r, col.g, col.b, 0.0))
		_idx.append_array(PackedInt32Array([first, first + 1 + i, first + 1 + (i + 1) % SEGMENTS]))

## Rounded-over clipped hedge: the same footprint and 19 px top as the old
## two stacked prisms, with a bevel and broad material shading instead of a step.
func _hedge_volume(g: Vector2, size: Vector2, col: Color) -> void:
	var inset := minf(0.075, minf(size.x, size.y) * 0.18)
	var low := PackedVector2Array([_p(g, DROP), _p(g + Vector2(size.x, 0), DROP),
		_p(g + size, DROP), _p(g + Vector2(0, size.y), DROP)])
	var high := PackedVector2Array([_p(g + Vector2(inset, inset), DROP - 19.0),
		_p(g + Vector2(size.x - inset, inset), DROP - 19.0),
		_p(g + size - Vector2(inset, inset), DROP - 19.0),
		_p(g + Vector2(inset, size.y - inset), DROP - 19.0)])
	for i in [1, 2]:
		var next: int = i + 1
		var shade := 0.17 if i == 1 else 0.27
		var shoulder_a := low[i] + Vector2(0, -15.0)
		var shoulder_b := low[next] + Vector2(0, -15.0)
		_fill_shaded(PackedVector2Array([low[i], low[next], shoulder_b, shoulder_a]),
			PackedColorArray([col.darkened(shade + 0.12), col.darkened(shade + 0.12), col.darkened(shade), col.darkened(shade)]))
		_fill_shaded(PackedVector2Array([shoulder_a, shoulder_b, high[next], high[i]]),
			PackedColorArray([col.darkened(shade), col.darkened(shade), col.lightened(0.09), col.lightened(0.09)]))
	_fill_shaded(high, PackedColorArray([col.lightened(0.20), col.lightened(0.10), col, col.lightened(0.13)]))

func _fill_shaded(poly: PackedVector2Array, colors: PackedColorArray) -> void:
	var first := _pts.size()
	_pts.append_array(poly)
	_cols.append_array(colors)
	for i in range(1, poly.size() - 1):
		_idx.append_array(PackedInt32Array([first, first + i, first + i + 1]))

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

## Project a grid point, dropped to the outside-world ground plane. This is the
## ONLY grid->screen conversion in the file, which is what lets set_footprint()
## re-frame the entire surround — consts, style table and all — from one place.
func _p(g: Vector2, drop: float = 0.0) -> Vector2:
	return Iso.to_screen(_g(g)) + Vector2(0.0, drop)

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
	# Broad sky light and a darker ground contact give the same soft material
	# response as the Blender props. Vertex shading stays in the static batch.
	var ambient := Color("#354A50")
	var dim := col.lerp(ambient, 0.28)
	var lit := col.lerp(ambient, 0.12)
	_fill_shaded(PackedVector2Array([left, front, front + up, left + up]),
		PackedColorArray([dim.darkened(0.10), dim.darkened(0.12), dim.lightened(0.05), dim.lightened(0.09)]))
	_fill_shaded(PackedVector2Array([front, right, right + up, front + up]),
		PackedColorArray([lit.darkened(0.10), lit.darkened(0.07), lit.lightened(0.10), lit.lightened(0.04)]))
	_fill_shaded(PackedVector2Array([back + up, right + up, front + up, left + up]),
		PackedColorArray([col.lightened(0.14), col.lightened(0.08), col, col.lightened(0.06)]))
	# A narrow bevel stays inside the original face; no footprint or height change.
	if h >= 3.0 and minf(size.x, size.y) >= 0.20:
		var bevel := Vector2(0.0, minf(1.1, h * 0.15))
		_fill_shaded(PackedVector2Array([left + up, front + up, front + up + bevel, left + up + bevel]),
			PackedColorArray([col.lightened(0.04), col, dim, dim]))
		_fill_shaded(PackedVector2Array([front + up, right + up, right + up + bevel, front + up + bevel]),
			PackedColorArray([col.lightened(0.08), col.lightened(0.14), lit, lit]))

## Floating slab — a box lifted clear of the ground, for roofs and parapets.
func _slab(g: Vector2, size: Vector2, h: float, thick: float, col: Color,
		drop: float = 0.0) -> void:
	_prism(g, size, thick, col, drop - h)

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
