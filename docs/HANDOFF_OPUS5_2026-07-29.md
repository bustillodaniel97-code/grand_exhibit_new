# Grand Exhibit — Opus 5 handoff

Date: 2026-07-29  
Project root: `/home/bustillo/godot-saga/repo`  
Godot executable: `/home/bustillo/bin/godot441`  
Godot version: 4.4.1 stable  
Active branch: `ui-polish`

## Read this first

This repository has a large, intentional dirty worktree containing the accumulated
engineering, balance, UI, simulation, and venue-authoring work from the current
session. **Do not reset, clean, stash, checkout, or rewrite these changes.** In
particular, do not assume an untracked file is disposable. Several new systems,
tests, shaders, audio files, manager utilities, and audit documents are untracked.

At handoff there are roughly 3,329 inserted and 1,465 deleted tracked lines across
40 tracked files, plus numerous important untracked files. The work has been tested
in place but has not been committed by this agent.

The user is making an independently authored idle museum/venue game inspired by
the gameplay cadence and production quality of *Idle Bank Tycoon*. The goal is
feature-loop and presentation parity, not copying proprietary code or assets.

## User's product direction

The user wants:

- The same satisfying idle-management loop: arrivals, queues, service stations,
  cash accumulation, cash transport, vault/storage, department upgrades,
  bottlenecks, managers, venue completion, and progression to new venues.
- Much stronger authored visual identity than the original prototype.
- Six substantially different venues, not the same rectangular plan recolored.
- A bright, inviting, polished diorama style with readable departments, coherent
  prop clusters, floor shine, clear circulation, reactive traffic, and NPCs that
  appear to inhabit a real place.
- Global fixes. The user explicitly does not want NPC, queue, decor, or progression
  bugs re-solved independently for every level.
- Original assets, rules, balance, and implementation. Do not extract or reproduce
  proprietary IBT code/assets.

The user approved the following next-work priority:

1. Managers
2. Menus and global/meta UI
3. Remaining venue layout/art passes

This order matters: stabilize shared progression and UX before multiplying content.

## Current venue roster

All six venues are present in `data/venues.json`:

1. `whispering_pines`
2. `copper_kettle`
3. `grand_river`
4. `sunspire`
5. `cloudrest`
6. `aurora_world`

Whispering Pines is the actively reviewed level-one baseline. The others have
authored variation and validation coverage, but they have not received the same
human visual-review loop. Do not claim they have Whispering Pines-level polish yet.

## Authoritative audit documents

Read these before changing roadmap or mechanics:

- `docs/IBT_PARITY_AUDIT_2026-07-29.md`
- `docs/IBT_DECOR_MONETIZATION_AUDIT_2026-07-29.md`
- `docs/IBT_MECHANICS_AUDIT.md`

They distinguish verified reference behavior, independent implementation choices,
remaining discrepancies, decor behavior, monetization surfaces, and guardrails.

## What has been implemented

### Core venue simulation and circulation

The active implementation is primarily in:

- `scenes/venue/floor/venue_floor.gd`
- `scenes/venue/floor/character.gd`
- `scenes/venue/floor/city.gd`
- `scenes/venue/floor/exhibits.gd`
- `data/venues.json`

Implemented or substantially reworked:

- Theme-derived station, queue, lobby, gallery, store/vault, staff, porter, and
  visitor coordinates instead of one hardcoded layout.
- Quarter-tile AStar presentation navigation around solid props.
- Whispering Pines partition walls are now rasterized into navigation, so visible
  partitions are real route constraints rather than scenery NPCs ignore.
- Authored wall openings exist from the orange ticket hall to the court staircase
  and between the orange ticket hall and purple Promotions wing.
- Raised gallery/storey support, storey-aware character depth, and stair lift.
- Wide court staircase between ticket hall and raised gallery.
- The old stair was previously oriented along its longest axis; it is now explicitly
  authored with `"stair_axis": "y"` for the correct climb direction.
- Stair rooms no longer also draw a full-height slab through their treads.
- Navigation-only side terraces use `"visible": false`, preventing four white
  blocker tiles from rendering while retaining route constraints.
- An obsolete rug at `(0.3, 8.15)`, size `(8.4, 0.7)`, was removed. It was the
  persistent white rectangle with a dark inner border floating over the stairs.
- A broad shortened runner is drawn into the middle seven stair treads. It does
  not cover either landing.
- Gallery exit traffic is routed to the upper stair landing, down the staircase,
  and then through the lower circulation network. Side ledges are not legal
  shortcuts.
- Dedicated building exit separate from the entrance, resolving the former front
  door pileup and misplaced-worker/station confusion.
- Visitors enter visibly from sidewalks rather than fading into existence.
- Most guests arrive on the near sidewalk; a minority use the opposite sidewalk
  and painted crosswalk.
