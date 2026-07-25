# Parity checklist — Idle Bank Tycoon

Target: match Kolibri Games' *Idle Bank Tycoon* in the idle-tycoon genre.
IBT is **mechanics-and-polish inspiration only**. No copied expression, art,
copy, character design or naming. Everything we ship is original work.

Derived from reference captures of IBT (store shots, an early-game session, and
a max-level session). Ordered by how much each gap costs us in player-visible
quality, not by implementation effort.

---

## 1. Structural — how the world reads

| | IBT | Us | Status |
|---|---|---|---|
| Projection | true 2:1 isometric | true 2:1 isometric | **done** |
| Room volume | floor + two wall faces, extruded | floor + walls + side returns | **done** |
| Depth sorting | actors interleave with furniture | Y-sorted props and cast | **done** |
| Floor extent | runs past both screen edges | 960px floor clipped to 720 | **done** |
| Prop density | every cell furnished | rooms still read sparse | **gap** |
| Ceiling dressing | bunting strung across rooms | none | **gap** |

**Density is the single biggest remaining visual gap.** At max level IBT's floor
has furniture, shelving, plants or signage in essentially every tile, plus a
queue packed shoulder-to-shoulder. Sparse floor is what reads as "prototype"
from a distance, which is exactly the altitude players judge from.

## 2. The engagement loop — what the player taps

| | IBT | Us | Status |
|---|---|---|---|
| Tap-to-collect chips | floating green `Collect Reward` buttons with the accrued amount, anchored over stations | none | **gap — major** |
| Per-station value labels | dark chips showing accumulated cash per station (`56 716`, `746.1K`) | none | **gap — major** |
| Station progress bars | thin green fill under each station label | none | **gap** |
| Upgrade entry | tap a station → upgrade sheet | tap a room → dept sheet | **done** |
| Manager buff feedback | glowing aura on buffed staff | none | **gap** |

The collect-chip loop is what converts an idle game from "watch numbers" into
"check in and tap". We have the economy underneath it already — `Economy` tracks
per-department accrual — so this is presentation, not simulation work.

## 3. Monetisation surface

| | IBT | Us | Status |
|---|---|---|---|
| Rewarded video | multiple placements, capped | 6 placements, capped | **done** |
| `x2 BOOST` button | large, persistent, bottom of the world view | buried in the store | **gap — major** |
| Offline earnings doubler | rewarded video on the welcome-back sheet | present | **done** |
| Free-currency placement | `FREE` chip in the bottom action row | present, not surfaced | **gap** |
| Timed offers | countdown cards with discount badges | present | **done** |
| Gem pack ladder | 6 tiers | 6 tiers | **done** |
| Starter / first-purchase offer | prominent | absent | **gap** |
| Ad-free purchase | offered | absent | **gap** |
| Interstitials | between sessions, capped | none | **gap** |

The persistent `x2 BOOST` button is the highest-value monetisation gap: it is a
permanent, one-tap rewarded-video entry point sitting on the main view, not
something the player has to go looking for.

## 4. Presentation

| | IBT | Us | Status |
|---|---|---|---|
| Palette | vivid, high chroma, per-room hue | vivid, high chroma, per-room hue | **done** |
| Typography | one rounded display family | Quicksand Bold/Medium | **done** |
| Buttons | chunky, extruded, press-sinks | chunky, extruded, press-sinks | **done** |
| Character art | hand-drawn, 3-tone, thick outline | procedural, baked 4x supersampled | **accepted gap** |
| Bottom action row | 5–6 round icon buttons over the world | tab bar | **gap** |

**Character art is a deliberate, owner-approved gap.** Matching hand-drawn
sprites means either an artist or a 3D-render pipeline; the owner's call is that
procedural is good enough because players judge from a distance. Recorded here so
the decision is not silently revisited.

## 5. Content systems

| | IBT | Us | Status |
|---|---|---|---|
| Manager collection | gacha, rarity tiers, levels | 14 managers, rarity, levels | **done** |
| Prestige | venue reset for permanent multiplier | present | **done** |
| Milestones / quests | rolling objectives | present | **done** |
| Timed event | limited-time mode | inspection + expedition | **present, quality unverified** |
| Decor / customisation | cosmetic sets | present | **done** |

---

## Upgrade atom — status (2026-07-25)

The mechanics audit's headline finding — our unit of progression was a department
with three sliders where the reference's is an individual object on the floor —
is now HALF closed. The FOUNDATION is in:

  · Departments are containers of per-level ITEMS (`venue_state.depts[x].items`);
    the "staff" track survives as a derived count, so every legacy caller and
    test still works, and raw `staff` writes reconcile the container on read.
  · A level-L item contributes `1 + (L-1) * items.step_per_level` staff-units;
    N level-1 items are exactly the old integer staff, so every balance identity
    holds by construction. `venue_flows` sums units; the choke model is untouched.
  · Each ticket item carries its own accumulating `pending` pile — the venue
    pending decomposed by throughput share, drained by porters by pile share,
    renormalised every allocation so drift cannot accumulate.
  · `Economy.purchase_item_upgrade` / `item_upgrade_cost` / `item_pending` /
    `collect_item` (exactly-once, clamped to venue pending), with
    `EventBus.item_upgraded` / `item_collected` signals.
  · Save v3 -> v4 migration; `tests/core/test_items.gd` (34 checks) covers the
    identities, allocation, collect-once and migration.

STILL OPEN (the presentation half): floating per-station cash chips + Collect
buttons on the floor reading `Economy.item_pending` and calling `collect_item`;
a per-item upgrade list in the department sheet driving `purchase_item_upgrade`;
quests that point at items. The signals and accessors above are the contract to
build against. Perf note: `venue_rates` walks the item arrays (budget test sits
at ~1.95s of a 2s cap for 10k calls) — per-item UI must read the published rates
and `item_pending`, never re-derive flows per chip per frame.

## Priority order

1. **Tap-to-collect chips + per-station value labels** — the missing core loop.
2. **Persistent `x2 BOOST` rewarded-video button** — the missing revenue loop.
3. **Prop density pass** — the thing that reads as unfinished from a distance.
4. **Bottom action row** over the world view (FREE / boost / offers).
5. **Starter offer + ad-free IAP + capped interstitials.**
6. **Manager buff aura + ceiling dressing** — polish.
