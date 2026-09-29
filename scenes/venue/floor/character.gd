extends Node2D
## Character — original museum crowd with role-specific offline sprite pools.
## Normal visitors use directional walking/idle art, a seated pose and an
## on-demand public feeding action. Adult staff use separate role assets.
## Ellis is reserved for the host. Editable Blender sources live in
## art/npc-locomotion and art/npc-activities at project root.
## The procedural figure/baker below remains the fallback, not the live art source.
## Public API: set_look_slot / randomize_look / set_uniform / walking / facing /
## with_cart / holding_sign / carry_stack.

const MotionSprites := preload("res://scripts/characters/motion_sprites.gd")
const ActivitySprites := preload("res://scripts/characters/activity_sprites.gd")
const SeatingSprites := preload("res://scripts/characters/seating_sprites.gd")
const CartSprites := preload("res://scripts/characters/cart_sprites.gd")
const UI := preload("res://scripts/ui/ui_kit.gd")
const StaffSprites := preload("res://scripts/characters/staff_sprites.gd")
const VisitorSprites := preload("res://scripts/characters/visitor_sprites.gd")
const Baker := preload("res://scenes/venue/floor/character_baker.gd")

const Roster := preload("res://scripts/characters/npc_roster.gd")
var actor_role: String = ""
var identity: Dictionary = {}

const WALK_FPS := 10.0
const STOP_DEBOUNCE := 0.08
## Ignore tiny steering corrections around a 45-degree sprite boundary. This
## changes only the displayed heading, never routes, speed or distance phase.
const HEADING_HYSTERESIS := PI / 36.0
const OUTLINE := Color("#3A2A1F")
const OUTLINE_W := 1.8
## Eyes are inked a shade lighter than the silhouette stroke. At the size the
## head is minified to on a phone, filling them with OUTLINE let them merge with
## the head stroke and with the staff cap into one dark mass.
const EYE_INK := Color("#4A3728")

## Figure metrics the bake budget and the suites both reason about.
const HEAD_R := 10.8
const HEAD_Y := -33.5
const BOB_AMP := 2.6
const SQUASH_AMP := 0.07

const HAIR_STYLES := 8
## Build multiplies torso/limb width and, at 45% strength, head radius. It is
## serialised through the bake, so it costs cache slots rather than draw time.
const BUILDS: Array[float] = [0.91, 1.0, 1.09]
## Distinct visitor looks. Bounds the bake cache. Every slot is a distinct
## (hair style, build) pair, and the palette axes are strided so no two slots
## share a full palette. Sized above the floor's peak population so a busy floor
## no longer shows the same person three times.
const LOOK_COUNT := HAIR_STYLES * 3   # 24
## Per-department staff variants. Staff read by uniform hue, so the variants only
## need to break up skin, hair and stature — three is enough for five tellers.
const STAFF_LOOK_COUNT := 3
## Styles that still read under a peaked cap: nothing that piles mass on the crown.
const STAFF_STYLES: Array[int] = [0, 6, 7]

const SKIN_TONES: Array[Color] = [
	Color("#F8D8B0"), Color("#EFC094"), Color("#D9A170"), Color("#B87B4C"),
	Color("#8E5733"), Color("#66412A"),
]
const HAIR_COLORS: Array[Color] = [
	Color("#2B2320"), Color("#4E3524"), Color("#7C5228"), Color("#C79A45"),
	Color("#B5AFA8"), Color("#8A3A2C"), Color("#42304E"),
]
const SHIRT_COLORS: Array[Color] = [
	Color("#4E7FB5"), Color("#C85A5A"), Color("#5FA86E"), Color("#D19A3E"),
	Color("#7A6BB5"), Color("#4FA3A5"), Color("#C77BA6"), Color("#5C6B8A"),
]
const PANTS_COLORS: Array[Color] = [
	Color("#3A3F4A"), Color("#5A4A3A"), Color("#44546A"), Color("#4A3F52"),
]

## Hair is silhouette-first. On a phone the head is about twenty screen pixels,
## so the only thing a player resolves is the OUTLINE; four styles that all hug
## the skull at r+0.8 are one haircut in four colours no matter how the strands
## are shaded. Seven of the eight styles below push the outline at least 3px past
## the skull cap.
##
## HAIR_BACK — masses behind the skull, drawn BEFORE it so the head occludes
## them. That is what lets a lock or a tail read at full strength without its
## 1.8px stroke ever crossing skin. Entries are [dx, dy, rx, ry] in design px
## from the head centre.
const HAIR_BACK: Array = [
	[],                                                             # 0 crop
	[],                                                             # 1 side sweep
	[[-1.0, -11.8, 4.8, 4.2]],                                      # 2 bun
	[[-10.4, 2.8, 4.2, 7.2], [10.4, 2.8, 4.2, 7.2]],                # 3 bob
	[[-10.6, -6.0, 4.6, 4.6], [0.0, -11.4, 5.2, 4.6],
		[10.6, -6.0, 4.6, 4.6]],                                    # 4 curls
	[[-0.4, -8.8, 4.8, 4.2], [0.4, -13.0, 3.0, 3.0]],               # 5 tall stack
	[[-12.0, 1.8, 4.2, 8.2], [-9.0, -5.8, 2.8, 2.8]],               # 6 ponytail
	[[-11.8, -5.4, 4.4, 4.4], [11.0, -5.6, 4.0, 4.0]],              # 7 twin tails
]

## HAIR_FRONT — appliqués on the face side of the skull. Filled, never stroked.
const HAIR_FRONT: Array = [
	[], [[-5.6, -8.2, 7.0, 5.4]], [], [], [], [], [], [],
]

## Crown band per style: [outer radius above HEAD_R, band thickness, sweep start
## in half-turns, sweep end in turns]. Style 4's band is thick and wide because
## the halo IS its silhouette.
const HAIR_CAP: Array = [
	[0.8, 5.8, 0.97, 1.03],
	[1.0, 6.6, 0.84, 1.05],
	[0.8, 5.4, 0.97, 1.03],
	[1.0, 6.2, 0.82, 1.08],
	[4.2, 9.0, 0.90, 1.10],
	[0.9, 6.0, 0.92, 1.06],
	[1.0, 6.4, 0.88, 1.08],
	[0.9, 6.0, 0.94, 1.06],
]

## Face layout, in design px from the head centre. The features used to pile into
## x in [-0.2, 10.5] on a head of radius 10.8 — 97% of the ink in the right half,
## touching the silhouette — which is why the head read as a ball with a face
## sliding off it rather than as a face. FACE_CX keeps the 3/4 offset small, and
## EYE_DX is held wide enough that the gap between the eyes survives being
## minified onto a phone instead of fusing into one dark blob.
const FACE_CX := 1.5
const EYE_DX := 3.0
const EYE_R := Vector2(1.35, 1.65)
const BROW_R := Vector2(1.7, 0.65)
const MOUTH_DX := 0.6
const MOUTH_R := 2.5
const BLUSH_FAR := Vector3(-4.4, 2.2, 1.9)    # dx from face centre, dy, radius
const BLUSH_NEAR := Vector3(4.8, 2.1, 1.7)
## Staff cap peak, design px from the head centre: x span, then y span. The peak
## used to abut the eye tops exactly, and since both were near-black they fused
## into one bar that read as wraparound sunglasses on every staff member.
const CAP_PEAK_X := Vector2(-2.6, 9.6)
const CAP_PEAK_Y := Vector2(-8.2, -5.4)