- Cars and pedestrians yield reactively at the crossing.
- Visitors retain full opacity during entrance walks.
- Visitors can display an angry facial expression when rejected; the face now
  agrees with the reaction indicator.
- Rejected visitors are tied to true service/crowd pressure, not the renderer's
  live-character cap.
- Cash bags can drop throughout visited areas instead of only in queue lanes.
- Multiple porter/busser support is tied to Archive staffing.
- Porters use a service corridor behind cashiers and enter the vault to deliver,
  rather than walking through desks or dropping at the room frontage.
- Porter loop is tested from cashier window to vault and back.

### Cashier and queue redesign

Whispering Pines ticket hall:

- Orange ticket room is `Rect2(0, 9, 10.5, 5)`.
- Five windows are centered inside the orange footprint:
  - `first_gx = 2.2`
  - `gx_step = 1.6`
  - `counter_gy = 1.9` relative to room
  - `porter_lane_gy = 0.45`
  - six queue slots
  - `slot_lead = 1.4`
  - `slot_gap = 0.2`
  - `lane_offset = 0.62`
- This leaves visible clearance between the counter and the first queued visitor.
- Served visitors no longer walk back to the tail of their rope line.
- `_cashier_exit(w)` sends them through the nearest left/right opening beside
  their own register, then AStar routes them to their chosen destination.
- This specifically fixes the prior behavior in which visitors looped backward
  through the queue and crossed the purple room.
- The cashier tap-to-collect mechanic is gated per cashier by a cooldown that
  begins around two minutes and scales later in progression. Review balance
  before changing it; it exists to prevent tap abuse.

### Destination behavior and Promotions

Promotions is not intended to be decorative. Economically it affects arrivals.
It now also has visible visitor behavior:

- Approximately 20% Promotions-only.
- Approximately 35% Promotions followed by Gallery.
- Approximately 45% Gallery-only.

These values come from:

- `visits_promo = intent_roll < 0.55`
- `visits_gallery = intent_roll >= 0.20`

Promotions staff were moved farther behind their desks so their bodies are visible.
The wall between ticket and Promotions has a proper doorway. Do not restore a full
partition there.

The user asked for an actual outdoor hangout destination because Gallery and
Promotions alone still feel too small for the target scale. This has **not** been
implemented yet. It should be an authored third destination with its own footprint,
props, satisfaction/dwell behavior, and routes—not a lobby waypoint relabeled
"outside."

### Latest balloon fix

The last visual request before handoff:

- Purple Promotions balloons should be attached to the top of the adjacent black
  cylinder/bin.

Implemented:

- Both now share grid anchor `(14.2, 10.4)`.
- The balloon spec has `"tie_height": 22.0`.
- `Exhibits._balloons()` accepts optional `tie_height`; strings begin at that
  height instead of the default six pixels.
- This matches the bin's 22-pixel lid height, making the composition read as tied
  to the lid.

The geometry suite passed after this change. The live build was relaunched and then
should be stopped as part of handoff.

### Props, elevation, and decor

Important elevation bug fixed in `VenueFloor._add_prop`:

- Previously the node position included storey lift, but its draw transform
  subtracted the entire node position, canceling both the grid anchor and lift.
- It now separates `screen_anchor` from elevation and subtracts only the anchor.
- This grounded/lifted upper-floor plants, exhibit bases, decor, and bins correctly.

Decor:

- Purchased decor is expected to spawn visibly and evolve room presentation.
- Decor has solid navigation footprints where appropriate.
- Decor influences satisfaction and therefore tip/drop behavior.
- Department evolution dressing is implemented by tier.
- User previously observed decor not spawning; current-save and behavior findings
  are documented in the decor audit. Re-test through the actual purchase UI before
  declaring the decor pipeline completely finished.

### Visual decluttering and presentation

- Floating room labels were removed.
- Floating exhibit captions were reduced to small brass accession ticks.
- Owned decor uses visual pads/gleams rather than text plaques.
- Large `$0.2`, `MAX`, and section-label overlays were removed from the crowd.
- Cash values were moved to cashier counter UI surfaces.
- Exhibit label colors/readability were adjusted.
- Floors and cashier glass received restrained shine/reflection treatment.
- First-venue palette is brighter and more inviting.
- Gallery is raised a storey to improve hierarchy.
- Long gallery bunting runs that added clutter were removed.
- Queue lines, counters, walls, furniture, and routes are derived from the authored
  room data as much as practical.

### Vehicle and street work

- Cars were remodeled away from the most blocky placeholder proportions.
- Cars were rescaled after being judged too small relative to NPCs.
- Crosswalk behavior and traffic yielding are implemented in `city.gd`.
- Near/far sidewalk arrival routes vary direction.
- Continue treating street scale and car art as secondary polish, not the next
  critical workstream.

