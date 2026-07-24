# SPEC.md — GRAND EXHIBIT (single source of truth)

Godot 4.4, GDScript, portrait 720x1280, gl_compatibility. Target: Android first.
Every agent implements THIS spec faithfully. No unilateral interface changes.
All balance lives in `data/*.json`. No magic numbers in logic.

## 0. GLOSSARY / PILLARS
- Four departments per venue on one scrolling map: `promotions` (visitor arrival rate),
  `ticket` (service points/throughput), `archive` (cart earned cash to vault),
  `gallery` (bonus % per visitor). Income is min-of-department throughput (choke-point).
- Currencies: Cash (soft, BigNumber), Gems (hard, int), Insight (evolve, BigNumber),
  Manager Cards (per-manager int). Never convertible backward into premium.
- Reputation XP from every upgrade purchase; Rep level gates meta (managers @6,
  expedition @7, Inspection Frenzy @ Day 2 real-time, decor in first hour, prestige at
  venue milestone completion).
- Prestige: cash RETAINED, managers/insight/gems/decor persist, dept levels reset.
- Notation: K M B T then aa ab ac ... az ba ... ; log-space math internally.
- Visual zoning: each dept zone has distinct floor color + border + floating badge icon.

## 1. REPO MAP & FILE OWNERSHIP (merge-safety contract)
```
autoload/                 -> branch core  (Lead Engineer)
scripts/core/             -> branch core
tests/core/               -> branch core
data/balance_core.json    -> branch core
scenes/main.tscn, scenes/venue/, scenes/ui/, scripts/ui/  -> branch venue-ui
tests/venue/              -> branch venue-ui
scripts/managers/, scenes/managers/, data/managers.json, data/lootboxes.json, tests/managers/ -> branch managers
scripts/events/, scenes/events/, data/events.json, tests/events/  -> branch events
scripts/meta/, scenes/meta/, data/quests_milestones.json, data/decor.json, data/venues.json (fill v2-6), tests/meta/ -> branch meta
scripts/monetization/, scenes/store/, data/store_iap.json, data/offers.json, tests/monetization/ -> branch monetization
project.godot, docs/, data/balance_core.json skeleton, README, CREDITS, DESIGN_DECISIONS -> main agent ONLY
```
Cross-agent references ONLY via: autoload singletons (§3), EventBus signals (§4),
DataLoader lookups (§5), BigNumber class_name, and scene paths from the SCREEN REGISTRY (§11)
loaded at runtime by path string. NO other cross-branch `class_name` or `preload` of
other-branch scripts. This keeps files compile-decoupled.

## 2. CODING CONVENTIONS
- GDScript 2.0 (Godot 4.4). Tabs indentation. snake_case. Typed where cheap.
- UI screens: one `Control`-rooted script that builds its widget tree in `_ready()` from code
  (StyleBoxFlat, no .theme file, no external art). Minimal .tscn = root node + script only.
- Palette (use constants below, defined in `scripts/ui/ui_kit.gd` by venue-ui branch — other
  branches hardcode these hex values in their own files; do NOT import ui_kit):
  BG "#F5EFE0" cream, INK "#33312E", PANEL "#FFFDF6", ACCENT "#C4703F" terracotta,
  BRASS "#B08D3E", SAGE "#7A9B76", SLATE "#5B7B8C", PLUM "#8E6C8A",
  DEPT_COLORS = {promotions: "#8E6C8A", ticket: "#C4703F", archive: "#5B7B8C", gallery: "#B08D3E"}
- Corner radius 12, border width 3 for dept zone walls. Font: default project font.
- All player-facing numbers formatted via BigNumber.to_notation().

## 3. AUTOLOAD CONTRACTS (exact public API)
BigNumber is `class_name BigNumber` in `scripts/core/big_number.gd` (RefCounted).
Value = m * 10^e, m in [1,10) unless zero (m==0,e==0).