var is_staff: bool = false
var uniform_color: Color = Color("#C4703F")
var with_cart: bool = false:
	set(value):
		with_cart=value
		# A loaded cart uses its own steering bank. Do not retain or decode
		# ordinary heading textures until the actor walks without the cart.
		_heading_set={} if value else MotionSprites.direction_set(identity,_motion_heading)
		if _frame>=0 and not _motion_set.is_empty():_sync_motion_frame()
		queue_redraw()
var holding_sign: bool = false     # promoter: holds an exhibit sign
var walking: bool = false:
	set(value):
		if walking == value:
			return
		walking = value
		_stop_elapsed = 0.0
		queue_redraw()
var walk_backwards := false
## Native seating follows the measured furniture contact and animated action.
var seated: bool = false
## Legacy primitive fallback only; native poses use SeatingSprites.SEAT_HEIGHT.
const SEAT_LIFT := 6.5
var facing: int = 1                # 1 = right, -1 = left
var carry_stack: int = 0:
	set(value):
		carry_stack=maxi(value,0)
		queue_redraw()
var manager_rank: int = 0          # 0 ordinary staff; 1..10 assigned manager
var reaction: String = "":
	set(value):
		reaction = value
		queue_redraw()

## Set by CharacterBaker: freeze on one walk pose and always draw primitives.
var bake_pose: int = -1
## Set by PortraitBaker. The walking figure is drawn in three-quarter profile
## facing +x, and the cap peak's geometry is authored for exactly that: it juts
## forward, far to the right of the head centre. A portrait frames the same head
## near front-on, where that identical wedge reads as a pale bar lying sideways
## across the crown. Front-on framing gets a symmetric, foreshortened brim.
var portrait_mode: bool = false

var _skin: Color = SKIN_TONES[0]
var _hair: Color = HAIR_COLORS[0]
var _shirt: Color = SHIRT_COLORS[0]
var _pants: Color = PANTS_COLORS[0]
var _hair_style: int = 0
var _build: float = 1.0
var _look_slot: int = -1
var _look_key: String = ""
var _is_painter: bool = false
var _bob_t: float = 0.0
var _frame: int = 0
var _frames: Array = []
var _approved_seated: Texture2D = null
var _uses_approved_art := false
var _motion_set: Dictionary = {}
var _cart_set: Dictionary = {}
var _cart_heading := Vector2.DOWN
var _cart_turn: Dictionary = {}
var _cart_turn_frames: Array = []
var _view_back := false
## Match legacy initial right/front facing until movement or a station supplies a heading.
var _motion_heading := 0
var _heading_set: Dictionary = {}
var _cycle_phase := 0.0
var _cycle_rate := 1.8
var _distance_driven := false
## Render-only micro-wait debounce. Logical phase remains driven exclusively by
## record_motion; a sustained stop still uses the rig's dedicated idle pose.
var _stop_elapsed := 0.0
var _feeding_frames: Array[Texture2D] = []
var _feeding_frame := -1
var _seating_frames: Array[Texture2D] = []
var _seating_active := false
var _seating_progress := 0.0
var _seating_ground_offset := Vector2.ZERO
var _seating_height := SeatingSprites.SEAT_HEIGHT

func prepare_seating() -> void:
	if actor_role != "visitor" or _seating_frames.size()>=SeatingSprites.frame_count()*2:return
	var texture := SeatingSprites.frame(identity,_seating_frames.size())
	if texture != null:_seating_frames.append(texture)

func begin_seating(front: Vector2, ground_offset: Vector2, height: float = SeatingSprites.SEAT_HEIGHT) -> bool:
	if actor_role != "visitor":return false
	while _seating_frames.size()<SeatingSprites.frame_count()*2:
		var previous := _seating_frames.size()
		prepare_seating()
		if previous==_seating_frames.size():return false
	walking=false
	set_motion_vector(front,0)
	_seating_progress=0
	_seating_ground_offset=ground_offset
	_seating_height=height
	_seating_active=true
	seated=true
	queue_redraw()
	return true

func advance_seating(delta: float, sit_down: bool) -> bool:
	if not _seating_active:return true
	_seating_progress=move_toward(_seating_progress,1.0 if sit_down else 0.0,delta/SeatingSprites.DURATION)
	queue_redraw()
	return _seating_progress>=1.0 if sit_down else _seating_progress<=0.0

func end_seating() -> void:
	seated=false
	_seating_active=false
	_seating_progress=0
	_seating_frames.clear()
	queue_redraw()

func seating_foot_distance() -> float:
	return float(_motion_set.get("seating_foot_grid",.189))*absf(scale.y)

func prepare_bird_feeding() -> void:
	if actor_role != "visitor" or _feeding_frames.size()>=ActivitySprites.frame_count():return
	var texture := ActivitySprites.feeding_frame(identity,_feeding_frames.size())
	if texture != null:_feeding_frames.append(texture)

func set_bird_feeding(active: bool, elapsed: float = 0.0) -> void:
	if not active or actor_role != "visitor" or seated or walking:
		if _feeding_frame >= 0:
			_feeding_frame = -1
			_feeding_frames.clear()
			queue_redraw()
		return
	if _feeding_frames.size()!=ActivitySprites.frame_count():_feeding_frames = ActivitySprites.feeding_frames(identity)
	if _feeding_frames.is_empty():return
	var frame := int(fposmod(elapsed,ActivitySprites.DURATION)/ActivitySprites.DURATION*ActivitySprites.frame_count())
	if frame != _feeding_frame:
		_feeding_frame = frame
		queue_redraw()

## Projected directly from the Blender wrist; use the current mirror and scale
## explicitly because the plaza and Character may update in either scene order.
func public_hand_position(release: bool = false) -> Vector2:
	var feeding := _feeding_frame >= 0
	# Directional walking is not mirrored art. Use the wrist from the exact
	# displayed pose, including a brief blocked pose, rather than legacy anchors
	# from a different camera angle or an eight-frame index wrapped twice.
	if not feeding and not seated and _heading_set.has("idle_hand"):
		var grip: Vector2=_heading_set.idle_hand if _frame<0 else _heading_set.walk_hands[clampi(_frame,0,_heading_set.walk_hands.size()-1)]
		return position+grip*Vector2(absf(scale.x),scale.y)
	# The public-action anchors are an independent eight-phase bank. An ordinary
	# 16/24/32-frame walk must sample them by cycle phase, not wrap its own index.
	var frame := ActivitySprites.release_frame() if release and feeding else _feeding_frame if feeding else MotionSprites.phase_frame(_cycle_phase,MotionSprites.WALK_FRAMES)
	var point := ActivitySprites.hand(identity,_view_back,walking,frame,feeding)
	var mirror := (1.0 if _view_back and not seated else -1.0) if _uses_approved_art else 1.0
	return position + point * Vector2(absf(scale.x)*facing*mirror,scale.y)

func _ready() -> void:
	# Trilinear on the node, mipmaps on the texture: both halves are needed, and
	# the project sets no default texture_filter at all, so canvas items were
	# minifying the baked sprites with nearest-neighbour on the mip level.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if not _is_painter:
		_try_bake()
	queue_redraw()

