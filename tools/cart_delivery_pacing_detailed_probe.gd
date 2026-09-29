extends SceneTree
const Geometry:=preload("res://scenes/venue/floor/cart_traffic_geometry.gd")
const TelemetryDispatch:=preload("res://tools/cart_dispatch_telemetry.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.get_node("SaveSystem").set_process(false)
	var gs: Node=root.get_node("GameState");gs.reset_to_new_game();gs.ready_flag=true;seed(918)
	var args:=OS.get_cmdline_user_args();var venue:=str(args[0]);gs.current_venue=venue
	for dept in ["ticket","archive","gallery","promotions"]:
		for track in ["staff","speed","value"]:gs.set_dept_level(venue,dept,track,8)
	var floor_node: Node=load("res://scenes/venue/floor/venue_floor.tscn").instantiate()
	floor_node._cart_dispatch=TelemetryDispatch.new()
	floor_node.set_size(Vector2(720,760));root.add_child(floor_node)
	for n in root.get_children():n.process_mode=Node.PROCESS_MODE_DISABLED
	floor_node._porter_planning_budget_usec=0
	floor_node.set_rates(root.get_node("Economy").venue_rates(venue))
	var timeline: Array=[]
	var duration:=float(args[2]) if args.size()>2 else 180.0
	var pairs:=0;var cart_hits:=0;var visitor_pairs:=0;var visitor_hits:=0
	var examples: Array=[];var buckets: Dictionary={};var prior: Dictionary={};var served:=0
	var porter_history: Dictionary={}
	var deliveries: Dictionary={}
	var first_delivery: Dictionary={};var loaded_since: Dictionary={};var longest_loaded: Dictionary={}
	var station_collections: Dictionary={};var station_deposits: Dictionary={}
	var pacing: Dictionary={};var sample_state: Dictionary={};var phase_dwell: Dictionary={}
	for i in floor_node._porters.size():
		var p: Variant=floor_node._porters[i]
		pacing[i]={"until_first":{},"loaded_until_first":{},"events":[]}
		phase_dwell[i]={}
		sample_state[i]={"at":p.pos,"heading":p.heading,"turn":p.turn_progress,"pedestrian_wait":p.pedestrian_wait,"carried":p.carried,"state":p.state}
	var initial_trips: int=floor_node._porter_trips
	for tick in int(duration/.05):
		floor_node.advance_sim(.05)
		for v in floor_node._visitors:
			var id: int=v.node.get_instance_id()
			if str(prior.get(id,""))=="queue" and v.state=="browse":served+=1
			prior[id]=v.state
		for i in floor_node._porters.size():
			var p: Variant=floor_node._porters[i]
			var before: Dictionary=sample_state[i]
			var category: String="service_wait"
			var moved: bool=p.pos.distance_to(before.at)>.00001 or absf(p.turn_progress-float(before.turn))>.00001 or not p.heading.is_equal_approx(before.heading)
			var req: Dictionary=floor_node._cart_dispatch._find(p)
			var dispatch_phase: String="lease" if floor_node._cart_dispatch.leases.has(p) else (str(req.get("phase","none")) if not req.is_empty() else "none")
			phase_dwell[i][dispatch_phase]=float(phase_dwell[i].get(dispatch_phase,0))+.05
			if moved:category="physical_travel"
			elif p.pedestrian_wait>float(before.pedestrian_wait) or p.pedestrian_wait>0:category="visitor_blocked"
			elif floor_node._cart_dispatch.holds.has(p) or p.state=="yielding":category="courtesy_hold"
			elif p.route_job!=null or not req.is_empty():category="planning_admission"
			elif p.state in ["collect","deposit"]:category="station_action"
			if not first_delivery.has(i):
				var all: Dictionary=pacing[i].until_first;all[category]=float(all.get(category,0))+.05
				if p.carried>0 or int(before.carried)>0:
					var loaded: Dictionary=pacing[i].loaded_until_first;loaded[category]=float(loaded.get(category,0))+.05
			if int(before.carried)==0 and p.carried>0:pacing[i].events.append({"seconds":tick*.05,"event":"loaded","station":p.window})
			if int(before.carried)>0 and p.carried==0:pacing[i].events.append({"seconds":tick*.05,"event":"unloaded","station":int(before.get("window",p.window))})
			sample_state[i]={"at":p.pos,"heading":p.heading,"turn":p.turn_progress,"pedestrian_wait":p.pedestrian_wait,"carried":p.carried,"state":p.state,"window":p.window}
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
		if tick%2!=0:continue
		for i in floor_node._porters.size():
			var p: Variant=floor_node._porters[i];var ph:=Geometry.heading(p)
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
	report["first_delivery_attribution"]=pacing
	report["dispatch_phase_dwell"]=phase_dwell
	report["dispatch_retry_reasons"]=floor_node._cart_dispatch.telemetry
	var file:=FileAccess.open(args[1],FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("CART_TRAFFIC ",venue," cart_hits=",cart_hits," visitor_hits=",visitor_hits," served=",served," deposits=",report.deposits);quit(0)