```gdscript
# BigNumber (class_name, RefCounted)
var m: float
var e: int
static func zero() -> BigNumber
static func one() -> BigNumber
static func from_float(v: float) -> BigNumber
static func from_parts(pm: float, pe: int) -> BigNumber
func copy() -> BigNumber
func is_zero() -> bool
func add(o: BigNumber) -> BigNumber          # returns new
func sub(o: BigNumber) -> BigNumber          # clamps at zero (economy never goes negative)
func mul(o: BigNumber) -> BigNumber          # returns new
func scale(f: float) -> BigNumber            # multiply by plain float
func div(o: BigNumber) -> BigNumber
func cmp(o: BigNumber) -> int                # -1/0/1
func gte(o: BigNumber) -> bool
func gt(o: BigNumber) -> bool
func lt(o: BigNumber) -> bool
func to_notation() -> String                 # "999", "1.23K", "45.6M", "7.89aa"
func to_save() -> Dictionary                 # {"m": m, "e": e}
static func from_save(d: Variant) -> BigNumber   # tolerant of bad input -> zero()
func to_float_approx() -> float              # clamp to 1e308 (UI bars only)
```

```gdscript
# EventBus (autoload, signals only + emit_signal passthrough is allowed)
signal cash_changed(new_value)               # BigNumber
signal gems_changed(new_value: int)
signal insight_changed(new_value)            # BigNumber
signal reputation_changed(level: int, xp)    # xp: BigNumber
signal reputation_level_up(level: int, rewards: Dictionary)
signal department_upgraded(venue_id: String, dept_id: String, track: String, level: int)
signal cash_served(amount)                   # pending cash generated at windows (BigNumber)
signal cash_banked(amount)                   # moved to vault (BigNumber)
signal manual_collect(amount)                # tap reward (BigNumber)
signal manager_obtained(manager_id: String, cards_gained: int)
signal manager_leveled(manager_id: String, level: int)
signal manager_ranked_up(manager_id: String, rank: int)
signal manager_assigned(manager_id: String, dept_id: String)   # dept_id "" = unassigned
signal manager_exchanged(from_id: String, to_id: String, cards_spent: int, cards_gained: int)
signal lootbox_opened(box_id: String, results: Dictionary)
signal quest_completed(quest_id: String)
signal milestone_completed(venue_id: String, milestone_id: String)
signal venue_progress_changed(venue_id: String, progress: float)
signal prestige_available(venue_id: String)
signal prestige_performed(from_venue: String, to_venue: String)
signal decor_purchased(venue_id: String, decor_id: String)
signal unlock_changed(feature: String, unlocked: bool)
signal offline_earnings_ready(amount, seconds: int, was_capped: bool)  # amount BigNumber
signal boost_changed(multiplier: float, seconds_remaining: int)
signal rv_reward_granted(placement_id: String, context: Dictionary)
signal iap_completed(product_id: String)
signal daily_deals_refreshed()
signal event_stage_completed(event_id: String, stage_index: int, rewards: Dictionary)
signal insight_storage_changed(stored, cap)  # BigNumbers
signal toast_requested(text: String)         # UI shows a toast
signal clock_anomaly(kind: String)
```

```gdscript
# DataLoader (autoload). All data parsed once at boot; dicts of id -> Dictionary.
var core: Dictionary            # balance_core.json
var venues: Dictionary          # id -> venue def
var managers: Dictionary
var lootboxes: Dictionary
var decor: Dictionary
var quests: Dictionary          # quest pool id -> def
var milestones: Dictionary      # venue_id -> Array of milestone defs
var iap_products: Dictionary
var offers: Dictionary
var events: Dictionary
func reload_all() -> void
func venue_order() -> Array     # venue ids sorted by "order"
func get_venue(id: String) -> Dictionary
func get_manager_def(id: String) -> Dictionary
func get_lootbox(id: String) -> Dictionary
func get_decor(id: String) -> Dictionary
func get_iap(id: String) -> Dictionary
func get_event(id: String) -> Dictionary
func dept_def(dept_id: String) -> Dictionary        # core.departments[dept_id]
func upgrade_cost(dept_id: String, track: String, level: int, venue_cost_mult: float) -> BigNumber
func track_step_multiplier(dept_id: String, track: String, level: int) -> float  # product of milestone steps <= level
```

```gdscript
# ClockGuard (autoload)
func now() -> int                                   # unix seconds
func validate_elapsed(from_unix: int, to_unix: int, cap_seconds: int) -> int  # clamp [0,cap]; rollback -> 0 + emit clock_anomaly("rollback")
```