### Economy, progression, meta, and managers

Touched systems include:

- `autoload/economy.gd`
- `autoload/game_state.gd`
- `data/balance_core.json`
- `data/quests_milestones.json`
- `scripts/managers/manager_system.gd`
- `scripts/managers/manager_curve.gd` (new/untracked)
- `scripts/meta/prestige_system.gd`
- `scripts/meta/quest_system.gd`
- `scenes/managers/managers_screen.gd`
- `scenes/managers/manager_badge.gd`
- `scenes/meta/prestige_screen.gd`
- `scenes/meta/statistics_screen.*` (new/untracked)

Implemented/rebalanced areas include venue progression gates, station caps, manager
curves, quests/milestones, prestige copy/flow, statistics, satisfaction, cash bags,
and department bottleneck reporting.

The user specifically complained that an introductory venue was still only 58%
complete despite maxed Promotions and station levels approaching 200. Level one
was rebalanced around a much shorter introductory arc and roughly level-100 station
expectations. Do not casually restore the earlier long grind.

The Managers workstream is the recommended next task because it is global. Audit
both behavior and presentation before changing:

- Assignment and reassignment clarity.
- Upgrade/rank costs and curve.
- Department-specific bonuses.
- Manager card hierarchy and portraits.
- Locked/available/assigned states.
- Ability timing and feedback.
- Whether manager impact is visible on the floor and in department numbers.
- Persistence across venue transitions.
- Test coverage in `tests/managers/`.

### Audio

`scenes/audio/` is new/untracked and contains background-music work. The user asked
for catchy, non-repetitive music that can be reused across levels. Inspect and test
this folder before assuming audio is absent or complete.

## Whispering Pines current authored structure

Core rooms:

- Gallery: raised, west/top, approximately `Rect2(0, 0, 9, 7)`.
- Archive/vault: east/top, approximately `Rect2(9, 0, 6, 6)`.
- Promotions: purple, `Rect2(10.5, 9, 4.5, 5)`.
- Ticket hall: orange, `Rect2(0, 9, 10.5, 5)`.
- Lobby: front/lower, `Rect2(0, 14, 15, 3)`.
- Court stair: `Rect2(2, 7, 5, 2)`, level 1 descending to level 0,
  explicit stair axis `y`.
- Side terrace/link rooms remain navigation blockers but are invisible.
- Central atrium links gallery/archive-side circulation.

Do not judge grid adjacency alone in an isometric view. Always launch and inspect
the projected scene, since two non-overlapping grid objects can visually overlap.

## Tests and validation

Use isolated XDG directories so tests do not mutate the user's real save:

```bash
env XDG_DATA_HOME=/tmp/grand_exhibit_test/data \
    XDG_CONFIG_HOME=/tmp/grand_exhibit_test/config \
    /home/bustillo/bin/godot441 --headless \
    --path /home/bustillo/godot-saga/repo \
    -s tests/venue/test_geometry.gd
```

Key suites:

```text
tests/core/test_data.gd
tests/core/test_items.gd
tests/core/test_money_bags.gd
tests/core/test_satisfaction.gd
tests/managers/test_managers.gd
tests/managers/test_carousel.gd
tests/meta/test_meta.gd
tests/meta/test_first_session.gd
tests/meta/test_venue_progression.gd
tests/venue/test_floor.gd
tests/venue/test_geometry.gd
tests/venue/test_city.gd
tests/venue/test_shell_smoke.gd
tests/venue/test_theme.gd
tests/venue/test_variation.gd
tests/venue/test_station_ui.gd
tests/venue/test_aquarium.gd
tests/venue/test_cast.gd
```

Most recent confirmed passes:

- `tests/venue/test_geometry.gd`
- `tests/venue/test_floor.gd`
- Earlier focused passes also included city, shell smoke, theme, and variation.
- `git diff --check` passed before the final few JSON/code edits; run it again.

The latest geometry run after anchoring balloons passed all checks, including:

- All prop anchors and cast waypoints visible with margin.
- No waypoint on a prop.
- Post-cashier route resolves.
- Navigation keeps body clearance from structures.
- Queue mouths connect.
- Two gallery departure lanes begin on the upper court stair.
- Dedicated exit is separate and traversable.
- Porter corridor stays behind cashier desks.
- Maxed venue fills to the live cap without false rejection.
- Ticket hall maintains visible queues.
- Cash drops occur outside the queue.
- Gallery holds an audience.
- Crowd distribution does not collapse into one state.

Do not treat automated tests as visual approval. The user has repeatedly found
projection/occlusion problems through screenshots that were mechanically valid.

## Launch command

