extends RefCounted
## Stable station indices with independent positions and directions. Every
## visible and operational point derives from the same local desk coordinates.
const Exhibits := preload("res://scenes/venue/floor/exhibits.gd")
const MIN_WAITING_GAP := .64
var stations: Array[Dictionary] = []
var authored := false
var lane_offset := .62
var slot_count := 4
var slot_lead := .65
var slot_gap := .28
var tail_gap := .45

func configure(room: Rect2, queue: Dictionary, count: int, slots: int, tail: float, rooms: Dictionary = {}) -> void:
	stations.clear()
	slot_count = slots
	lane_offset = float(queue.get("lane_offset",.62))
	slot_lead = float(queue.get("slot_lead",1.0))
	slot_gap = float(queue.get("slot_gap",.55))
	# Keep the authored lane ends and circulation space, but admit only as many
	# full-size bodies as fit. Extra visitors wait in the lobby, not in each other.
	var span:=maxf(0.0,float(slots-1)*slot_gap)
	slot_count=mini(slots,1+int(floor(span/MIN_WAITING_GAP)))
	if slot_count>1:slot_gap=span/float(slot_count-1)
	tail_gap = tail
	var entries: Array = queue.get("stations",[])
	authored = not entries.is_empty()
	if authored and entries.size()!=count:
		push_error("Admission station count must match the saved station bank")
	var depth := float(queue.get("counter_gy",1.1))-float(queue.get("porter_lane_gy",float(queue.get("counter_gy",1.1))-1.35))
	for w in count:
		var entry: Dictionary = entries[w] if w<entries.size() else {}
		var room_id: String = entry.get("room","ticket")
		var station_room: Rect2 = rooms.get(room_id,{}).get("rect",room)
		var at := Exhibits.v2(entry.get("at"),Vector2(float(queue.get("first_gx",2.3))+w*float(queue.get("gx_step",2.5)),float(queue.get("counter_gy",1.1))))
		var front := Exhibits.v2(entry.get("front"),Vector2.DOWN)
		if front not in [Vector2.DOWN,Vector2.RIGHT,Vector2.UP,Vector2.LEFT]:
			push_error("Admission front must be a cardinal unit vector")
			front = Vector2.DOWN
		var right := Vector2(front.y,-front.x)
		var station := {"center":station_room.position+at,"room":room_id,"front":front,"right":right}
		station["porter"] = station_room.position+Exhibits.v2(entry.get("porter"),at+right*.62-front*depth)
		station["exit"] = station_room.position+Exhibits.v2(entry.get("exit"),at+right*(lane_offset+.34)+front*.72)
		stations.append(station)

func point(w: int, local: Vector2 = Vector2.ZERO) -> Vector2:
	return stations[w].center+stations[w].right*local.x+stations[w].front*local.y

func slot(w: int, index: int) -> Vector2:
	return point(w,Vector2(0,slot_lead+clampi(index,0,slot_count-1)*slot_gap))

func mouth(w: int) -> Vector2:
	return slot(w,slot_count-1)+stations[w].front*tail_gap

func rope(w: int, side: float, index: int) -> Vector2:
	return slot(w,index)+stations[w].right*side

func rotation_degrees(w: int) -> float:
	return rad_to_deg((stations[w].right as Vector2).angle())

func queue_bounds(w: int) -> Rect2:
	var a := slot(w,0)-Vector2(.5,.5)
	var b := slot(w,slot_count-1)+Vector2(.5,.5)
	return Rect2(a,Vector2.ZERO).expand(b).expand(slot(w,0)+Vector2(.5,.5)).expand(slot(w,slot_count-1)-Vector2(.5,.5))
