extends "res://scenes/venue/floor/cart_dispatch.gd"
## Passive QA timer. Probes run with wall budget zero, so observation cannot
## change the dispatch budget decision.
var qa_advance_calls:=0
var qa_advance_usec:=0
func advance(max_operations:int,time_budget_usec:int)->void:
 var began:=Time.get_ticks_usec();super.advance(max_operations,time_budget_usec)
 qa_advance_calls+=1;qa_advance_usec+=Time.get_ticks_usec()-began