```gdscript
# Analytics (autoload) — logs to user://analytics.log + stdout
func log_event(name: String, params: Dictionary = {}) -> void
func session_start() -> void
func rv_impression(placement_id: String) -> void
func iap_funnel(step: String, product_id: String = "") -> void
func retention_check() -> void          # computes D1/D3/D7 cohort flags from first_launch_unix
```

```gdscript
# AdService (autoload) — mediation-agnostic. Real SDK (AdMob) swaps in later.
var debug_ads: bool = true              # false in release export (documented)
signal ad_result(placement_id: String, success: bool, context: Dictionary)
func is_ready(placement_id: String) -> bool
func show_rewarded(placement_id: String, context: Dictionary = {}) -> void
# debug behavior: 0.4s timer then ad_result(placement, true, context). If context.simulate_failure -> false.
```

```gdscript
# IAPService (autoload) — store-kit agnostic stub
var debug_iap: bool = true
signal iap_result(product_id: String, success: bool)
func purchase(product_id: String) -> void   # debug: 0.4s then success; grants applied by monetization layer
func localized_price(product_id: String) -> String  # returns catalog "price_usd" string
```

```gdscript
# GameState (autoload) — single mutable state. Pure data + currency helpers. No timers.
var ready_flag: bool = false
var cash: BigNumber
var gems: int
var insight: BigNumber
var reputation_xp: BigNumber
var current_venue: String
var venues_unlocked: Array            # Array[String]
var venues_state: Dictionary          # venue_id -> {depts:{dept:{staff,speed,value}}, decor:{slot:decor_id}, milestones:Array[String], served_total:BigNumber-save, earned_total:BigNumber-save}
var pending_cash: Dictionary          # venue_id -> BigNumber (uncollected at windows)
var managers_state: Dictionary        # manager_id -> {cards:int, level:int, rank:int, assigned_to:String}
var boosts: Dictionary                # {"income_x2_until": int unix}
var rv_state: Dictionary              # placement_id -> {count:int, day:String, ready_at:int}
var daily_deals: Dictionary           # {refresh_at:int, force_used:int, day:String, items:Array}
var expedition_state: Dictionary      # {stage:int, invested:BigNumber-save, insight_stored:BigNumber-save, last_tick:int, boss_unlocked:bool}
var event_state: Dictionary           # event_id -> {stage:int, opened_at:int, team_power_at_open:float, completed:Array}
var first_launch_unix: int
var last_seen_unix: int
var offer_state: Dictionary           # offer_id -> "shown"|"bought"|"dismissed"
var settings: Dictionary              # {music:bool, sfx:bool}
func reset_to_new_game() -> void
func rep_level() -> int               # derived via core.reputation.thresholds
func rep_progress() -> float          # 0..1 toward next level
func feature_unlocked(feature: String) -> bool   # keys: "managers","expedition","inspection","decor","prestige"
func day_index() -> int               # floor((now - first_launch_unix)/86400)
func add_cash(b: BigNumber) -> void
func spend_cash(b: BigNumber) -> bool
func add_gems(n: int) -> void
func spend_gems(n: int) -> bool
func add_insight(b: BigNumber) -> void
func spend_insight(b: BigNumber) -> bool
func add_reputation(xp: BigNumber) -> void   # emits signals incl. level_up with rewards from core.reputation.rewards
func income_boost_active() -> float   # 2.0 while now < boosts.income_x2_until else 1.0
func venue_state(venue_id: String) -> Dictionary
func dept_level(venue_id: String, dept_id: String, track: String) -> int
func set_dept_level(venue_id: String, dept_id: String, track: String, level: int) -> void
func to_save_dict() -> Dictionary
func from_save_dict(d: Dictionary) -> void
```

```gdscript
# SaveSystem (autoload)
const SAVE_PATH := "user://grand_exhibit_save.json"
const SAVE_VERSION := 2
var autosave_interval_sec := 20
func save_now() -> void                     # writes {version, saved_at, checksum, state}; checksum = sha256(JSON.stringify(state)+salt)
func load_game() -> bool                    # false if missing/corrupt (corrupt -> backup rename + new game)
func has_save() -> bool
func compute_offline_and_apply() -> Dictionary  # returns {amount:BigNumber, seconds:int, capped:bool}; uses ClockGuard + Economy.current_cash_per_second(); sets last_seen
func migrate(state: Dictionary, from_version: int) -> Dictionary
```

