# IBT MECHANICS AUDIT — Grand Exhibit vs *Idle Bank Tycoon: Money Empire*

> **Historical snapshot:** the implementation verdicts below predate the parity
> work and are preserved as research provenance, not current status. See
> `docs/IBT_PARITY_AUDIT_2026-07-29.md` for the verified current matrix.
> Individual station levels/piles and gated collection, the persistent boost
> dock, ten manager ranks, statistics guidance, and six structurally authored
> venues are now implemented.

Date: 2026-07-25 · Scope: **core mechanics only** (not art, not polish — `docs/IBT_PARITY.md`
already covers presentation). Method: primary-source research on IBT + read-only inspection of
this repo. No code was changed.

**Repo state warning.** At audit time four files were uncommitted and mid-edit by another agent:
`autoload/economy.gd`, `data/balance_core.json`, `data/decor.json`, `scripts/meta/decor_system.gd`
(`git status`, branch `ui-polish`). That work is the satisfaction/rating system. It is called out
explicitly in §3 and conclusions about it are marked in-flight, not final.

## Sources

| Tag | Source |
|---|---|
| **[PG]** | [PocketGamer.biz — *Game Analysis: Deconstructing Idle Bank Tycoon by Kolibri Games*](https://www.pocketgamer.biz/game-analysis-deconstructing-idle-bank-tycoon-by-kolibri-games/) |
| **[AQ]** | [AppQuantum — *Deconstructs Idle Bank Tycoon*](https://appquantum.medium.com/appquantum-deconstructs-idle-bank-tycoon-what-makes-this-game-one-of-the-most-successful-projects-24e55cdc9e71) |
| **[LW]** | [Level Winner — *Idle Bank Tycoon Guide: Tips, Tricks & Strategies*](https://www.levelwinner.com/idle-bank-tycoon-money-empire-guide-tips-tricks-strategies/) |
| **[FW]** | [FatWallet Refugee — *Game Guide: Idle Bank Tycoon*](https://fatwalletrefugee.com/2024/02/27/idle-bank-tycoon/) |
| **[TA]** | [Talk Android — *Tips To Play Idle Bank Tycoon*](https://www.talkandroid.com/22380-tips-to-play-idle-bank-tycoon-updated-for-2023/) |
| **[S-max]** | Screenshot, IBT max level — `/home/bustillo/.claude/uploads/0f162f2b-2b4f-4bfe-b1b3-84a7a6148762/df18aaac-1313.jpg` |
| **[S-mid]** | Screenshot, IBT mid game — `.../2320cbb7-1315.jpg` |
| **[S-mgr]** | Screenshot, IBT managers + promote modal — `.../47e9fbc5-1333.jpg` |
| **[S-stn]** | Screenshot, IBT station upgrade UI — `.../8da070d9-758.jpg` |

---

## 1. IBT's actual core loop

**The atom of Idle Bank Tycoon is an individual placed object, not a room.**

The bank has four rooms — Marketing Department (attracts customers), Service Windows (rate of
currency accumulation), the Vault (staff move money to the safe by cart), and the Main Hall
(extra soft currency per customer) **[PG]**. But the room is only a container. Inside each room
sit *many individual items, each of which levels independently* **[LW]**: teller desks, cash
carts, marketing desks, vault shelving, main-hall seats, plus decorative items.

The proof is in the quest strip **[S-mid]**, which reads objects, never rooms:

> `Upgrade Vault Room Items for a total of 484 levels` — 394/484
> `Upgrade 3 Cash Cart(s) to level 96` — 0/3
> `Upgrade 3 Marketing Desk(s) to level 74` — 0/3

Individual carts and desks carry their own level numbers in the nineties and seventies, and the
game counts *484 item-levels* inside one room. That is per-object progression, and it is the
spine of the game.

**The minute-to-minute session** is therefore a floor scan, not a menu visit:

1. Open the game, take the Welcome Back offline lump (2x for a rewarded video, 3x for hard
   currency) **[PG]**.
2. Look at the diorama. Every station carries a **dark value chip** showing cash accrued at that
   specific object — `56 716`, `57 042`, `4,13M`, `4,3M`, `0`, `746,1K`, `1,2M` **[S-mid, S-max]** —
   with a thin green fill bar under it.
3. Tap the green **`Collect Reward`** buttons that have popped over finished stations and over
   seated customers in the Main Hall — `130.60K`, `156.82K`, `43.318` **[S-max]**. Main Hall seats
   accumulate: "empty seats will fill with money bags over time" **[FW]**.
4. Spend the cash upgrading whichever objects the three active quests point at, or whichever is
   cheapest. Tapping a station opens its sheet, which shows the room's rate and headcount
   (`17,180/s`, `+301`) and a progress bar, over a single `UPGRADE` button **[S-stn]**.
5. Every upgrade grants Reputation stars; the star level gates features **[LW, TA]**.
6. Every other day, play the **Audit Madness** limited-time event; whenever it is open, farm
   **Business Mode** for light bulbs to level managers **[PG, AQ, FW]**.
7. Tap the persistent `x2 BOOST` rewarded-video button and the `FREE` chip in the bottom action
   row **[S-mid]**.

**The bottleneck** is a genuine flow chain: marketing sets arrival, service windows set the
processing rate, and vault carts set how fast earned money actually reaches the safe **[PG]**.
The vault also has an upgradeable **capacity**, separate from transporter speed **[LW]**.

**Satisfaction / rating — read this carefully.** The owner reports that customers rate the venue
on decor, speed and rest areas, and that this drives currency drops. What I can confirm from
sources is *the parts, not the composite*:

- **Confirmed:** Reputation is a star currency; "every upgrade you make increases your reputation
  by a little bit" **[LW]**, shown as a purple star badge with a progress bar (`9` mid-game,
  `13` at max) **[S-mid, S-max]**.
- **Confirmed:** each room contains decorative items alongside its functional ones, and upgrading
  decor "increase[s] client deposits and reputation points" and "deposit amounts" **[LW]**.
- **Confirmed:** the Main Hall is the seating/rest area, and seated customers spawn collectible
  money bags over time **[FW]**, visible as `Collect Reward` chips over the couches **[S-max]**.
- **UNVERIFIED:** I found **no source describing a composite customer-satisfaction score that
  weighs decor, speed and rest areas into a single income multiplier.** No such meter appears in
  any screenshot I examined. The owner's model is a plausible synthesis of three real IBT parts,
  but as a single named mechanic it is not corroborated. Flagging this because a system matching
  that description is being written into this repo right now (§3).

**Managers** unlock at Reputation 6 **[PG]**. They are acquired as cards from briefcases — Intern,
Senior, Director — via quests, events and purchase **[LW]**. They level with light bulbs and rank
up with duplicates **[PG]**. The promote modal **[S-mgr]** shows the real shape: a **star rank**
(1★ → 3★), a **Max Level** that the rank raises (20 → 40), and **two separate stats** —
**Efficiency** (100 → 125) and **Productivity** (+20% → +25%). Promotion consumes duplicate
managers ("MANAGERS NEEDED", two 0/1 slots). Rank runs far deeper than 4: level caps scale "from
2★ at level 40 to 10★ at level 300" **[FW]**. Efficiency is the audit stat; matching a manager's
specialty symbol to the audit slot grants a bonus **[LW, TA]**. Productivity is the income stat.

**Currencies:** Cash (soft, primary, retained across banks), Gold Ingots (hard/premium), Light
Bulbs (evolve currency, manager levels only, earned in Business Mode and idly into a capped
store), Manager Cards, and Reputation Stars **[PG, LW, FW]**. All five are visible in the HUD
**[S-mid, S-mgr]**.

**Progression:** one-way. "Once you're done with the first bank, it will be marked sold and you'll
move onto the next bank" **[LW]**; later banks are bigger and slower. Crucially, "players retain
their soft currency when advancing to a new Prestige level" **[PG]**.

**Events:** one LTE — **Audit Madness**, available from day 2, running every two days, awarding
briefcases of manager cards **[AQ]**. It scales with the player's main-game progress, and clearing
all levels requires better managers than you started with **[PG, AQ]**.

### CRITICAL QUESTION: does IBT contain a match-3 puzzle battler?

**Yes. Emphatically yes, in two places.** This is the one thing the audit was expected to
overturn and it does not.

- Audit Madness is described verbatim as "the match-3 battler" **[AQ]** and as a "match-3 battler"
  LTE **[PG]**.
- Business Mode "launches at reputation level 7, requiring soft currency investment to earn evolve
  currency and defeat bosses using **match-3 gameplay**" **[PG]**; **[FW]** independently calls
  Business Mode "a **Match3 puzzle mini-game** with Auto-Mode functionality" whose purpose is
  collecting light bulbs to level managers.
- The battle detail is corroborated at play level: "the auditor lets you make several moves before
  he deals massive blows, so if every move you make creates a combo, you will surely survive the
  round", and there are bonus tiles indicated at the upper left of the puzzle **[AQ]**.
- Managers are the team you bring: they are "essential for progressing through LTEs and enhancing
  combos" **[PG, AQ]**.

Note the one older account that disagrees: **[LW]** describes Business Mode as tapping a `Manage`
button for cash and the audit as a manager stat check (matching specialty symbols, combined
efficiency thresholds) with no puzzle. Three later sources say match-3. The most likely reading is
that **[LW]** documents an earlier build, or the stat check is the *preparation* layer that feeds
the puzzle. Either way, **the mid-game activity in current IBT is a match-3 battler fought with a
manager team, and K3 did not invent it.**

---

## 2. Divergence table

| Mechanic | What IBT does | What we built | Verdict |
|---|---|---|---|
| **Upgrade atom** | Individual placed objects, each with its own level; hundreds per room (`484` item-levels in the Vault Room; carts at level 96) **[S-mid, LW]** | 4 departments × 3 abstract tracks (`staff`/`speed`/`value`); `staff` is a count to `max_staff`, `speed`/`value` are department-wide scalars — `autoload/economy.gd:155-175`, `docs/SPEC.md` §3 | **DIVERGES — structural** |
| **Tap-to-collect** | `Collect Reward` buttons over stations and seats; dark per-object value chips with green fill bars **[S-max, S-mid]** | `Economy.manual_collect()` exists and pays pending + 5% tip (`autoload/economy.gd:188-200`) but is a whole-venue tap; no per-station chips. Already self-reported at `docs/IBT_PARITY.md` §2 as "gap — major" | **MISSING** |
| **Flow / choke chain** | marketing → service windows → vault carts **[PG]** | `promotions → ticket → archive`, `min(arrival, serve)` then `min(that, transport)`, with `choke_id` returned — `autoload/economy.gd:138-149` | **MATCHES** |
| **Fourth room bonus** | Main Hall gives extra soft currency per customer **[PG]** | `gallery` dept adds `gallery_bonus` into `value_per_visitor` — `autoload/economy.gd:131-137` | **MATCHES** |
| **Vault / cart split** | Vault upgrades deposit speed; cash-cart upgrades carrying capacity (official Help Center + **[FW]**) | `archive.speed` is deposit speed, independently levelled Archive items contribute cart capacity, and `archive.value` scales transport | **MATCHES** |
| **Match-3 battler** | Audit Madness LTE (match-3 battler) + Business Mode (match-3, farms evolve currency) **[PG, AQ, FW]** | `scripts/events/match3_engine.gd` (8×8, 5 tile types, cascades, audit-focus mechanic) + `scripts/events/battle_math.gd` | **MATCHES** |
| **LTE cadence** | Audit Madness from day 2, runs every two days **[AQ]** | `inspection_frenzy`: `unlock_day: 1`, `duration_hours: 48`, `cooldown_hours: 72` — `data/events.json` | **MATCHES** (cooldown slightly slacker) |
| **Business Mode** | Unlocks at Reputation 7; invest soft currency → earn evolve currency + fight bosses **[PG]** | `expedition`: `unlock_rep: 7`, 5 invest stages paying insight, then a match-3 boss — `data/events.json`, `scenes/events/expedition_screen.gd` | **MATCHES** |
| **Idle evolve currency** | Idle bulb accrual into limited storage; RV doubles it ("The Interns Worked Hard") **[PG]** | `insight_idle` 2.0/min, cap `60 + 5×rep`, `collect_insight(multiplier)` for 1x/2x/3x — `autoload/economy.gd:202-247` | **MATCHES** |
| **Managers unlock** | Reputation 6 **[PG]** | `managers_rep: 6` — `data/balance_core.json` | **MATCHES** |
| **Manager stats** | **Two** stats: Efficiency (audit) and Productivity (income), plus a specialty symbol **[S-mgr, LW]** | **One** economic multiplier (`base_mult × level × rank_mult`, `autoload/economy.gd:62-74`) plus a separate `battle_power` for combat | **DIVERGES** |
| **Manager rank depth** | Star ranks to 10★, level caps to 300 **[FW]**; promotion consumes duplicate managers **[S-mgr]** | Rank max 4 (`rank_mults` 4 entries), `level_cap` 50, `dup_costs [2,4,8]` — `data/managers.json` | **DIVERGES — shallower** |
| **Manager acquisition** | Briefcases: Intern / Senior / Director, from quests, events, purchase **[LW]** | 3 lootbox tiers: `field_case` (RV, 5 charges/2h), `specialist_case` (150 gems), `executive_case` (600 gems) — `docs/SPEC.md` §4 | **MATCHES** |
| **Currencies** | Cash, Gold Ingots, Light Bulbs, Manager Cards, Reputation Stars **[PG, LW]** | Cash, Gems, Insight, Manager Cards, Reputation XP — `docs/SPEC.md` §0 | **MATCHES** |
| **Progression** | One-way, bank "sold", soft currency **retained** **[LW, PG]** | One-way through 6 venues, cash retained, dept levels reset — `scripts/meta/prestige_system.gd`, `data/venues.json` | **MATCHES** |
| **Venue count** | Owner reports ~12 levels played; total bank count **unverified** | 6 venues — `data/venues.json` | **DIVERGES (probable)** — see §4 |
| **Quests** | Three active at a time, object-targeted, feeding a milestone bar **[S-mid, LW]** | 3 active from pool, feeding venue progress → 8 milestones → prestige — `scripts/meta/milestone_system.gd` | **MATCHES** (but targets departments, not objects) |
| **Satisfaction rating** | Parts confirmed (rep stars, decor items, Main Hall seats); **composite score unverified** | Being written now: `satisfaction.weights {decor 0.4, speed 0.35, rest 0.25}`, income mult clamped 0.5–2.0 — `data/balance_core.json`, `scripts/meta/decor_system.gd:79-113` | **INVENTED** (in flight) |
| **Welcome Back** | Offline lump, 2x RV / 3x hard currency **[PG]** | Present, same shape; 4h offline cap — `docs/SPEC.md` §9, `data/balance_core.json` | **MATCHES** (cap length unverified vs IBT) |
| **Persistent `x2 BOOST`** | Large permanent button on the world view **[S-mid, S-max]** | `scenes/ui/boost_dock.gd` exists; `docs/IBT_PARITY.md` §3 still reports it "buried in the store" | **MISSING / partial** |
| **Bottom action row** | 5–6 round icons over the world: FREE, rep, `x2 BOOST`, cards, MAX bulbs **[S-mid]** | Tab bar (`scenes/ui/bottom_nav.gd`); flagged as gap in `docs/IBT_PARITY.md` §4 | **MISSING** |
| **Daily deals** | Auto-refresh every few hours; 3 forced refreshes/day for 10 hard currency **[PG]** | Identical: 3 items, 4h refresh, 3 force/day @ 10 gems — `docs/SPEC.md` §8 | **MATCHES** |
| **Offer calendar** | "Back to School" offer at second bank start **[PG]** | 9 offers incl. `offer_venue2` @ `venue_2_start`, `starter_bundle`, `first_buy_bonus` — `data/offers.json`, `data/store_iap.json`. (Note: `docs/IBT_PARITY.md` §3 claims starter offer "absent" — that is stale w.r.t. the data.) | **MATCHES** |
| **RV placements** | Instant cash by per-second income, hard currency, 2x/2h boost, idle-bulb doubler, free lootbox 5×/2h **[PG]** | Same six: `instant_cash`, `free_gems`, `income_x2`, `welcome_back`, `insight_rush`, `free_lootbox` — `scripts/monetization/rv_placements.gd` | **MATCHES** |
| **Interstitials / ad-free IAP** | Present **[PG implies ad-led revenue]** | Absent — `docs/IBT_PARITY.md` §3 | **MISSING** (low priority) |

**Verdict counts: MATCHES 16 · DIVERGES 5 · MISSING 5 · INVENTED 1.**

---

## 3. The invented mechanics

Only one true invention exists. K3's meta layer is otherwise an unusually faithful transliteration
of the published IBT deconstructions — `unlock_rep: 7` for Business Mode, `managers_rep: 6`,
capped idle evolve currency, three-tier briefcases, 3-item daily deals at 10 hard currency per
forced refresh. Those numbers are not guesses; they are **[PG]**'s numbers.

### 3.1 The satisfaction / venue-rating system — **IN FLIGHT, verdict: keep, but re-label**

`data/balance_core.json` now carries a `satisfaction` block weighting decor 0.40, speed 0.35 and
rest 0.25 into a single income multiplier clamped to 0.5×–2.0×; `scripts/meta/decor_system.gd:79-113`
scores decor pieces and rest seats. The uncommitted `economy.gd` diff splits `venue_flows()` out of
`venue_rates()` so the rating cannot feed back into the flow it is measured from, and multiplies
satisfaction into **value per visitor** rather than arrival rate. Its own comment states the
provenance plainly: *"owner's brief: 'visitors rate the venue, and that rating drives how much
currency they drop'"*.

The engineering is careful — the one-way `flows → rating → value` split correctly avoids the
compounding loop where a speed upgrade would raise both throughput and arrivals.

**Assessment: keep it.** It is a good mechanic and it makes decor load-bearing instead of a flat
+3% sticker, which is a real weakness of the current build. But it should be recorded as **our
design, not IBT parity**, because I could not verify IBT computes any such composite score. The
risk of mislabelling it is that someone later "fixes" a divergence that was never a divergence, or
balances it against an IBT reference that does not exist. It also introduces a
**0.5× income floor** — a punitive state IBT has no evident equivalent of. Recommend watching that
clamp closely; idle players are highly loss-averse and a visible "your venue is bad" multiplier is
a churn surface. Consider clamping to `1.0–2.0` (pure upside) unless play-testing says otherwise.

### 3.2 Things that look invented but are not

Recorded so they are not cut by mistake:

- **The match-3 battler** (`scripts/events/match3_engine.gd`). Real IBT mechanic, twice over
  **[PG, AQ, FW]**. **Keep.** Moreover our version is *better designed than the brief required*:
  the `FOCUS_CHARGE_MULT` audit-focus system (engine header, lines 8-14) was added because a board
  with ~18 undifferentiated legal moves measured as only a 1.8% skill delta — it converts the
  puzzle from a tap tax into a search. `battle_math.gd:4-11` documents and fixes a genuine design
  bug where boss HP keyed off the *owned roster* rather than the *selected team*, which made every
  manager you collected strictly harden the event. That is real design work; do not throw it away.
- **Expedition Mode as a cash-sink → evolve-currency faucet.** That is exactly IBT's Business Mode
  **[PG]**. **Keep.**
- **The `gallery` department.** Maps onto IBT's Main Hall **[PG]**. **Keep.**

---

## 4. The missing mechanics, ranked by cost

**1. Per-object upgrade granularity and per-object cash chips.** *(retention — severe)*
This is one item, not two, and it is the top of the list by a wide margin. In IBT the player looks
at a floor covered in objects that each carry a number, picks one, and taps it. In ours the player
opens a department sheet with three rows. Everything else on this list is downstream of it. The
`docs/DESIGN_DECISIONS.md` entry of 2026-07-24 records the owner's own verdict on the pre-diorama
build — *"it's only menus"* — and the Phase 2 living-floor work addressed the *rendering* of that
problem without changing the *upgrade unit* underneath. The floor is now a beautiful diorama of a
simulation the player still cannot touch object by object.

**2. Tap-to-collect `Collect Reward` chips.** *(retention + revenue — severe)*
The reason to open an idle game is to harvest something. `Economy.manual_collect()` already
computes the payout (`autoload/economy.gd:188-200`); what is missing is per-station accrual and
the buttons. `docs/IBT_PARITY.md` §2 already ranks this #1 and is correct to.

**3. Persistent `x2 BOOST` button + bottom action row.** *(revenue — high)*
IBT's most valuable ad placement is a permanent one-tap button on the world view **[S-mid, S-max]**,
not a store entry. We have `scenes/ui/boost_dock.gd` but it is not surfaced. Directly monetisable,
and **[PG]** notes IBT's revenue is ad-led with a low $0.6 IAP RPD — meaning the ad surface *is*
the business model.

**4. Manager depth: two stats, and rank beyond 4.** *(retention — medium-high)*
IBT separates **Efficiency** (audit performance) from **Productivity** (income) **[S-mgr]** and runs
ranks to 10★/level 300 **[FW]**. We collapse both into one multiplier and stop at rank 4 / level 50.
The two-stat split is what makes a manager a *choice* rather than a strict power ordering, and the
deep rank ladder is the long-tail card sink that keeps briefcases meaningful for months. With rank
capped at 4 and 14 managers, our card economy saturates fast.

**5. Vault capacity as a storage ceiling.** *(retention — medium)*
IBT upgrades vault *capacity* separately from cart *speed* **[LW]**. A filling vault is a visible,
legible reason to come back and tap. Ours models the archive purely as a rate, and `pending_cash`
grows without bound (`autoload/economy.gd:37-40`) — so nothing ever visibly backs up.

**6. Venue count.** *(retention — medium, unverified)*
We ship 6 venues (`data/venues.json`). The owner has played ~12 levels of IBT. I could **not**
verify IBT's total bank count, and the purple star in the screenshots is *Reputation level* (9
mid-game, 13 at max **[S-mid, S-max]**), not a bank counter — so "12 levels" may well be reputation,
not banks. Flagging as a content-runway question to answer with real data before anyone builds
venues 7-12. **Unverified.**

**7. Capped interstitials and an ad-free IAP.** *(revenue — low)*
Standard genre furniture, cheap to add, small delta.

---

## 5. Single clearest finding

**K3 did not confuse the genre. It got the meta layer unusually right and the core loop's
*granularity* wrong.**

The owner's specific suspicion — that the match-3 battler was invented or imported from another
genre — is **incorrect**. Idle Bank Tycoon contains a match-3 battler in two separate places, and
our implementation of it is faithful and, in its balance model, better than the brief. The manager
gates, the currency set, the Business-Mode structure, the daily-deal cadence and the RV placement
list are all near-exact matches to the published deconstructions. That part of the build is sound.

The structural error is **the upgrade atom**. IBT's unit of progression is *an individual object
sitting on the floor* — this cart, that desk, level 96 — each with its own accumulating pile of
cash and its own tap target. Grand Exhibit's unit is *a department with three abstract sliders*
(`staff` / `speed` / `value`, `autoload/economy.gd:155-175`). That single substitution is what
removes the entire minute-to-minute loop: with no per-object state there is nothing to put a
number chip on, nothing to put a `Collect Reward` button over, nothing for a quest to point at
("Upgrade 3 Cash Carts to level 96" is unexpressible in our data model), and nothing to scan the
floor *for*. The diorama then has no choice but to be scenery.

Every other DIVERGES and MISSING verdict in §2 — no collect chips, no per-station values, quests
that target departments instead of objects, a floor that reads as decoration — is a symptom of
that one decision. Fixing granularity is the high-leverage move; fixing the symptoms individually
is not.

Concretely: departments should become *containers of N independently-levelled items*, with
`pending_cash` tracked per item instead of per venue. The choke model in `venue_rates()` survives
unchanged — it just sums over items within a department instead of reading a `staff` integer.
That keeps the (correct, tested) economy and buys back the loop.
