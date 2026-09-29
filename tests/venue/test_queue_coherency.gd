extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	if not ok:failures+=1;printerr("FAIL: ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.get_node("SaveSystem").set_process(false)
	var gs: Node=root.get_node("GameState");gs.reset_to_new_game();gs.ready_flag=true;seed(912)
	var floor_node: Node=load("res://scenes/venue/floor/venue_floor.tscn").instantiate()
	floor_node.set_size(Vector2(720,760));root.add_child(floor_node)
	for n in root.get_children():n.process_mode=Node.PROCESS_MODE_DISABLED
	var report: Array=[]
	for vid in root.get_node("DataLoader").venue_order():
		gs.current_venue=vid
		for dept in ["ticket","archive","gallery","promotions"]:
			for track in ["staff","speed","value"]:gs.set_dept_level(vid,dept,track,8)
		floor_node.retheme(vid);floor_node.set_rates(root.get_node("Economy").venue_rates(vid))
		var overlap:=0;var pairs:=0;var service_in_motion:=0;var bad_claims:=0;var lobby_collisions:=0;var served:=0
		var prior: Dictionary={};var peak:=0;var min_gap:=100.0
		var by_station: Dictionary={};var progress: Dictionary={};var stalled:=0
		var stall_seen: Dictionary={};var stall_samples: Array=[]
		for step in 3600:
			floor_node.advance_sim(.05)
			peak=maxi(peak,floor_node.get_queue_occupancy())
			for v in floor_node._visitors:
				var id: int=v.node.get_instance_id()
				var previous: Dictionary=prior.get(id,{})
				if previous.get("state","")=="queue" and v.state=="browse":
					served+=1;by_station[previous.window]=int(by_station.get(previous.window,0))+1
				prior[id]={"state":v.state,"window":v.window}
				var last: Dictionary=progress.get(id,{"pos":v.pos,"time":step*.05,"state":v.state})
				if last.state!=v.state or v.pos.distance_to(last.pos)>.03:last={"pos":v.pos,"time":step*.05,"state":v.state}
				progress[id]=last
				if v.state in ["to_queue","to_queue_entry"] and step*.05-float(last.time)>30:
					stalled+=1
					if not stall_seen.has(id):
						stall_seen[id]=true
						var peers: Array=[]
						for peer in floor_node._queues[v.window]:peers.append({"state":peer.state,"pos":str(peer.pos),"target":str(peer.target),"path":str(peer.path),"entered":peer.queue_entered})
						var nearby: Array=[]
						for other in floor_node._visitors:
							if other!=v and other.pos.distance_to(v.pos)<1.5:nearby.append({"state":other.state,"pos":str(other.pos),"target":str(other.target),"window":other.window,"departing_window":other.departing_window,"seated":other.node.seated})
						var next: Vector2=v.path[0] if not v.path.is_empty() else v.target
						stall_samples.append({"nearby":nearby,"waiting_to_cross":floor_node._waiting_to_cross(v.pos,next),"step":step,"state":v.state,"window":v.window,"pos":str(v.pos),"target":str(v.target),"path":str(v.path),"peers":peers,"speed":v.speed})
			for q in floor_node._queues:
				if q.size()>floor_node._slots_per_window:bad_claims+=1
				for i in q.size():
					var v=q[i]
					if v.state=="arriving":bad_claims+=1
					if v.state=="queue" and (v.pos.distance_to(v.target)>.03 or not v.path.is_empty()):service_in_motion+=1
					if not v.queue_entered:continue
					for j in range(i+1,q.size()):
						if not q[j].queue_entered:continue
						var gap: float=v.pos.distance_to(q[j].pos);pairs+=1;min_gap=minf(min_gap,gap)
						if gap<.59:overlap+=1
			for i in floor_node._crowd.size():
				for j in range(i+1,floor_node._crowd.size()):
					if floor_node._crowd[i].target.distance_to(floor_node._crowd[j].target)<.63:lobby_collisions+=1
		check(stalled==0,vid+" admission walkers make progress without a 30-second stall")
		for w in floor_node._windows_active:check(int(by_station.get(w,0))>0,vid+" station "+str(w)+" actually serves guests")
		check(overlap==0,vid+" waiting bodies remain separated")
		check(bad_claims==0,vid+" no outdoor queue reservations or excess lane occupancy")
		check(service_in_motion==0,vid+" only stationary guests are marked ready for service")
		check(lobby_collisions==0,vid+" lobby waiting destinations are exclusive")
		check(served>0 and floor_node._porter_trips>0,vid+" arrivals receive service and money reaches the archive")
		report.append({"venue":vid,"slots_per_lane":floor_node._slots_per_window,"gap":floor_node._admissions.slot_gap,"pairs":pairs,"overlaps":overlap,"smallest_gap":min_gap,"served":served,"served_by_station":by_station,"stalled_steps":stalled,"stall_samples":stall_samples,"trips":floor_node._porter_trips,"peak_waiting":peak,"service_in_motion":service_in_motion,"bad_claims":bad_claims,"lobby_conflicts":lobby_collisions})
		print("QUEUE_COHERENCY ",vid," served=",served," overlaps=",overlap)
	var out:=OS.get_environment("QUEUE_REPORT")
	if not out.is_empty():
		var f:=FileAccess.open(out,FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close()
	print("Queue coherency failures: ",failures)
	quit(1 if failures else 0)