## Marks this instance as the baker's off-screen painter.
func set_painter_mode(on: bool) -> void:
	_is_painter = on

# ------------------------------------------------------------------ look

## The look table: slot -> a full appearance.
##
## Every axis is driven by a stride coprime with its palette size, so each entry
## of each palette is used a near-equal number of times, and no axis is a
## function of any other. The previous table ran all six axes off one
## `seed = slot * 7919` stream, which put 43% of the crowd on one hair style,
## 36% on one hair colour, and never selected two of the palette entries at all.
static func look_for_slot(slot: int) -> Dictionary:
	var s: int = posmod(slot, LOOK_COUNT)
	var tier: int = s / HAIR_STYLES        # which build band this slot sits in
	var demographic: Dictionary = Roster.visitor(s)
	return {
		"skin": SKIN_TONES[(s * 5) % SKIN_TONES.size()],
		"hair": Color("#B5AFA8") if demographic.age_group == "elder" else HAIR_COLORS[(s * 3) % HAIR_COLORS.size()],
		"shirt": SHIRT_COLORS[(s + 3 * tier) % SHIRT_COLORS.size()],
		"pants": PANTS_COLORS[(s + tier) % PANTS_COLORS.size()],
		"hair_style": s % HAIR_STYLES,
		"build": BUILDS[tier % BUILDS.size()],
		"is_staff": false,
		"uniform": Color("#C4703F"),
		"role": "visitor", "age_group": demographic.age_group, "gender": demographic.gender,
	}

## Adopt a specific look slot. The floor deals slots rather than rolling them:
## with 24 slots and twenty people on screen, independent random picks put three
## visitors in the same face by the birthday paradox alone.
func set_look_slot(slot: int) -> void:
	if actor_role not in ["", "visitor"]:
		return
	actor_role = "visitor"
	identity = Roster.visitor(slot)
	_look_slot = posmod(slot, LOOK_COUNT)
	apply_look(look_for_slot(_look_slot))
	_look_key = "v%d" % _look_slot
	_try_bake()
	queue_redraw()

## Which look slot this figure wears, or -1 for staff and unassigned figures.
func age_scale() -> float:
	if identity.get("age_group", "") != "child":return 1.0
	# The approved child mesh is already shorter; avoid applying the old full reduction twice.
	return 0.90 if _approved_seated != null else 0.74

func look_slot() -> int:
	return _look_slot

