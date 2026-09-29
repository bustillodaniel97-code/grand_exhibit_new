extends RefCounted
## Pure manager progression curve. Kept free of autoload references so the
## event math can compile under standalone `-s` tests before globals resolve.

const MAX_RANK: int = 10
const LEVEL_CAPS: Array[int] = [20, 40, 60, 80, 100, 140, 180, 220, 260, 300]
const RANK_MULTS: Array[float] = [1.0, 1.3, 1.7, 2.2, 2.8, 3.6, 4.5, 5.6, 6.9, 8.5]
const CARD_COSTS: Array[int] = [2, 4, 8, 12, 18, 26, 38, 54, 76]

static func level_cap(rank: int) -> int:
	return LEVEL_CAPS[clampi(rank - 1, 0, LEVEL_CAPS.size() - 1)]

static func rank_cost(rank: int) -> int:
	if rank >= MAX_RANK:
		return 0
	return CARD_COSTS[clampi(rank - 1, 0, CARD_COSTS.size() - 1)]

static func productivity(def: Dictionary, state: Dictionary) -> float:
	var level: int = maxi(int(state.get("level", 1)), 1)
	var rank: int = clampi(int(state.get("rank", 1)), 1, MAX_RANK)
	return 1.0 + float(def.get("base_mult", 0.03)) * float(level) * RANK_MULTS[rank - 1]

static func audit_efficiency(def: Dictionary, state: Dictionary) -> float:
	var level: int = maxi(int(state.get("level", 1)), 1)
	var rank: int = clampi(int(state.get("rank", 1)), 1, MAX_RANK)
	return float(def.get("battle_power", 10.0)) * (1.0 + 0.12 * float(level - 1)) \
		* RANK_MULTS[rank - 1]
