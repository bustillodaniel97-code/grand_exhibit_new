extends "res://tools/cart_dispatch_timing_qa.gd"
## QA-only release-before-request segmentation. Never wired into production.
var segment_splits:=0
var segment_resumes:=0
var segmented:Dictionary={}
const EXITS:=[Vector2(4.25,6),Vector2(5.25,16.5)]
func configure(owner:Node)->void:
 super.configure(owner);segmented.clear();segment_splits=0;segment_resumes=0
func _admit(request:Dictionary,steps:Array)->void:
 if floor_node._theme.id=="pelagic_crown" and request.refuge_for==null and steps.size()>4:
  for i in steps.size()-1:
   if i<2 or not steps[i].at in EXITS or request.p.pos.distance_to(steps[i].at)<.3:continue
   # Stop only at a pose already in the accepted route. Release this lease on
   # arrival; the next route is a fresh admission, so no cart holds-and-waits.
   var prefix:Array=steps.slice(0,i+1)
   request.erase("admission_envelope");request.erase("admission_offsets")
   request.erase("envelope");request.erase("envelope_offsets")
   segmented[request.p]={"age":int(request.sequence),"suffix":steps.slice(i+1).duplicate(true)};segment_splits+=1
   super._admit(request,prefix);return
 super._admit(request,steps)
func _release_finished()->void:
 super._release_finished()
 for p in segmented.keys():
  if leases.has(p) or not p.motion_step.is_empty() or p.route_cursor<p.route_steps.size():continue
  var continuation:Dictionary=segmented[p];segmented.erase(p)
  if p.pos.distance_to(p.target)<.0001:continue
  segment_resumes+=1;enqueue(p,int(continuation.age))
  # Reuse the exact suffix that was already selected and admitted up to this
  # exit. Production still rebuilds its envelope, validates current occupancy,
  # and computes an alternate route when that suffix is blocked.
  var request:Dictionary=_find(p)
  request.intent=continuation.suffix
