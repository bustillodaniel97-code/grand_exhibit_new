extends Node
## AdService — mediation-agnostic rewarded-video interface (AdMob plugs in later).
## Debug build: simulated ads that always succeed after a short delay unless
## context.simulate_failure == true. Set debug_ads=false for release exports.

signal ad_result(placement_id: String, success: bool, context: Dictionary)

var debug_ads: bool = true

func is_ready(_placement_id: String) -> bool:
	return true  # debug: always ready

func show_rewarded(placement_id: String, context: Dictionary = {}) -> void:
	if not debug_ads:
		# Real SDK call goes here. Until wired, fail gracefully.
		await get_tree().create_timer(0.2).timeout
		ad_result.emit(placement_id, false, context)
		return
	await get_tree().create_timer(0.4).timeout
	var success: bool = not bool(context.get("simulate_failure", false))
	ad_result.emit(placement_id, success, context)