## Deterministic look from a seed, quantised to one of LOOK_COUNT slots.
func randomize_look(rng_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	set_look_slot(rng.randi() % LOOK_COUNT)

## Staff read by uniform hue first, so the variant only moves skin, hair colour,
## hair style and stature. Variants are capped at STAFF_LOOK_COUNT so a room full
## of staff costs a bounded number of bake slots; without it the five tellers
## behind the counters were one person copy-pasted five times.
func set_uniform(dept_color: Color, variant: int = 0, role: String = "employee") -> void:
	var staff_identity: Dictionary = Roster.employee(role, variant)
	if staff_identity.is_empty() or actor_role not in ["", role]:
		return
	actor_role = role
	identity = staff_identity
	var v: int = posmod(variant, STAFF_LOOK_COUNT)
	is_staff = true
	uniform_color = dept_color
	_shirt = dept_color
	_pants = dept_color.darkened(0.45)
	_skin = SKIN_TONES[(v * 2 + 1) % SKIN_TONES.size()]
	_hair = HAIR_COLORS[(v * 3) % HAIR_COLORS.size()]
	_hair_style = STAFF_STYLES[v % STAFF_STYLES.size()]
	_build = BUILDS[(v + 1) % BUILDS.size()]
	_look_slot = -1
	_look_key = "s%s_%d" % [dept_color.to_html(false), v]
	_try_bake()
	queue_redraw()

## Bake-cache key for this figure's appearance. Two characters sharing a key are
## the same person on screen.
func look_key() -> String:
	return _look_key

## Serialise the current look so the baker can rebuild it on its painter.
func current_look() -> Dictionary:
	return {
		"skin": _skin, "hair": _hair, "shirt": _shirt, "pants": _pants,
		"hair_style": _hair_style, "build": _build,
		"is_staff": is_staff, "uniform": uniform_color,
		"role": actor_role, "age_group": identity.get("age_group", "middle_aged"),
		"gender": identity.get("gender", "male"),
	}

func apply_look(look: Dictionary) -> void:
	# Baker painters consume both pools; live actors cannot change roles via appearance.
	if not _is_painter and actor_role != "":
		if bool(look.get("is_staff", false)) != (actor_role != "visitor"):
			return
	_skin = look.get("skin", _skin)
	_hair = look.get("hair", _hair)
	_shirt = look.get("shirt", _shirt)
	_pants = look.get("pants", _pants)
	_hair_style = int(look.get("hair_style", 0))
	_build = float(look.get("build", 1.0))
	is_staff = bool(look.get("is_staff", false))
	uniform_color = look.get("uniform", uniform_color)
	queue_redraw()

func _try_bake() -> void:
	set_bird_feeding(false)
	_feeding_frames.clear()
	if _seating_active:end_seating()
	else:_seating_frames.clear()
	if _is_painter or _look_key == "":
		return
	_approved_seated = null
	_uses_approved_art = false
	_motion_set = MotionSprites.get_set(identity)
	_heading_set = {} if with_cart else MotionSprites.direction_set(identity,_motion_heading)
	_cart_set = CartSprites.get_set(identity)
	if not _motion_set.is_empty():
		_frames = _motion_set.back if _view_back else _motion_set.front
		_approved_seated = _motion_set.get("seated", null)
		_uses_approved_art = true
		return
	_frames = Baker.frames_for(_look_key)
	if _frames.is_empty():
		Baker.request(_look_key, current_look(), self)

# ------------------------------------------------------------------ tick

## Cadence is expressed in complete left/right cycles per second. Deriving speed
## from the rig stride prevents short children taking the same giant steps as adults.
func walk_cadence() -> float:
	var base: float={"child":1.70,"young_adult":1.45,"middle_aged":1.35,"elder":1.20}.get(str(identity.get("age_group","young_adult")),1.45)
	return base+float(int(identity.get("variant",0))-1)*.04

func preferred_walk_speed(cadence: float = -1.0) -> float:
	return motion_stride() * age_scale() * (walk_cadence() if cadence<0 else cadence)

## Pushing has its own planted-foot animation; a walking-art update must not
## change cart speed or make the porter's feet slide against the handle rig.
func motion_stride() -> float:
	return float(_motion_set.get("cart_stride_grid" if with_cart else "stride_grid",.63))

func set_motion_vector(grid_delta: Vector2, speed: float) -> void:
	if grid_delta.length_squared() < 0.00000001:return
	var heading:=MotionSprites.direction_index(grid_delta,_motion_heading,
		HEADING_HYSTERESIS if not with_cart and speed>0.0 else 0.0)
	if heading!=_motion_heading:
		_motion_heading=heading
		_heading_set={} if with_cart else MotionSprites.direction_set(identity,heading)
		queue_redraw()
	_cart_heading=grid_delta.normalized();_cart_turn={};_cart_turn_frames=[]
	var projected := Vector2((grid_delta.x-grid_delta.y)*30.0,(grid_delta.x+grid_delta.y)*20.0)
	if absf(projected.x)>0.0001:facing=1 if projected.x>0 else -1
	var back := _view_back
	if absf(projected.y)>0.0001:back=projected.y<0
	if back!=_view_back:
		_view_back=back
		if not _motion_set.is_empty():_frames=_motion_set.back if back else _motion_set.front
		queue_redraw()
	_cycle_rate=maxf(speed/maxf(preferred_walk_speed(1.0),.01),0.0)
	if with_cart:queue_redraw()

## The floor supplies actual turn progress; rendering never advances it itself.
## Load an arc when it begins, never from _draw. Ordinary movement clears it.
func set_cart_turn(start: Vector2,end: Vector2,progress: float) -> void:
	var t:=clampf(progress,0,1)
	walking=false;walk_backwards=false
	set_motion_vector(start.rotated(start.angle_to(end)*t),0.0)
	var first:=CartSprites.Steering.direction_index(start)
	var last:=CartSprites.Steering.direction_index(end)
	var direction:=1 if posmod(last-first,4)==1 else -1
	if t>0.0 and t<1.0:
		_cart_turn_frames=CartSprites.Steering.turn_frames(identity,first,direction,carry_stack>0)
	_cart_turn={"start":first,"end":last,"frame":roundi(t*CartSprites.Steering.turn_intervals())}
	queue_redraw()

func _steering_texture() -> Texture2D:
	var packet: Dictionary=_cart_set["1" if carry_stack>0 else "0"]
	var view:=CartSprites.Steering.direction_index(_cart_heading)
	if not _cart_turn.is_empty():
		var frame: int=_cart_turn.frame
		var intervals := CartSprites.Steering.turn_intervals()
		if frame>0 and frame<intervals and _cart_turn_frames.size()==intervals-1:return _cart_turn_frames[frame-1]
		view=int(_cart_turn.start if frame==0 else _cart_turn.end)
		return packet[str(view)].idle
	var section: Dictionary=packet[str(view)]
	return section.walk[clampi(_frame,0,section.walk.size()-1)] if walking else section.idle

## Live movers submit the distance they actually travelled, including shortened
## steps at corners. Rendering cannot add footsteps while the actor is blocked,
## paused, or after a simulation catch-up. Timed previews retain their old API.
func record_motion(grid_delta: Vector2, seconds: float, look: Vector2 = Vector2.ZERO) -> void:
	_distance_driven=true
	var distance:=grid_delta.length()
	if distance<=0.000001:return
	set_motion_vector(look if not look.is_zero_approx() else grid_delta,
		distance/maxf(seconds,.000001))
	var stride:=motion_stride()*maxf(absf(scale.y),.01)
	_cycle_phase=fposmod(_cycle_phase+distance/stride*(-1.0 if walk_backwards else 1.0),1.0)
	# A final short segment may stop before _process runs. Select its travelled
	# pose now, so stop debounce retains that pose instead of the previous frame.
	if not _motion_set.is_empty():_sync_motion_frame()

func _walk_frame_count() -> int:
	if with_cart:return int(_cart_set.get("walk_frames",MotionSprites.WALK_FRAMES))
	if not _heading_set.is_empty():return _heading_set.walk.size()
	return _frames.size() if not _frames.is_empty() else MotionSprites.WALK_FRAMES

func _sync_motion_frame() -> void:
	var next_frame:=MotionSprites.phase_frame(_cycle_phase,_walk_frame_count())
	if next_frame!=_frame:
		_frame=next_frame
		queue_redraw()

func _process(delta: float) -> void:
	var mirror := (1.0 if _view_back and (not seated or _seating_active) else -1.0) if _uses_approved_art else 1.0
	scale.x = absf(scale.x) * float(facing) * mirror
	if _frames.is_empty() and not _is_painter and _look_key != "":
		_frames = Baker.frames_for(_look_key)
		if not _frames.is_empty():queue_redraw()
	if not walking:
		if _can_debounce_locomotion() and _frame >= 0:
			_stop_elapsed += delta
			if _stop_elapsed >= STOP_DEBOUNCE:
				_frame = -1
				_bob_t = 0.0
				queue_redraw()
		else:
			if _frame != -1:
				_frame = -1
				_bob_t = 0.0
				queue_redraw()
		return
	_bob_t += delta
	var f: int
	if not _motion_set.is_empty():
		if not _distance_driven:
			_cycle_phase=fposmod(_cycle_phase+delta*_cycle_rate*(-1.0 if walk_backwards else 1.0),1.0)
		f=MotionSprites.phase_frame(_cycle_phase,_walk_frame_count())
	else:f=int(_bob_t*WALK_FPS)%Baker.FRAMES
	if f != _frame:
		_frame=f;queue_redraw()

func _can_debounce_locomotion() -> bool:
	return not with_cart and not seated and not _seating_active \
		and _feeding_frame < 0 and not _motion_set.is_empty()

# ------------------------------------------------------------------ draw

func _draw() -> void:
	_draw_manager_aura()
	if seated and _seating_active and _seating_frames.size()==SeatingSprites.frame_count()*2:
		var frame := roundi(_seating_progress*(SeatingSprites.frame_count()-1))
		if _view_back:frame+=SeatingSprites.frame_count()
		# Keep the support contact in world space while the sprite itself mirrors.
		var offset := _seating_ground_offset+Vector2(0,SeatingSprites.SEAT_HEIGHT*scale.y-_seating_height)
		offset/=scale
		draw_texture_rect(_seating_frames[frame],Rect2(MotionSprites.DRAW_RECT.position+offset,MotionSprites.DRAW_RECT.size),false)
		_draw_reaction()
		return
	if _feeding_frame >= 0 and not seated and not walking:
		draw_texture_rect(_feeding_frames[_feeding_frame],MotionSprites.DRAW_RECT,false)
		_draw_reaction()
		return
	# Seating takes priority over ordinary standing/walking art.
	if seated and _approved_seated != null and not _is_painter:
		draw_texture_rect(_approved_seated, MotionSprites.seated_draw_rect(_approved_seated), false)
		_draw_reaction()
		return
	if seated:
		draw_set_transform(Vector2(0.0, -SEAT_LIFT))
		_draw_figure()
		draw_set_transform(Vector2.ZERO)
		_draw_reaction()
		return
	# Sprite path: one quad, supersampled offline.
	if not _is_painter and not _frames.is_empty():
		if with_cart and not _cart_set.is_empty():
			if bool(_cart_set.get("steering",false)):
				# True yaw views already include their orientation. Cancel the
				# legacy actor reflection for this quad; retain its scale/anchor.
				draw_set_transform(Vector2.ZERO,0.0,Vector2(-1 if scale.x<0 else 1,1))
				draw_texture_rect(_steering_texture(),CartSprites.Steering.DRAW_RECT,false)
				draw_set_transform(Vector2.ZERO)
				_draw_reaction()
				return
			var packet: Dictionary=_cart_set["1" if carry_stack>0 else "0"]
			var view:="back" if _view_back else "front"
			var cart_texture: Texture2D=packet[view][clampi(_frame,0,packet[view].size()-1)] if walking else packet["idle_"+view]
			# Body, hands and trolley share one native projection and depth pass.
			# Mirror once with the actor; the old independent prop flip is bypassed.
			draw_texture_rect(cart_texture,CartSprites.DRAW_RECT,false)
			_draw_reaction()
			return
		var tex: Texture2D = _motion_set["idle_back" if _view_back else "idle_front"] if _frame < 0 and not _motion_set.is_empty() else _frames[clampi(_frame, 0, _frames.size() - 1)]
		# The motion canvas includes extra foot clearance at the same pixel density.
		var draw_rect := MotionSprites.DRAW_RECT if not _motion_set.is_empty() else Rect2(-Baker.ANCHOR * 0.5, Vector2(Baker.SPRITE) * 0.5)
		# True yaw art already contains its orientation. Preserve the node
		# mirror for legacy seated/feeding/props, cancelling it for this quad.
		if not _heading_set.is_empty():
			tex=_heading_set.idle if _frame<0 else _heading_set.walk[clampi(_frame,0,_heading_set.walk.size()-1)]
			draw_set_transform(Vector2.ZERO,0.0,Vector2(-1 if scale.x<0 else 1,1))
		draw_texture_rect(tex, draw_rect, false)
		draw_set_transform(Vector2.ZERO)
		# Props stay live: only a handful of characters carry one, so they are
		# not worth multiplying the bake cache by.
		if _uses_approved_art:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(1 if _view_back else -1,1))
		if holding_sign:
			if _heading_set.has("idle_hand"):
				var grip: Vector2=_heading_set.idle_hand if _frame<0 else _heading_set.walk_hands[clampi(_frame,0,_heading_set.walk_hands.size()-1)]
				var reflection:=Vector2(-1 if scale.x<0 else 1,1)
				draw_set_transform((grip-Vector2(11,-20))*reflection,0.0,reflection)
			_draw_sign(0.0,12.0 if _heading_set.has("idle_hand") else 0.0)
		if with_cart:
			_draw_cart(0.0)
		draw_set_transform(Vector2.ZERO)
		_draw_reaction()
		return
	_draw_figure()
	_draw_reaction()

