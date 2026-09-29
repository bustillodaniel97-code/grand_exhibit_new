extends SceneTree
const Geometry:=preload("res://scenes/venue/floor/cart_traffic_geometry.gd")
const ProbeDispatch:=preload("res://tools/cart_dispatch_segmented_pelagic_qa.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var wall_started:=Time.get_ticks_usec()
	root.get_node("SaveSystem").set_process(false)
	var args:=OS.get_cmdline_user_args();var selected_seed:=int(args[3]) if args.size()>3 else 918;var budget:=int(args[4]) if args.size()>4 else 1500
	var gs: Node=root.get_node("GameState");gs.reset_to_new_game();gs.ready_flag=true;seed(selected_seed)
	var venue:=str(args[0]);gs.current_venue=venue
	for dept in ["ticket","archive","gallery","promotions"]:
		for track in ["staff","speed","value"]:gs.set_dept_level(venue,dept,track,8)
	var floor_node: Node=load("res://scenes/venue/floor/venue_floor.tscn").instantiate()
	floor_node._cart_dispatch=ProbeDispatch.new()
	floor_node.set_size(Vector2(720,760));root.add_child(floor_node)
	for n in root.get_children():n.process_mode=Node.PROCESS_MODE_DISABLED
	floor_node._porter_planning_budget_usec=budget
	floor_node.set_rates(root.get_node("Economy").venue_rates(venue))
	var timeline: Array=[]
	var duration:=float(args[2]) if args.size()>2 else 180.0
	var pairs:=0;var cart_hits:=0;var visitor_pairs:=0;var visitor_hits:=0
	var examples: Array=[];var buckets: Dictionary={};var prior: Dictionary={};var served:=0
	var porter_history: Dictionary={}
	var deliveries: Dictionary={}
	var first_delivery: Dictionary={};var loaded_since: Dictionary={};var longest_loaded: Dictionary={}
	var station_collections: Dictionary={};var station_deposits: Dictionary={}
	var travel: Dictionary={};var lease_seen: Dictionary={};var route_events:Array=[];var hold_events:Array=[];var hold_seen:Dictionary={};var blocked_regions:Dictionary={}
	for i in floor_node._porters.size():travel[i]={"pickup":0.0,"return":0.0,"refuge":0.0,"other":0.0}
	var initial_trips: int=floor_node._porter_trips
	for tick in int(duration/.05):
		var before_pos:Array=[];var before_wait:Array=[]
		for p in floor_node._porters:before_pos.append(p.pos);before_wait.append(p.pedestrian_wait)
		floor_node.advance_sim(.05)
		for v in floor_node._visitors:
			var id: int=v.node.get_instance_id()
			if str(prior.get(id,""))=="queue" and v.state=="browse":served+=1
			prior[id]=v.state
		for i in floor_node._porters.size():
			var p: Variant=floor_node._porters[i]
			var distance:float=p.pos.distance_to(before_pos[i]);var kind:="refuge" if p.state=="yielding" else ("return" if p.state=="to_vault" else ("pickup" if p.state=="to_window" else "other"));travel[i][kind]=float(travel[i][kind])+distance
			if p.pedestrian_wait>float(before_wait[i]) and not p.route_steps.is_empty() and p.route_cursor<p.route_steps.size():
				var cell:=Vector2i(roundi(p.pos.x*4),roundi(p.pos.y*4));var key:=str(cell);blocked_regions[key]=int(blocked_regions.get(key,0))+1
			var old: Dictionary=porter_history.get(i,{"at":p.pos,"state":p.state,"moved":tick*.05})
			if p.carried>0 and not loaded_since.has(i):
				loaded_since[i]=tick*.05
				station_collections[p.window]=int(station_collections.get(p.window,0))+1
			if loaded_since.has(i):longest_loaded[i]=maxf(float(longest_loaded.get(i,0)),tick*.05-float(loaded_since[i]))
			if str(old.state)=="deposit" and p.state!="deposit":
				deliveries[i]=int(deliveries.get(i,0))+1
				if not first_delivery.has(i):first_delivery[i]=tick*.05
				station_deposits[p.window]=int(station_deposits.get(p.window,0))+1
				loaded_since.erase(i)
			if p.pos.distance_to(old.at)>.02 or str(old.state)!=p.state:old={"at":p.pos,"state":p.state,"moved":tick*.05}
			porter_history[i]=old
		if tick%200==0:
			var jobs: Array=[]
			for request in floor_node._cart_dispatch.requests:
				jobs.append({"porter":floor_node._porters.find(request.p),"phase":request.phase,"tried":request.tried,"age":request.sequence,"ticket":request.get("schedule_ticket",-1),"intent_poses":request.get("envelope",[]).size(),"expanded":request.p.route_job.expanded if request.p.route_job!=null else 0})
			var reservations: Array=[];var holds: Array=[]
			for owner in floor_node._cart_dispatch.leases:
				var data: Dictionary=floor_node._cart_dispatch.lease_data.get(owner,{})
				reservations.append({"porter":floor_node._porters.find(owner),"age":data.get("sequence",-1),"released":data.get("released",0),"state":owner.state,"at":str(owner.pos)})
			for owner in floor_node._cart_dispatch.holds:
				var hold: Dictionary=floor_node._cart_dispatch.holds[owner]
				holds.append({"porter":floor_node._porters.find(owner),"winner":floor_node._porters.find(hold.winner),"arrived":hold.arrived,"saved_state":hold.state})
			timeline.append({"seconds":tick*.05,"revision":floor_node._cart_dispatch.revision,"leases":floor_node._cart_dispatch.leases.size(),"reservations":reservations,"holds":holds,"jobs":jobs,"deposits":floor_node._porter_trips-initial_trips})
		for owner in floor_node._cart_dispatch.leases:
			var data:Dictionary=floor_node._cart_dispatch.lease_data.get(owner,{});var sig:="%s/%s"%[data.get("sequence",-1),owner.route_steps.size()]
			if lease_seen.get(owner,"")!=sig:
				lease_seen[owner]=sig;var length:=0.0;var cursor:Vector2=owner.pos;var turns:=0
				for step in owner.route_steps:
					if step.turn:turns+=1
					else:length+=cursor.distance_to(step.at)
					cursor=step.at
				route_events.append({"seconds":tick*.05,"porter":floor_node._porters.find(owner),"state":owner.state,"station":owner.window,"from":str(owner.pos),"to":str(owner.dock.get("at",owner.target)),"distance":length,"turns":turns,"steps":owner.route_steps.size(),"age":data.get("sequence",-1)})
		for held in floor_node._cart_dispatch.holds:
			var h:Dictionary=floor_node._cart_dispatch.holds[held];var sig:="%s/%s"%[floor_node._porters.find(h.winner),h.arrived]
			if hold_seen.get(held,"")!=sig:hold_seen[held]=sig;hold_events.append({"seconds":tick*.05,"porter":floor_node._porters.find(held),"winner":floor_node._porters.find(h.winner),"arrived":h.arrived,"saved_state":h.state,"at":str(held.pos)})
		for held in hold_seen.keys():
			if not floor_node._cart_dispatch.holds.has(held):hold_events.append({"seconds":tick*.05,"porter":floor_node._porters.find(held),"event":"released","at":str(held.pos)});hold_seen.erase(held)
		if tick%2!=0:continue
		for i in floor_node._porters.size():
			var p: Variant=floor_node._porters[i];var ph:=Geometry.heading(p)
			if tick>=4800 and tick<=5200:
				for v in floor_node._visitors+floor_node._rejected:
					if Geometry.point_distance(v.pos,p.pos,ph)<.6:
						examples.append({"seconds":tick*.05,"kind":"contact_trace","porter":i,"cart_at":str(p.pos),"cart_heading":str(ph),"cart_height":floor_node._porter_layout._height_at(p.pos),"cart_state":p.state,"motion_step":str(p.motion_step),"route_cursor":p.route_cursor,"route_size":p.route_steps.size(),"leased":floor_node._cart_dispatch.leases.has(p),"visitor_at":str(v.pos),"visitor_height":floor_node._porter_layout._height_at(v.pos),"visitor_state":v.state,"visitor_walking":v.node.walking,"visitor_cart_wait":v.cart_wait,"visitor_path0":str(v.path[0]) if not v.path.is_empty() else "none","distance":Geometry.point_distance(v.pos,p.pos,ph)})
			var height: float=floor_node._theme.lift_at(p.pos)
			for j in range(i+1,floor_node._porters.size()):
				var other: Variant=floor_node._porters[j]
				if absf(height-floor_node._theme.lift_at(other.pos))>=73.0:continue
				pairs+=1
				if Geometry.overlap(p.pos,ph,other.pos,Geometry.heading(other)):
					cart_hits+=1
					if examples.size()<12:examples.append({"seconds":tick*.05,"kind":"cart_cart","a":str(p.pos),"b":str(other.pos),"states":[p.state,other.state],"headings":[str(ph),str(Geometry.heading(other))]})
			for v in floor_node._visitors+floor_node._rejected:
				if absf(height-floor_node._theme.lift_at(v.pos))>=73.0:continue
				visitor_pairs+=1
				if Geometry.point_distance(v.pos,p.pos,ph)<Geometry.VISITOR_RADIUS:
					visitor_hits+=1
					var key:="%s/%s"%[p.state,v.state];buckets[key]=int(buckets.get(key,0))+1
					if examples.size()<24:examples.append({"seconds":tick*.05,"kind":"cart_visitor","cart":str(p.pos),"visitor":str(v.pos),"states":[p.state,v.state],"heading":str(ph),"visitor_target":str(v.target)})
	var final_porters: Array=[]
	for i in floor_node._porters.size():
		var p: Variant=floor_node._porters[i]
		final_porters.append({"index":i,"at":str(p.pos),"heading":str(p.heading),"target":str(p.target),"state":p.state,"job":p.route_job.status if p.route_job!=null else "none","stationary_seconds":duration-float(porter_history.get(i,{"moved":duration}).moved),"deliveries":int(deliveries.get(i,0)),"first_delivery_seconds":first_delivery.get(i,null),"longest_loaded_seconds":longest_loaded.get(i,0),"current_loaded_seconds":duration-float(loaded_since[i]) if loaded_since.has(i) else 0.0,"carried":p.carried,"remaining_steps":p.route_steps.size()-p.route_cursor})
	var blockers: Array=[]
	for i in floor_node._porters.size():
		var p: Variant=floor_node._porters[i]
		for v in floor_node._visitors+floor_node._rejected:
			if p.pos.distance_to(v.pos)<2.0:
				blockers.append({"porter":i,"at":str(v.pos),"state":v.state,"target":str(v.target),"path_size":v.path.size(),"walking":v.node.walking,"cart_wait":v.cart_wait})
	var report:={"timeline":timeline,"nearby_guests":blockers,"crowd_detours":floor_node._crowd_traffic.detours,"dispatch_grants":floor_node._cart_dispatch.grants,"dispatch_relocations":floor_node._cart_dispatch.relocations,"peak_concurrent_routes":floor_node._cart_dispatch.peak_concurrent,"final_porters":final_porters,"venue":venue,"seconds":duration,"cart_pairs":pairs,"cart_overlap_samples":cart_hits,"visitor_pairs":visitor_pairs,"visitor_overlap_samples":visitor_hits,"visitor_states":buckets,"served":served,"deposits":floor_node._porter_trips-initial_trips,"examples":examples,"scope":"Ground-plane full cart rectangle against carts and .22-radius indoor/rejected visitor discs at matching elevation, sampled every .1s. Excludes independent plaza/city populations."}
	report["station_collections"]=station_collections;report["station_deposits"]=station_deposits
	report["travel_distance"]=travel;report["route_events"]=route_events;report["hold_events"]=hold_events;report["blocked_quarter_cells"]=blocked_regions
	report["wall_seconds"]=(Time.get_ticks_usec()-wall_started)/1000000.0
	report["dispatch_usec"]=floor_node._cart_dispatch.qa_advance_usec
	report["dispatch_calls"]=floor_node._cart_dispatch.qa_advance_calls
	report["segment_splits"]=floor_node._cart_dispatch.segment_splits
	report["segment_resumes"]=floor_node._cart_dispatch.segment_resumes
	report["provenance"]={"injected_dispatcher":"res://tools/cart_dispatch_segmented_pelagic_qa.gd","base_chain":"res://tools/cart_dispatch_timing_qa.gd -> res://scenes/venue/floor/cart_dispatch.gd","CART_LEASE_DEFER_QA":"unset","production_sha256":"c9feb81d54b2db0cec6c4e03f628adbf5b219cfac2d8a0946d98e67e41cebd81","seed":selected_seed,"seconds":duration,"planning_wall_budget_usec":budget}
	var file:=FileAccess.open(args[1],FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("CART_TRAFFIC ",venue," cart_hits=",cart_hits," visitor_hits=",visitor_hits," served=",served," deposits=",report.deposits);quit(0)