GUI launch requires normal desktop access:

```bash
/home/bustillo/bin/godot441 \
  --path /home/bustillo/godot-saga/repo \
  --editor-pid 0
```

Wait for:

```text
BOOT OK — cash=...
```

When replacing a running build, terminate the old process/session first. Several
earlier review misunderstandings came from an old window remaining open while a
new instance failed to take focus.

## Worktree inventory warning

Tracked modifications span balance, economy, progression, managers, meta UI,
venue UI, floor simulation, city, exhibits, tests, and authoring tools.

Important untracked additions include:

- `docs/IBT_DECOR_MONETIZATION_AUDIT_2026-07-29.md`
- `docs/IBT_PARITY_AUDIT_2026-07-29.md`
- `scenes/audio/`
- `scenes/meta/statistics_screen.gd`
- `scenes/meta/statistics_screen.tscn`
- `scenes/venue/floor/venue_grade.gdshader`
- `scripts/managers/manager_curve.gd`
- multiple `.uid` files
- `tests/meta/test_first_session.gd`
- `tests/venue/test_station_ui.gd`
- `tests/venue/test_variation.gd`

Again: do not clean these.

`tools/__pycache__/venue_kit.cpython-313.pyc` is modified. It is generated noise,
but do not delete or revert it as part of an unrelated task without user approval.

## Known incomplete or risky areas

1. **Managers:** next priority; functionality exists but needs a full global UX and
   impact audit.
2. **Menus/meta UI:** polish progression, venue selection, currencies, rewards,
   quests, stats, prestige, and navigation after managers.
3. **Outdoor hangout:** requested but not yet built.
4. **Other five venues:** structurally varied and tested, not yet reviewed to the
   same visual standard as Whispering Pines.
5. **Decor purchase path:** implementation exists, but manually verify a purchase
   causes immediate visible room evolution in the real save.
6. **Stair/circulation visual review:** automated tests pass; continue watching
   multiple NPCs concurrently for rare crowd overlap.
7. **Promotions doorway:** now a real opening and wall-aware route. Do not add props
   that silently obstruct it.
8. **Data file scale:** `data/venues.json` is heavily edited. Prefer surgical edits
   and validate JSON after each patch.
9. **Performance:** character baking and spawn pacing were deliberately tuned.
   Avoid increasing initial arrival rate without measuring draw-call/bake spikes.
10. **Monetization:** ads and consent/entitlement scaffolding exist. Follow the
    independent-design and policy guardrails in the audits.

## Recommended next execution plan

### Phase 1 — Managers

1. Run all manager tests and launch the current screen.
2. Inventory every manager interaction and persistence path.
3. Compare the screen's visual hierarchy to the now-cleaner venue UI.
4. Fix assignment clarity, locked states, rank feedback, and bonus readability.
5. Make manager bonuses visibly affect department throughput/bottlenecks.
6. Add/adjust tests before changing manager balance.
7. Validate at least one venue transition with assignments intact.

### Phase 2 — Menus and global UI

1. Audit main navigation, HUD, side rail, boost dock, quests, prestige, stats,
   store/monetization, and venue transition.
2. Reduce modal/card clutter and preserve NPC/venue visibility.
3. Establish one consistent token set for spacing, type, chips, colors, shadows,
   disabled states, and attention hierarchy.
4. Make bottlenecks and available actions legible without giant overlays.
5. Exercise first-session and progression tests.

### Phase 3 — Venue content pipeline

1. Build the outdoor hangout as a reusable authored destination type.
2. Review the five later venues one at a time in live projection.
3. Preserve meaningful layout differences: room topology, elevation, circulation,
   landmark exhibits, exterior relationship, and palette.
4. Use `tools/author_venue.py` and `tools/venue_kit.py`; inspect their current
   modifications before extending them.
5. Apply global navigation/decor systems rather than venue-specific hacks.
6. Run theme, variation, geometry, floor, city, and shell tests after each venue.

## Communication notes

The user is highly engaged and provides excellent visual feedback, often based on
their wife/daughter observing the live build. They prefer seeing the actual running
result rather than hearing that a test passed.

Be explicit about whether a window is the newest run. When making a visual fix:

1. Identify the actual source.
2. Explain the visible expected change briefly.
3. Run focused tests.
4. Terminate the old GUI instance.
5. Launch the latest build.
6. Ask the user to inspect the specific behavior.

Do not overstate parity. Say which layer is complete and which still requires
human review.

## Immediate first action for Opus 5

1. Read this handoff and all three audit documents.
2. Run `git status --short --branch` and preserve everything.
3. Run `git diff --check`.
4. Run the manager test suites in isolated XDG directories.
5. Launch and audit the Managers screen.
6. Continue with the Managers phase unless the user supplies a newer priority.