## Assigned managers should be visible in the venue without another speech
## bubble competing with visitor faces. A restrained floor halo plus a lapel
## gem communicates seniority; rank changes brightness and adds up to five rays.
func _draw_manager_aura() -> void:
	if manager_rank <= 0:
		return
	var strength := clampf(float(manager_rank) / 10.0, 0.1, 1.0)
	var glow := UI.BRASS.lightened(0.18 + strength * 0.18)
	glow.a = 0.18 + strength * 0.16
	draw_arc(Vector2(0.0, 1.0), 17.0 + strength * 2.5, 0.0, TAU, 24,
		Color(glow.r, glow.g, glow.b, glow.a * 0.45), 5.5)
	draw_arc(Vector2(0.0, 0.0), 15.5 + strength * 2.0, 0.0, TAU, 24, glow, 1.8)
	var rays: int = mini(5, 1 + manager_rank / 2)
	for i in rays:
		var angle := -PI + TAU * float(i) / float(rays)
		var ray_from := Vector2(cos(angle), sin(angle) * 0.45) * 19.0
		var ray_to := Vector2(cos(angle), sin(angle) * 0.45) * (22.0 + strength * 3.0)
		draw_line(ray_from, ray_to, glow, 1.5)
	draw_circle(Vector2(-5.6, -21.0), 3.1, UI.BRASS.darkened(0.2))
	draw_circle(Vector2(-5.6, -21.5), 2.0, glow.lightened(0.22))

func _draw_reaction() -> void:
	if reaction == "":
		return
	# Kept live above the baked character so temporary emotions do not multiply
	# the sprite-cache variants.
	if reaction == "angry" and _motion_set.is_empty():
		_draw_angry_face_overlay()
	var center := Vector2(0.0, -69.0)
	draw_circle(center, 12.0, Color(0.10, 0.06, 0.16, 0.30))
	draw_circle(center + Vector2(0.0, -1.5), 10.5, UI.PANEL)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-3.0, 8.0), center + Vector2(1.0, 15.0),
		center + Vector2(4.0, 7.0)]), UI.PANEL)
	if reaction == "angry":
		draw_line(center + Vector2(-5.0, -4.0), center + Vector2(-1.0, -2.0),
			UI.CARPET_RED.darkened(0.18), 2.0)
		draw_line(center + Vector2(5.0, -4.0), center + Vector2(1.0, -2.0),
			UI.CARPET_RED.darkened(0.18), 2.0)
		draw_arc(center + Vector2(0.0, 5.0), 4.5, 1.15 * PI, 1.85 * PI, 8,
			UI.CARPET_RED.darkened(0.30), 1.8)

## Replace the baked smile while an upset guest walks away. Emotions remain a
## live overlay so every visitor look—and every venue—shares the same state
## without multiplying the character bake cache.
func _draw_angry_face_overlay() -> void:
	var phase: float = TAU * float(_frame) / float(Baker.FRAMES)
	var moving: bool = walking and _frame > 0
	var bob: float = -absf(sin(phase)) * BOB_AMP if moving else 0.0
	var swing: float = sin(phase) * 3.6 if moving else 0.0
	var squash: float = 1.0 + (absf(sin(phase)) - 0.5) * SQUASH_AMP if moving else 1.0
	var hc := Vector2(swing * 0.16, HEAD_Y * squash + bob * 0.8)
	var mouth := hc + Vector2(FACE_CX + MOUTH_DX, 2.7)

	# Skin patch erases the baked smile and its antialiased fringe.
	draw_colored_polygon(_ellipse_poly(mouth, Vector2(4.0, 3.5), 16), _skin)
	# Brows lean down toward the nose; the mouth arc is the inverse of the
	# default smile. Both remain readable after the character is minified.
	var angry_ink := EYE_INK.darkened(0.08)
	for side in [-1.0, 1.0]:
		var eye := hc + Vector2(FACE_CX + EYE_DX * side, -0.8)
		draw_line(
			eye + Vector2(-2.0 * side, -3.5),
			eye + Vector2(1.4 * side, -2.0),
			angry_ink, 1.7, true)
	draw_arc(mouth + Vector2(0.0, 2.2), MOUTH_R + 0.4,
		1.16 * PI, 1.84 * PI, 10, angry_ink, 1.5, true)

## Full primitive draw. Runs inside the baker, and as the headless fallback.
func _draw_figure() -> void:
	var phase: float = 0.0
	if bake_pose >= 0:
		phase = TAU * float(bake_pose) / float(Baker.FRAMES)
	elif walking:
		phase = float(int(_bob_t * WALK_FPS)) / WALK_FPS * TAU * 2.2
	var moving: bool = not seated and (bake_pose > 0 or (bake_pose < 0 and walking))
	var bob: float = -absf(sin(phase)) * BOB_AMP if moving else 0.0
	# A sitter's torso settles ONTO the seat. Positive bob is downward here, so
	# this drops the body and head relative to the hips; without it the figure
	# keeps a standing spine and reads as hovering above the bench.
	if seated:
		bob = 5.4
	var swing: float = sin(phase) * 3.6 if moving else 0.0
	var squash: float = 1.0 + (absf(sin(phase)) - 0.5) * SQUASH_AMP if moving else 1.0
	var w: float = _build / squash
	var h: float = squash

	# A sitter's shadow belongs on the floor, not floating at seat height with the
	# rest of the figure, and the bench already casts its own. Skip it.
	if not seated:
		_draw_contact_shadow(squash)
	if seated:
		_draw_legs_seated(w)
	else:
		_draw_legs(bob, swing, w)
	_draw_arm(-1.0, bob, swing, w, h)      # far arm, behind the torso
	_draw_body(bob, w, h)
	_draw_head(bob, swing, w, h)
	_draw_arm(1.0, bob, swing, w, h)       # near arm, in front
	if holding_sign:
		_draw_sign(bob)
	if with_cart:
		_draw_cart(bob)

