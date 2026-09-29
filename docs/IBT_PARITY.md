# Parity checklist — Idle Bank Tycoon (presentation)

Target: match Kolibri Games' *Idle Bank Tycoon* in the idle-tycoon genre.
IBT is **mechanics-and-polish inspiration only**. No copied expression, art,
copy, character design or naming. Everything we ship is original work.

Gameplay-loop parity is tracked separately in `IBT_PARITY_AUDIT_2026-07-29.md`.
The 3D toy-diorama overhaul (floors and grandeur, Dig Site, themed decor,
platforms) has its own feature scorecard: `IBT_PARITY_SCORECARD.md`. Rows
below that describe the 2D isometric floor now describe the fallback floor;
every museum ships the 3D floor.
This file covers how the game READS and what the player taps.

Re-audited **2026-07-30** against the running build. Every row below was checked
against code or data, not against memory of the last pass — the previous revision
listed both of its top-priority items as open when both had already shipped, and a
checklist that points work at the wrong thing is worse than no checklist.

---

## 1. Structural — how the world reads

| | IBT | Us | Status |
|---|---|---|---|
| Projection | true 2:1 isometric | true 2:1 isometric | **done** |
| Room volume | floor + two wall faces, extruded | floor + walls + side returns | **done** |
| Depth sorting | actors interleave with furniture | Y-sorted props and cast | **done** |
| Floor extent | runs past both screen edges | 960px floor clipped to 720 | **done** |
| Prop density | every cell furnished | 32–61 props per venue plus 16–36 dressing pieces | **done** |
| Ceiling dressing | bunting strung across rooms | bunting in all 12 venues | **done** |
| Player camera | pinch zoom + pan | pinch/wheel to 3.2x, drag pan, focal-correct | **done** |

Density is no longer eyeballed: `tests/venue/test_geometry.gd` holds a per-room
floor (`MIN_PROPS` — gallery 12, ticket 12, lobby 10, archive 7, promotions 6)
and a whole-floor minimum of 55. Those room minimums are what caught two rooms
dropping below quota during a hand-editing session.

## 2. The engagement loop — what the player taps

| | IBT | Us | Status |
|---|---|---|---|
| Tap-to-collect chips | floating collect buttons over stations | `_station_chips` per ticket item, reading `Economy.item_pending` | **done** |
| Per-station value labels | dark chips showing accrued cash | the same chips carry the amount | **done** |
| Station upgrade affordance | tap a station to upgrade | per-station upgrade buttons (`_station_upgrade`) | **done** |
| Upgrade entry | tap a station → upgrade sheet | tap a room → dept sheet with per-item list | **done** |
| Manager buff feedback | glowing aura on buffed staff | `Character._draw_manager_aura` | **done** |
| Idle-staff legibility | — | porters fade to 42% with nothing to carry | **ours** |

## 3. Monetisation surface

| | IBT | Us | Status |
|---|---|---|---|
| Rewarded video | multiple placements, capped | 6 placements, capped | **done** |
| `x2 BOOST` button | persistent, bottom of world view | `scenes/ui/boost_dock.tscn`, always present | **done** |
| Offline earnings doubler | rewarded video on welcome-back | present | **done** |
| Free-currency placement | `FREE` chip in the action row | present | **done** |
| Timed offers | countdown cards with discount badges | present | **done** |
| Gem pack ladder | 6 tiers | 6 tiers | **done** |
| Starter / first-purchase offer | prominent | `starter_bundle` in `offers.json` + `store_iap.json` | **done** |
| Ad-free purchase | offered | `ad_free` entitlement, `interstitials.gd` | **done** |
| Interstitials | between sessions, capped | `scripts/monetization/interstitials.gd`, capped, instrumented | **done** |

**Release blocker, not a parity gap:** `data/store_iap.json → ads` still holds
Google's public TEST ad units with `is_test: true`. Shipping those means zero
revenue and an AdMob policy strike. Replace before the first Play release; see
`ANDROID_RELEASE.md` §7.