```gdscript
# Economy (autoload) — fixed-step simulation (10 ticks/sec accumulator). _process no-op until GameState.ready_flag.
func venue_rates(venue_id: String) -> Dictionary
# -> {arrival_per_s:float, serve_per_s:float, transport_per_s:float, value_per_visitor:BigNumber,
#     pending_per_s:BigNumber, banked_per_s:BigNumber, choke_id:String, manager_mult:Dictionary}
func current_cash_per_second() -> BigNumber   # banked_per_s for current venue (decor, boost, manager mults applied)
func purchase_upgrade(venue_id: String, dept_id: String, track: String) -> bool
func manual_collect(venue_id: String) -> BigNumber   # collects fraction of pending + tip bonus (core.economy.tip_bonus_pct)
func dept_stat(venue_id: String, dept_id: String, track: String) -> float  # effective stat incl. step multipliers
func insight_per_second() -> BigNumber        # expedition idle insight rate (0 if expedition locked)
func tick_insight_storage(now_unix: int) -> void
```
SIM MODEL (per venue, per second):
- arrival_per_s = promotions.staff * promotions.speed_stat
- serve_per_s   = ticket.staff * ticket.speed_stat
- transport_per_s = archive.staff * archive.speed_stat (in visitor-units/s)
- value_per_visitor = venue.base_value * ticket.value_stat * (1 + gallery_bonus) * income_multiplier
- pending_per_s = min(arrival, serve) * value_per_visitor       (choke = argmin)
- banked_per_s  = min(pending_rate_in_cash, transport_per_s * value_per_visitor)
- pending_cash accumulates += pending_per_s - banked_per_s (>=0). banked goes straight to cash.
- income_multiplier = decor_mult * boost * milestone_global_mults (managers multiply dept stats, see managers spec)
- gallery_bonus = gallery.staff * gallery.value_stat (value_stat = fraction per staff, e.g. 0.05)
- dept stats: base + per_level*(level-1), times step-function multipliers from tracks[].steps {level:mult}.
```

## 4. DATA SCHEMAS (all files in data/, loaded by DataLoader)
### balance_core.json (owned: core branch)
```json
{
  "economy": {
    "offline_cap_hours": 4, "offline_efficiency": 1.0, "tip_bonus_pct": 0.05,
    "manual_collect_fraction": 1.0, "tick_hz": 10
  },
  "reputation": {
    "thresholds_mantissa": [0, 20, 60, 140, 300, 620, 1250, 2500, 5000, 10000, 20000, 40000, 80000, 160000, 320000],
    "xp_per_upgrade": {"base": 2.0, "per_level": 0.25},
    "level_rewards": {"gems_every_level": 5, "visitor_burst_levels": [3, 5, 8], "burst_visitors": 50}
  },
  "departments": {
    "promotions": {
      "name": "Promotions Office", "icon": "P", "color": "#8E6C8A",
      "desc": "Brings visitors to the museum.",
      "base_staff": 1, "max_staff": 25,
      "tracks": {
        "staff": {"base_cost_m": 25, "base_cost_e": 0, "growth": 1.15, "steps": {"10": 1.0, "25": 1.0}},
        "speed": {"base_stat": 0.20, "per_level": 0.02, "base_cost_m": 40, "base_cost_e": 0, "growth": 1.12, "steps": {"10": 2.0, "25": 2.0, "50": 2.0}},
        "value": {"base_stat": 1.0, "per_level": 0.05, "base_cost_m": 60, "base_cost_e": 0, "growth": 1.13, "steps": {"10": 2.0, "25": 2.0}}
      }
    },
    "ticket": { "...": "same shape; base_staff 1, max_staff 10; speed base_stat 0.34 (serve/s per window); value base_stat 1.0 per_level 0.08; costs 15/30/50 growth 1.13-1.15" },
    "archive": { "...": "same shape; speed base_stat 0.25 cart-units/s; costs 35/55/80" },
    "gallery": { "...": "value base_stat 0.05 per_level 0.01 (bonus fraction per staff); staff max 12; costs 100/150/220 growth 1.14" }
  },
  "unlocks": {"managers_rep": 6, "expedition_rep": 7, "inspection_day": 1, "decor_rep": 2}
}
```
`upgrade_cost(dept, track, level, venue_mult)` = base_cost * growth^level * venue_mult * 10^(venue cost_exp).
Track "staff" increases unit count (each purchase = +1 staff up to max_staff); "speed" and "value"
raise per-unit stats. Rep XP per purchase = xp_per_upgrade.base + level * xp_per_upgrade.per_level.

### venues.json (skeleton by main agent; meta branch balances v2-6)
Venue def: {"id","name","order":int,"base_value_m":float,"base_value_e":int,"cost_exp":int,
"cost_mult":float,"desc":String,"decor_slots":int,"milestone_track":[ids from quests_milestones]}
Venue 1 "Whispering Pines Hall": base_value 2e0, cost_exp 0. v2 "Copper Kettle Museum" 1.5e3 cost_exp 3,
v3 "Grand River Athenaeum" 2e6/6, v4 "Sunspire Gallery" 3e9/9, v5 "Cloudrest Citadel" 5e12/12,
v6 "Aurora World Museum" 8e15/15.

### managers.json (owned: managers branch) — 14 managers, original museum names
{"id","name","rarity":"common|rare|epic|legendary","specialty":"promotions|ticket|archive|gallery",
"base_mult":float (per-level dept stat bonus, e.g. 0.03 common .. 0.10 legendary),
"rank_mults":[1.0, 1.5, 2.25, 3.5], "level_cap":int, "level_cap_hook":int (legendary 100, lifted later),
"insight_cost_base":float, "insight_cost_growth":float (~1.12),
"dup_costs":[2,4,8] (cards to rank 2/3/4),
"battle_power":float (rarity base: 10/25/60/150), "color":"promotions=#8E6C8A..." (tile affinity = specialty),
"flavor":String}
Assigned manager dept multiplier = 1 + (base_mult * level) * rank_mults[rank-1]; applies to that
dept's speed stat (throughput) AND to value if specialty == "gallery" or "ticket" (doc: implement as
multiplying dept_stat for "speed" and "value" tracks only).

### lootboxes.json (owned: managers branch)
{"id","name","tier","price_gems":int (0 for Field),"rv_free":{"max":5,"recharge_hours":2} (Field only),
"cards_total":int, "rarity_weights":{"common":..,"rare":..,"epic":..,"legendary":..},
"insight_bonus_m":float, "gems_bonus":int, "published":true}
Tiers: field_case (ad, 5x/2h recharge), specialist_case (150 gems), executive_case (600 gems).
Rates must sum to 1.0 and be displayed verbatim in UI.

### events.json (owned: events branch)
{"inspection_frenzy": {"id","name":"Inspection Frenzy","unlock_day":1,"duration_hours":48,
"cooldown_hours":72,"stages":[{"boss_hp":..,"moves":int,"rewards":{...}} x6],
"scaling":{"hp_vs_power":0.9,"final_stage_power_need":1.5,"base_hp":500}},
"expedition": {"id","unlock_rep":7,"stages":[x5 {"invest_cost_m":..,"invest_cost_e":..,"insight_reward":..}],
"boss":{"boss_hp":..,"moves":..,"rewards":{..}},
"insight_idle":{"per_minute":2.0,"cap_base":60,"cap_per_rep_level":5}}}

### quests_milestones.json (owned: meta branch)
Quest pool: {"id","desc","type":"upgrade_count|earn_total|serve_total|buy_decor|own_managers",
"dept":String?, "target_m":float,"target_e":int,"progress_reward":float (bar fill 0..1)}
3 active quests per venue at a time; completing fills venue progress bar; bar full -> next milestone.
Milestones per venue (8): {"id","venue_id","name","reward":{"gems":int,"cards":{box:int}},
"global_income_mult":float (permanent, e.g. 1.1)} — last milestone enables prestige.

### decor.json (owned: meta branch) — 18+ items, 2 full sets of 6
{"id","name","slot_theme":"entrance|hall|garden","cost_cash_m/e" or "cost_gems",
"income_mult":float (e.g. 1.03), "set_id":String?, "set_bonus_mult":float (on set def),
"premium":bool, "event_exclusive":bool}
Sets: {"set_id","name","pieces":[ids],"bonus_mult":1.15}

### store_iap.json (owned: monetization branch)
{"id","kind":"gems|cash_pack|insight_pack|bundle","title","price_usd":"$0.99"(must end in 9),
"grants":{"gems":int,"cash_seconds":int,"insight_m/e":int},"tag":"starter|daily|regular",
"limit_per_day":int?}
6 gem packs $0.99..$99.99; cash packs = N minutes of current income; starter bundle (venue-2 trigger).

### offers.json (owned: monetization branch)
{"id","trigger":"venue_2_start|venue_N_start|rep_10|event_day","iap_id":String,"discount_pct":int,
"expires_hours":int} — 8+ offers covering venues 2-6 + rep milestones (deeper calendar than genre norm).

## 5. MANAGER SYSTEM RULES (managers branch)
- Unlock at rep 6 (feature_unlocked("managers")). Cards from lootboxes, event rewards, milestones.
- Level up: spend Insight (cost = insight_cost_base * growth^(level-1) * 10^0, BigNumber). Max = level_cap.
- Rank up: spend dup_costs[rank-1] duplicate cards. Rank max 4.
- Assign: one manager per dept per venue... simplify: assignment is GLOBAL per save (assigned_to = dept_id),
  applies to current venue's dept. Exchange: 5 cards of one manager -> 1 card of another chosen manager
  of SAME rarity (config "exchange_ratio": 5).
- Legendary level_cap_hook stays in data (no code path needed beyond reading the field).

## 6. MATCH-3 BATTLER RULES (events branch)
- Grid 8x8, 5 tile types keyed to dept colors + 1 neutral. Swap adjacent; no-match swaps revert.
- Match 3 = clear + charge; 4 = line clear + 1.5x charge; 5 = clear color + 2.5x charge. Cascades x1.25 per step.
- Team = up to 3 owned managers (chosen on event entry screen). Tile affinity by manager specialty color:
  matches of that color charge that manager. Full charge (100) auto-fires attack = battle_power *
  (1 + 0.12*(level-1)) * rank_mults[rank-1] * combo_mult.
- Boss: "citation meter" HP. Player has N moves; win when HP <= 0. Lose -> can retry.
- Difficulty scaling: boss_hp_i = base_hp * (i+1)^1.6 * max(1.0, (team_power_at_open/100)^0.9);
  final stage tuned so ~1.5x starting team power needed (final_stage_power_need config) — enforced by
  scaling factor applied to last stage. team_power_at_open captured when event first opens (event_state).
- Rewards per stage from events.json; deep stages = gems + executive_case.
- Expedition Mode reuses the same engine with its boss config (same scene, different config id).

## 7. META RULES (meta branch)
- Quests: 3 active drawn from pool (type checks read GameState/Economy). Complete -> progress bar += reward,
  quest replaced. Bar full -> milestone completes (reward granted, global_income_mult applied permanently),
  bar resets. After 8th milestone -> prestige_available.
- Prestige: requires all 8 milestones; moves to next venue in venue_order; dept levels of NEW venue start
  at data defaults; OLD venue state kept (can revisit? NO — one-way, keep simple, document);
  cash/gems/insight/managers/decor-collection persist. Venue switch resets pending_cash.
- Decor: per-venue slots = venue.decor_slots; buy with cash or gems; income_mult multiplies venue income;
  completing a set (all pieces owned, any venue) grants set bonus (applies to ALL venues). Premium decor
  gems-only; event_exclusive granted by event rewards only.
- Unlock schedule enforcement: feature_unlocked checks core.unlocks + day_index for inspection.

## 8. MONETIZATION RULES (monetization branch)
Six RV placements (ids): "instant_cash" (grant = 15 min of current income, core-configurable),
"free_gems" (5 gems, 3/day), "income_x2" (2h stack, cap 8h), "welcome_back" (2x offline / 3x for 20 gems),
"insight_rush" (2x ad / 3x for 10 gems on expedition collect), "free_lootbox" (field_case, 5 charges,
recharge 2h). All grant flows: UI button -> AdService.show_rewarded -> ad_result(success) -> apply grant
-> EventBus.rv_reward_granted -> Analytics.rv_impression. Failure -> toast "Ad unavailable".
Daily deals: shelf of 3 items from store_iap tag "daily", auto-refresh every 4h, force refresh 3x/day @ 10 gems.
IAP: IAPService.purchase -> iap_result(true) -> apply grants -> iap_completed + funnel logs.
Offers: trigger checks on venue/rep changes; banner UI; expiry timer. Debug build: all purchases succeed.

## 9. UI SPEC (venue-ui branch owns framework; each branch builds its screens per §11)
- HUD top bar: Cash (large, notation), Gems, Insight; Rep badge + progress bar under.
- Bottom nav (5): Museum / Managers / Expedition / Event / Store. Lock badges when feature locked.
- VenueView: vertical scroll of 4 dept panels (order: promotions, ticket, archive, gallery). Each panel:
  colored zone wall (border + tinted floor), floating circular badge with dept icon letter + name,
  visual strip (queue dots = waiting visitors: max 12 shown; cart dots moving for archive), 3 upgrade
  rows (Staff / Speed / Value) each with level, effect, cost button (disabled+red if unaffordable),
  tap panel body = manual_collect (small float text "+N").
- Popups: dim background, centered card 90% width, close X top-right. PopupManager (scripts/ui/popup_manager.gd):
  open(path:String, payload:Dictionary), close_top(). All screens are paths in registry.
- Welcome Back popup: shows offline amount + seconds; buttons: Claim (1x) / Watch Ad 2x / 20 Gems 3x.
- Toasts: bottom-center, 2s.

## 10. SAVE SCHEMA v2
{"version":2,"saved_at":unix,"checksum":sha256,"state":{ ...GameState.to_save_dict()... }}
BigNumbers serialize as {"m":float,"e":int}. Corruption: checksum mismatch -> rename to .bak, new game,
log analytics "save_corrupt". Migration v1->v2: add expedition_state/event_state defaults (migrate()
handles missing keys tolerantly; from_save_dict must accept partial dicts).

## 11. SCREEN REGISTRY (paths; opened ONLY via PopupManager.open(path) or nav)
- "res://scenes/managers/managers_screen.tscn"   (managers branch)
- "res://scenes/managers/lootbox_screen.tscn"    (managers branch)
- "res://scenes/events/inspection_screen.tscn"   (events branch)
- "res://scenes/events/expedition_screen.tscn"   (events branch)
- "res://scenes/meta/decor_screen.tscn"          (meta branch)
- "res://scenes/meta/prestige_screen.tscn"       (meta branch)
- "res://scenes/store/store_screen.tscn"         (monetization branch)
Each screen: root Control + script with `func setup(payload: Dictionary) -> void` (called by PopupManager).

## 12. TESTS (every branch)
Standalone SceneTree scripts: tests/<area>/test_*.gd, run via
`godot --headless --path <repo> -s tests/<area>/test_x.gd`; exit code 0 pass / 1 fail.
Each file defines its own tiny check() helper (no shared harness). Cover at minimum:
- core: BigNumber math incl. 1e150+ overflow safety & notation aa..az; upgrade cost curve; offline cap;
  clock rollback -> 0; save round-trip + corrupt checksum recovery; choke-point sim (min-of-depts).
- managers: level/rank costs, assignment multiplier, exchange 5:1, lootbox weights sum to 1.0, seeded open distribution in range.
- events: match detection, cascade, charge->attack damage math, scaling formula monotonic.
- meta: quest progress, milestone chain, prestige retention rules, decor set bonus.
- monetization: placement grants (debug ads), daily caps, deals refresh, offer trigger.
- venue: purchase flow spends cash + grants rep xp (can live in tests/core if simpler).

## 13. DEFINITION OF DONE (per branch)
1. Files only inside ownership map. 2. `godot --headless --path . --quit-after 3` exits clean
(no parse errors). 3. Branch tests pass. 4. Commit with message "<area>: what".
5. No edits to project.godot, docs/SPEC.md, or other branches' files.