## Grounding shadow — three stacked ellipses fake a penumbra without a shader.
func _draw_contact_shadow(squash: float) -> void:
	var spread: float = 1.0 + (1.0 - squash) * 2.0
	paint_ellipse(Rect2(-11.0 * spread, -4.0, 22.0 * spread, 8.0), Color(0.20, 0.13, 0.06, 0.13))
	paint_ellipse(Rect2(-8.0 * spread, -3.0, 16.0 * spread, 6.0), Color(0.20, 0.13, 0.06, 0.16))
	paint_ellipse(Rect2(-5.0 * spread, -2.2, 10.0 * spread, 4.4), Color(0.20, 0.13, 0.06, 0.18))

## Legs for a sitter: SHINS ONLY, dropping from the seat to the floor.
##
## The first attempt drew a thigh as well and read as standing-but-ten-pixels-up,
## which is exactly what it was. At this fixed camera angle a sitter's thigh runs
## AWAY from the viewer and is hidden behind their own lap, so a thigh capsule
## cannot read as horizontal — it only makes the leg longer, which is the one
## thing that destroys the pose.
##
## What sells sitting at this size is the pair of short legs hanging off a seat
## with the shoes on the ground, plus the torso sunk onto the seat (see the bob in
## _draw_figure). The figure is already translated up by SEAT_LIFT, so the floor
## is at +SEAT_LIFT in this local space and the shins have exactly that to cover —
## which is why the seat height is one constant shared with the furniture painters
## instead of a number guessed per pose.
func _draw_legs_seated(w: float) -> void:
	var shoe := Color("#3B2E26")
	for side in [-1.0, 1.0]:
		var x: float = (2.7 * side - 2.5) * w
		# Starts at -5.0 so the thigh tucks UNDER the torso: _draw_body's lower edge
		# sits at about -4.8 once the sitting bob is applied, and legs begun below
		# that left a gap between body and knees that read as a floating figure.
		_shape(_capsule(Rect2(x, -5.0, 4.8 * w, SEAT_LIFT + 5.0)), _pants)
		# Inner shadow down the leg's far side, as standing legs get.
		draw_colored_polygon(
			_capsule(Rect2(x + 3.0 * w, -5.0, 1.6 * w, SEAT_LIFT + 5.0)),
			_pants.darkened(0.22))
		_shape(_capsule(Rect2(x - 0.5, SEAT_LIFT - 3.0, 5.6 * w, 3.6)), shoe)

func _draw_legs(bob: float, swing: float, w: float) -> void:
	var shoe := Color("#3B2E26")
	for side in [-1.0, 1.0]:
		var off: float = swing * 0.44 * side
		var x: float = (2.9 * side - 2.6) * w + off
		_shape(_capsule(Rect2(x, -10.0 + bob, 5.4 * w, 9.5)), _pants)
		# Inner shadow down the leg's far side.
		draw_colored_polygon(_capsule(Rect2(x + 3.4 * w, -10.0 + bob, 2.0 * w, 9.5)),
			_pants.darkened(0.22))
		_shape(_capsule(Rect2(x - 0.8, -3.6 + bob, 6.6 * w, 4.0)), shoe)
		draw_line(Vector2(x - 0.4, -2.6 + bob), Vector2(x + 5.4 * w, -2.6 + bob),
			shoe.lightened(0.28), 1.0)

func _draw_body(bob: float, w: float, h: float) -> void:
	var top: float = -25.0 * h + bob
	var bh: float = 17.0 * h
	var torso := PackedVector2Array([
		Vector2(-8.6 * w, top + bh), Vector2(-9.7 * w, top + bh * 0.34),
		Vector2(-8.0 * w, top), Vector2(8.0 * w, top),
		Vector2(9.7 * w, top + bh * 0.34), Vector2(8.6 * w, top + bh),
	])
	_shape(_round_poly(torso, 3.2), _shirt)
	# Waist occlusion.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-8.6 * w, top + bh), Vector2(8.6 * w, top + bh),
		Vector2(8.3 * w, top + bh * 0.60), Vector2(-8.3 * w, top + bh * 0.60),
	]), _shirt.darkened(0.17))
	# Shading down the right (away from the key light), rim light on the left.
	draw_colored_polygon(PackedVector2Array([
		Vector2(5.6 * w, top + 1.0), Vector2(8.4 * w, top + 2.0),
		Vector2(8.6 * w, top + bh), Vector2(5.6 * w, top + bh),
	]), _shirt.darkened(0.12))
	draw_line(Vector2(-7.2 * w, top + 3.0), Vector2(-7.9 * w, top + bh * 0.75),
		_shirt.lightened(0.30), 1.8)
	draw_line(Vector2(-6.0 * w, top + 1.5), Vector2(5.0 * w, top + 1.5),
		_shirt.lightened(0.24), 1.8)
	# Collar.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-3.4 * w, top - 0.4), Vector2(3.4 * w, top - 0.4),
		Vector2(2.2 * w, top + 3.2), Vector2(-2.2 * w, top + 3.2),
	]), _shirt.darkened(0.30))
	if is_staff:
		# Uniform sash + a brass button, so staff read instantly in a crowd.
		draw_line(Vector2(-6.6 * w, top + bh * 0.26), Vector2(6.6 * w, top + bh * 0.44),
			uniform_color.lightened(0.46), 2.4)
		draw_circle(Vector2(0.0, top + bh * 0.62), 1.5, UI.BRASS)

func _draw_arm(side: float, bob: float, swing: float, w: float, h: float) -> void:
	var top: float = -25.0 * h + bob
	# The torso reaches 9.7*w at the shoulder, so an arm at 8.3*w was swallowed
	# whole on the far side and every figure read one-armed with a floating hand.
	var x: float = (8.3 * w + 1.2) * side
	var lift: float = swing * 0.52 * side
	var sleeve := _shirt if side > 0.0 else _shirt.darkened(0.14)
	_shape(_capsule(Rect2(x - 2.5, top + 3.0 + lift, 5.0, 11.0)), sleeve)
	var hand := Vector2(x, top + 15.0 + lift)
	draw_circle(hand, 2.8, OUTLINE)
	draw_circle(hand, 2.2, _skin)
	draw_circle(hand + Vector2(-0.6, -0.7), 1.0, _skin.lightened(0.22))