## 4. Presentation

| | IBT | Us | Status |
|---|---|---|---|
| Palette | vivid, high chroma, per-room hue | same, plus ambient-tinted shadows | **done** |
| Typography | one rounded display family | Quicksand Bold/Medium | **done** |
| Buttons | chunky, extruded, press-sinks | chunky, extruded, press-sinks | **done** |
| Bottom action row | round icon buttons over the world | FREE / CASH / x2 BOOST / Store | **done** |
| Character art | hand-drawn, 3-tone, thick outline | procedural, baked 4x supersampled | **accepted gap** |
| Edge antialiasing | smooth polygon edges | none | **blocked** |

**Character art is a deliberate, owner-approved gap.** Recorded so the decision is
not silently revisited.

**Antialiasing is blocked, not deferred.** Godot logs *"2D MSAA is not yet
supported for GLES3"*, and the project runs `gl_compatibility` on purpose for
device reach. The alternatives are switching renderer, or supersampling the world
into a 2x SubViewport at 4x the fill rate on a phone. Both cost more than the hard
edges do. Measured, not assumed.

## 5. Content systems

| | IBT | Us | Status |
|---|---|---|---|
| Manager collection | gacha, rarity tiers, levels | 14 managers, rarity, 10 ranks | **done** |
| Prestige | venue reset for permanent multiplier | present | **done** |
| Milestones / quests | rolling objectives | present, including `item_level` targets | **done** |
| Timed event | limited-time mode | inspection + expedition, match-3 | **present, quality unverified** |
| Decor / customisation | cosmetic sets | present, per-museum purchase | **done** |

## Upgrade atom — CLOSED (2026-07-30)

The mechanics audit's headline finding — our unit of progression was a department
where the reference's is an individual object — is closed at both ends. The
foundation shipped 2026-07-25 (per-level `items` arrays, per-item `pending`,
`purchase_item_upgrade` / `collect_item`, save v3→v4). The presentation half that
was recorded as still open is also in: collect chips on the floor
(`_station_chips`), a per-item upgrade list in the department sheet
(`dept_panel.gd:318`), and quests targeting items (`quests_milestones.json`,
`item_level`).

Perf note still applies: `venue_rates` walks the item arrays and the budget test
sits near its cap. Per-item UI must read published rates and `item_pending`, never
re-derive flows per chip per frame.

---

## What is actually open

Presentation parity with the reference is essentially reached. What remains are
our own quality gaps, and most were found by playing the build rather than by
comparing it to IBT.

1. **Venues 7–11 have no bespoke art.** All five still share `late_art` — the same
   seven pieces at the same fractional offsets, recoloured. Venues 1–6 and 12 each
   have their own. Largest content gap, and invisible from a checklist, because
   every row above passes for those venues too.
2. **chronos_spire and empyrean_palace are unshippable as framed.** At the zoom the
   renderer actually uses, their lobbies are 88% and 100% off-canvas — the front
   door and its crowd are not on screen. Both fail loudly in the generator
   (`REFRAME_PENDING`).
3. **Seven staircases cannot express their route.** Their landings are not on
   opposite faces of one axis, so they fall back to the renderer's guess and warn
   every generator run.
4. **The surround reads bare** against the reference — neighbouring buildings, kerb
   and lot dressing are thin.
5. **Lounges are hand-authored on one venue.** Should be derived from each plan so
   every museum gets them.
6. **Face shading ignores rotation.** `Iso.box` lights a fixed left/right face, so a
   piece turned past 90° is lit from the wrong side.
7. **Camera-facing walls do not occlude the cast.** Every wall in a storey batches
   into one node that sorts behind the actors. Glazing the affected walls was the
   cheap fix; splitting them into y-sorted nodes is the real one, at a draw call
   each.
8. **The timed event's quality is still unverified** — carried unchanged from the
   previous audit, and the oldest unexamined claim in this file.
