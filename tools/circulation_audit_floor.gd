extends "res://scenes/venue/floor/venue_floor.gd"
## Test instrumentation only; every move still uses the production implementation.
var audit_step: Callable
func _move(v: Visitor, dt: float) -> bool:
 var before := v.pos
 var arrived := super._move(v,dt)
 if audit_step.is_valid() and before!=v.pos:audit_step.call("visitor",before,v.pos,v.state)
 return arrived
func _porter_move(p: Porter, dt: float) -> bool:
 var before := p.pos
 var arrived := super._porter_move(p,dt)
 if audit_step.is_valid() and before!=p.pos:audit_step.call("porter",before,p.pos,p.state)
 return arrived