func _draw_head(bob: float, swing: float, w: float, h: float) -> void:
	var hc := Vector2(swing * 0.16, HEAD_Y * h + bob * 0.8)
	# Build carries into the head at 45% strength. Full strength made the small
	# builds read as children, and none at all left every figure wearing the same
	# head — which is most of why the crowd looked stamped from one die.
	var r: float = HEAD_R * (1.0 + (_build - 1.0) * 0.45)
	_draw_hair_back(hc, r)
	draw_colored_polygon(_capsule(Rect2(hc.x - 2.8, hc.y + r - 3.6, 5.6, 6.4)),
		_skin.darkened(0.26))
	_shape(_ellipse_poly(hc, Vector2(r, r * 0.97), 26), _skin)
	# Occlusion under the chin, key light upper-left, narrow rim along the lit
	# edge — three tones is what gives a flat disc form at this size.
	draw_colored_polygon(_ellipse_poly(hc + Vector2(1.4, 3.8), Vector2(r * 0.82, r * 0.48), 18),
		_skin.darkened(0.14))
	draw_colored_polygon(_ellipse_poly(hc + Vector2(-3.2, -3.4), Vector2(r * 0.46, r * 0.42), 16),
		_skin.lightened(0.16))
	draw_arc(hc, r - 0.9, PI * 1.08, PI * 1.52, 10, _skin.lightened(0.32), 1.6)
	draw_circle(hc + Vector2(-r + 1.2, 1.0), 2.2, _skin.darkened(0.10))
	_draw_hair_front(hc, r)
	_draw_face(hc)
	if is_staff:
		_draw_cap(hc, r)

## Masses behind the skull. Drawn before the head so the head occludes their
## inner half: the outline changes, but no stroke lands on the face.
func _draw_hair_back(hc: Vector2, r: float) -> void:
	var k: float = r / HEAD_R
	var back := _hair.darkened(0.14)
	for e in HAIR_BACK[_hair_style]:
		_shape(_ellipse_poly(hc + Vector2(e[0], e[1]) * k, Vector2(e[2], e[3]) * k, 18), back)

func _draw_hair_front(hc: Vector2, r: float) -> void:
	var cap: Array = HAIR_CAP[_hair_style]
	var outer: float = r + float(cap[0])
	var thick: float = float(cap[1])
	var from_a: float = PI * float(cap[2])
	var to_a: float = TAU * float(cap[3])
	_shape(_crescent(hc, outer, from_a, to_a, thick), _hair)
	# Key light is upper-left, so the back of the sweep carries the shadow.
	draw_colored_polygon(_crescent(hc, outer, lerpf(from_a, to_a, 0.55), to_a, thick),
		_hair.darkened(0.26))
	var k: float = r / HEAD_R
	for e in HAIR_FRONT[_hair_style]:
		# Filled, never stroked. A 1.8px outline laid across a 21px head is a bar,
		# and the stroked lock this replaces ran vertically between the two eyes.
		draw_colored_polygon(_ellipse_poly(hc + Vector2(e[0], e[1]) * k,
			Vector2(e[2], e[3]) * k, 18), _hair)
		draw_colored_polygon(_ellipse_poly(hc + Vector2(e[0] - 1.2, e[1] + 1.2) * k,
			Vector2(e[2] * 0.34, e[3] * 0.42) * k, 12), _hair.darkened(0.26))
	# The highlight rides the middle of the crown band. It used to be two straight
	# lines across the top of the head, which at this size read as a bandage.
	draw_arc(hc, outer - thick * 0.34, lerpf(from_a, to_a, 0.17), lerpf(from_a, to_a, 0.41),
		12, _hair.lightened(0.26), 1.6)

## Faces +x; mirrored by scale.x when facing left.
func _draw_face(hc: Vector2) -> void:
	for side in [-1.0, 1.0]:
		var e := hc + Vector2(FACE_CX + EYE_DX * side, -0.8)
		# Brow shadow, iris, catchlight — a face this small still needs three parts.
		draw_colored_polygon(_ellipse_poly(e + Vector2(0, -2.3), BROW_R, 10),
			_skin.darkened(0.24))
		draw_colored_polygon(_ellipse_poly(e, EYE_R, 12), EYE_INK)
		draw_circle(e + Vector2(-0.45, -0.6), 0.62, Color(1, 1, 1, 0.92))
	draw_arc(hc + Vector2(FACE_CX + MOUTH_DX, 2.6), MOUTH_R, 0.18 * PI, 0.82 * PI, 10,
		EYE_INK, 1.3)
	draw_circle(hc + Vector2(FACE_CX + BLUSH_FAR.x, BLUSH_FAR.y), BLUSH_FAR.z,
		Color(0.92, 0.47, 0.42, 0.22))
	draw_circle(hc + Vector2(FACE_CX + BLUSH_NEAR.x, BLUSH_NEAR.y), BLUSH_NEAR.z,
		Color(0.92, 0.47, 0.42, 0.24))

func _draw_cap(hc: Vector2, r: float) -> void:
	var crown := uniform_color.darkened(0.08)
	var cc := hc + Vector2(0, -1.6)
	_shape(_crescent(cc, r + 1.0, PI * 1.01, TAU * 0.99, 6.6), crown)
	draw_colored_polygon(_crescent(cc, r + 1.0, PI * 1.42, TAU * 0.99, 6.6),
		uniform_color.darkened(0.30))
	# The peak clears the eyes by more than 2 design px and its lower edge carries
	# no stroke, so it can no longer fuse with them into a sunglasses bar.
	# Front-on, the brim is symmetric about the head and foreshortened, because a
	# peak pointing at the camera is short. In profile it keeps its authored
	# forward jut. Same wedge, two projections of it.
	var px: Vector2 = CAP_PEAK_X
	var py: Vector2 = CAP_PEAK_Y
	if portrait_mode:
		var half: float = (CAP_PEAK_X.y - CAP_PEAK_X.x) * 0.46
		px = Vector2(-half, half)
		py = Vector2(CAP_PEAK_Y.x + 0.5, CAP_PEAK_Y.y + 0.2)
	var peak := PackedVector2Array([
		Vector2(hc.x + px.x, hc.y + py.x + 0.6),
		Vector2(hc.x + px.y, hc.y + py.x),
		Vector2(hc.x + px.y, hc.y + py.y),
		Vector2(hc.x + px.x, hc.y + py.y - 0.4),
	])
	draw_colored_polygon(peak, uniform_color.darkened(0.34))
	# CLOSED outline. The open [0,1,2] path left the fourth edge undrawn, and at
	# portrait magnification that unterminated stroke reads as a square bracket
	# hanging off the end of the brim.
	draw_polyline(PackedVector2Array([peak[0], peak[1], peak[2], peak[3], peak[0]]),
		OUTLINE, OUTLINE_W)
	draw_circle(hc + Vector2(-1.4, -9.6), 1.6, UI.BRASS)

## Furthest any of a style's hair reaches from the head centre, in design px at
## the nominal head radius. The suite measures silhouette variety with this, and
## checks the tallest styles still fit inside the baked sprite.
static func hair_reach(style: int) -> float:
	var s: int = clampi(style, 0, HAIR_STYLES - 1)
	var best: float = HEAD_R + float(HAIR_CAP[s][0])
	for group in [HAIR_BACK[s], HAIR_FRONT[s]]:
		for e in group:
			var c := Vector2(e[0], e[1])
			for i in 32:
				var a: float = TAU * float(i) / 32.0
				best = maxf(best, (c + Vector2(cos(a) * float(e[2]), sin(a) * float(e[3]))).length())
	return best

