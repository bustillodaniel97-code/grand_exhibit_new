extends RefCounted
## Resumable construction of the exact pose envelope used for cart leases.
const Geometry:=preload("res://scenes/venue/floor/cart_traffic_geometry.gd")
var floor_node: Node
var porter: Variant
var steps: Array=[]
var poses: Array=[]
var offsets: Array=[0]
var index: Dictionary={}
var status:="idle"
var last_operations:=0
var step_cursor:=0
var sample_cursor:=0
var at:=Vector2.ZERO
var heading:=Vector2.RIGHT
var angle:=0.0
func begin(owner: Node,p: Variant,route: Array) -> void:
 floor_node=owner;porter=p;steps=route;poses=[];offsets=[0];index={}
 step_cursor=0;sample_cursor=0;at=p.pos;heading=Geometry.heading(p);angle=0.0;status="building"
 _append(at,heading)
func _append(point: Vector2,direction: Vector2) -> void:
 var pose:={"at":point,"heading":direction,"height":floor_node._porter_layout._height_at(point)}
 poses.append(pose)
 var cell:=Vector2i(floori(point.x),floori(point.y))
 if not index.has(cell):index[cell]=[]
 index[cell].append(pose)
func advance(max_operations: int,time_budget_usec: int) -> void:
 last_operations=0;var began:=Time.get_ticks_usec()
 while status=="building" and last_operations<maxi(0,max_operations):
  if time_budget_usec>0 and Time.get_ticks_usec()-began>=time_budget_usec:break
  if step_cursor>=steps.size():status="ready";break
  var step: Dictionary=steps[step_cursor]
  var samples:=32 if step.turn else 4
  sample_cursor+=1
  if step.turn:
   if sample_cursor==1:angle=heading.angle_to(step.heading)
   _append(at,heading.rotated(angle*sample_cursor/32.0))
  else:_append(at.lerp(step.at,sample_cursor/4.0),heading)
  last_operations+=1
  if sample_cursor>=samples:
   at=step.at;heading=step.heading;step_cursor+=1;sample_cursor=0
   offsets.append(poses.size()-1)
 if status=="building" and step_cursor>=steps.size():status="ready"