## Axis-aligned bounds of a style's hair, in design px from the head centre. The
## crown is treated as a full circle, which is conservative. The suite uses this
## to prove the tall styles still fit above the baked sprite's anchor — hair that
## overruns the sprite is silently guillotined, not an error anyone would see.
static func hair_bounds(style: int) -> Rect2:
	var s: int = clampi(style, 0, HAIR_STYLES - 1)
	var outer: float = HEAD_R + float(HAIR_CAP[s][0])
	var box := Rect2(-outer, -outer, outer * 2.0, outer * 2.0)
	for group in [HAIR_BACK[s], HAIR_FRONT[s]]:
		for e in group:
			box = box.merge(Rect2(float(e[0]) - float(e[2]), float(e[1]) - float(e[3]),
				float(e[2]) * 2.0, float(e[3]) * 2.0))
	return box

## Horizontal span of every facial feature, in design px from the head centre.
static func face_extent() -> Vector2:
	var half: float = maxf(EYE_R.x, BROW_R.x)
	var lo: float = minf(minf(FACE_CX - EYE_DX - half, FACE_CX + MOUTH_DX - MOUTH_R),
		FACE_CX + BLUSH_FAR.x - BLUSH_FAR.z)
	var hi: float = maxf(maxf(FACE_CX + EYE_DX + half, FACE_CX + MOUTH_DX + MOUTH_R),
		FACE_CX + BLUSH_NEAR.x + BLUSH_NEAR.z)
	return Vector2(lo, hi)

## Museum exhibit board on a stick (promotions marketer).
func _draw_sign(bob: float, raise_by: float = 0.0) -> void:
	draw_line(Vector2(11, -44 + bob-raise_by), Vector2(11, -20 + bob), UI.WALL_BROWN, 3.0)
	var board := Rect2(1, -64 + bob-raise_by, 30, 20)
	_shape(_round_rect(board, 3.0), UI.PANEL)
	draw_circle(board.get_center() + Vector2(-7, -1), 3.6, UI.ROOM_PROMO)
	draw_line(board.get_center() + Vector2(-1, 3), board.get_center() + Vector2(11, 3),
		UI.ROOM_PROMO.darkened(0.1), 2.0)
	draw_line(board.get_center() + Vector2(-1, -3), board.get_center() + Vector2(8, -3),
		UI.ROOM_PROMO.darkened(0.1), 2.0)

## Wooden trolley + artifact crates (archive porter). Ours, not cash bags.
func _draw_cart(bob: float) -> void:
	var cx := 14.0
	_shape(_round_rect(Rect2(cx, -15 + bob, 21, 4.4), 1.6), UI.WALL_BROWN)
	draw_line(Vector2(cx + 1, -15 + bob), Vector2(cx - 6, -23 + bob), UI.WALL_BROWN, 2.4)
	for wheel_x in [cx + 4.0, cx + 17.0]:
		draw_circle(Vector2(wheel_x, -8.4 + bob), 3.8, OUTLINE)
		draw_circle(Vector2(wheel_x, -8.4 + bob), 1.5, UI.WALL_BROWN.lightened(0.3))
	for i in maxi(carry_stack, 1):
		var crate := Rect2(cx + 2.5, -26.4 + bob - float(i - 1) * 10.6, 16, 10.4)
		_shape(_round_rect(crate, 1.6), Color("#D6A868"))
		draw_line(crate.position + Vector2(1.4, 5.2), crate.position + Vector2(14.6, 5.2),
			Color("#A9793F"), 1.4)
		draw_line(crate.position + Vector2(0.8, 1.4), crate.position + Vector2(15.2, 1.4),
			Color("#EDC68F"), 1.2)

# ------------------------------------------------------------------ helpers

## Fill a polygon, then stroke its boundary. Strokes are not flagged antialiased:
## under the sprite path the supersampled downsample smooths them far better than
## the flag would, and AA geometry would only bloat the bake.
func _shape(poly: PackedVector2Array, fill: Color, outline: Color = OUTLINE) -> void:
	draw_colored_polygon(poly, fill)
	var ring := poly.duplicate()
	ring.append(poly[0])
	draw_polyline(ring, outline, OUTLINE_W)

func _ellipse_poly(center: Vector2, radii: Vector2, segments: int = 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return pts

func _capsule(rect: Rect2) -> PackedVector2Array:
	return _round_rect(rect, minf(rect.size.x, rect.size.y) * 0.5)

func _round_rect(rect: Rect2, radius: float, per_corner: int = 5) -> PackedVector2Array:
	var r: float = minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var pts := PackedVector2Array()
	var corners := [
		[Vector2(rect.position.x + rect.size.x - r, rect.position.y + rect.size.y - r), 0.0],
		[Vector2(rect.position.x + r, rect.position.y + rect.size.y - r), PI * 0.5],
		[Vector2(rect.position.x + r, rect.position.y + r), PI],
		[Vector2(rect.position.x + rect.size.x - r, rect.position.y + r), PI * 1.5],
	]
	for c in corners:
		var centre: Vector2 = c[0]
		var base: float = c[1]
		for i in per_corner + 1:
			var a: float = base + PI * 0.5 * float(i) / float(per_corner)
			pts.append(centre + Vector2(cos(a) * r, sin(a) * r))
	return pts

## Rounds a polygon by nudging each vertex toward its neighbours. The nudge is
## capped at 45% of the shorter adjacent edge: past half an edge the corner
## inverts, the polygon self-intersects, and Godot's triangulator rejects it.
func _round_poly(poly: PackedVector2Array, amount: float) -> PackedVector2Array:
	var n := poly.size()
	if n < 3:
		return poly
	var out := PackedVector2Array()
	for i in n:
		var prev: Vector2 = poly[(i - 1 + n) % n]
		var cur: Vector2 = poly[i]
		var next: Vector2 = poly[(i + 1) % n]
		var d_prev: float = prev.distance_to(cur)
		var d_next: float = next.distance_to(cur)
		if d_prev < 0.001 or d_next < 0.001:
			out.append(cur)
			continue
		out.append(cur + (prev - cur) / d_prev * minf(amount, d_prev * 0.45))
		out.append(cur + (next - cur) / d_next * minf(amount, d_next * 0.45))
	return out

## Hair crescent: an arc band whose inner edge tapers back out to meet the outer
## edge at both ends. A constant-thickness annulus closes with a radial end cap,
## and stroking that cap laid a dark bar diagonally across the cheek on every
## style whose sweep came past the horizontal.
func _crescent(center: Vector2, radius: float, from_a: float, to_a: float,
		depth: float, segments: int = 22) -> PackedVector2Array:
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in segments + 1:
		var t: float = float(i) / float(segments)
		var d := Vector2.RIGHT.rotated(lerpf(from_a, to_a, t))
		outer.append(center + d * radius)
		inner.append(center + d * (radius - depth * pow(sin(PI * t), 0.55)))
	inner.reverse()
	var pts := outer
	pts.append_array(inner)
	return pts

## Cheap filled ellipse. Named paint_ellipse, not draw_ellipse: Godot 4.5 added
## CanvasItem.draw_ellipse and the old name silently shadowed it.
func paint_ellipse(rect: Rect2, color: Color) -> void:
	draw_colored_polygon(_ellipse_poly(rect.get_center(),
		Vector2(rect.size.x * 0.5, rect.size.y * 0.5), 18), color)
