# Grand Exhibit — Claude complete-project handoff

Date: 2026-07-29 (updated after twelve-venue/menu pass)  
Repository: `/home/bustillo/godot-saga/repo`  
Branch: `ui-polish`  
Godot: `/home/bustillo/bin/godot441` (Godot 4.4.1)

## Mission and ownership boundary

> **This document supersedes the earlier six-venue handoff sections below.**
> The repository now contains twelve venue records and the shared menu/event
> polish described in the “Current delta” section at the end. Read that section
> before treating any older six-venue wording as current.

Claude owns the **remainder of the core gameplay and Android-release engineering**:

- finish and harden the complete idle-tycoon loop;
- fix the confirmed decor ownership/presentation defect described below;
- replace release stubs with production adapters;
- close progression, persistence, performance, accessibility, device-QA, and
  Play Store submission blockers;
- preserve the original museum identity and the working shared venue simulation.

Codex retains **venue/content ownership**:

- do not redesign or replace the current venue layouts without coordinating;
- Codex has authored levels 7–12;
- those six levels grow progressively larger, grander, more structurally
  complex, more visually distinctive, and harder/longer to complete;
- Codex also owns their room plans, navigation corridors, surroundings,
  architecture, exhibit dressing, decor anchors, camera framing, and geometry QA.
- Codex owns final player-facing menu art direction, information hierarchy,
  visual consistency, transitions, responsive composition, and presentation QA.
- Claude may wire menu behavior and data, but should not independently replace
  the established visual language or ship programmer-facing/default-looking UI.

Shared systems may be changed by Claude when necessary. Do not hardcode new
behavior into one venue. Stable internal department ids (`promotions`, `ticket`,
`archive`, `gallery`) are save/API contracts even when player-facing roles have
venue-authored names such as `Harbor Cafe`.

The user's standing quality bar is commercial presentation parity with Idle Bank
Tycoon across both levels and menus. This means comparable readability,
hierarchy, responsiveness, feedback, animation cadence, and sense of progression;
it does not authorize copying IBT assets, exact layouts, writing, or branded UI.

## Non-negotiable repository safety

The worktree is intentionally very dirty and contains a large amount of current
work. Preserve it. Do not reset, clean, checkout, or revert unrelated changes.
Do not discard untracked files. Inspect overlapping edits before modifying them.

The live user save is:

`/home/bustillo/.local/share/godot/app_userdata/Grand Exhibit/grand_exhibit_save.json`

Never mutate, delete, or replace that save during automated tests. Tests should
use their isolated/test state.

## Current product state

The historical snapshot below describes the shared systems that were already
present before the final venue expansion. The current roster is twelve; see the
authoritative delta section at the end of this document.

The game currently has:

- twelve authored venues;
- marketing/café arrival → ticket service → physical cash transport → vault flow;
- individual cashier piles and guarded manual collection;
- multiple porters and authored service corridors;
- visitor queues, satisfaction, dissatisfied walkaways, angry faces, tips/bags,
  seating, and decor-derived rating;
- reactive street traffic, sidewalk approaches, crosswalk behavior, and exits;
- department and station upgrades;
- Reputation progression and feature gates;
- three rolling objectives and venue milestones;
- managers, specialist posts, cards, ranks, productivity, and audit strength;
- Expedition and Inspection match-3 event modes;
- offline income, persistent rewarded x2 boost, offers, store UI, daily deals;
- a venue-completion celebration and next-level preview;
- twelve distinct theme definitions and automated geometry/variation checks;
- a substantial automated test suite.

The mechanical comparison is documented in:

- `docs/IBT_PARITY_AUDIT_2026-07-29.md`
- `docs/IBT_DECOR_MONETIZATION_AUDIT_2026-07-29.md`
- `docs/IBT_MECHANICS_AUDIT.md`

Use IBT only as a gameplay-familiarity reference. Do not copy its code, assets,
writing, names, layouts, branded UI, or proprietary expression.

## Confirmed decor diagnosis

The user's observation that purchased decor does not appear is **not caused by
missing PNG/3D assets**.

The complete path exists:

1. `scenes/meta/decor_screen.gd::_on_buy`
2. `scripts/meta/decor_system.gd::buy_decor`
3. `_place` writes `venue_state[venue_id].decor[str(slot)] = decor_id`
4. `EventBus.decor_purchased` emits
5. `VenueFloor` receives the event, invalidates `_props_key`, and calls
   `_rebuild_props`
6. `_build_owned_decor` selects a venue/room anchor
7. `_decor_kind` and `_decor_spec` select a code-drawn painter
8. `_add_prop` creates the visible, navigation-aware node

The live save proves the purchase path worked. Whispering Pines contains:

- slot 0 `oak_bench`
- slot 1 `visitor_benches`
- slot 2 `heritage_arch`
- slot 3 `lily_pond`
- slot 4 `reading_lamps`
- slot 5 `welcome_planter`

Tidewater (`copper_kettle`) currently contains `"decor": {}`.

There are two real product defects:

### A. Venue-scoped placement is not communicated

Decor placement is stored per venue and the six pieces bought in Whispering
Pines do not appear in Tidewater. The player experiences this as “my decor did
not spawn” after moving venues. The UI does not clearly distinguish:

- a globally discovered/owned decor blueprint;
- a piece placed in this venue;
- whether a piece must be bought again per venue;
- what, if anything, carries forward at museum completion.

Choose and consistently implement one understandable rule:

1. **Recommended:** unlock/own a decor design globally, then place it into a
   limited slot in every venue without buying the same collectible again; venue
   placement remains local and economically meaningful.
2. Alternatively, make every purchase explicitly venue-local, explain this
   before spending, and make completion/carryover rules prominent.

Do not silently change the economy. Add save migration and tests for whichever
rule is chosen.

### B. Spawned pieces lack visual identity and salience

Most decor ids are heuristically collapsed by `_decor_kind` into generic
`plinth`, `planter`, `bench`, `banner`, `rug`, `vitrine`, or `statue` painters.
Several named products therefore look like ordinary room dressing, and different
products can look almost identical. A small gold pad/glint is not enough.

Required correction:

- give every sellable decor id a deliberate visual spec or asset mapping;
- ensure the silhouette/color/detail materially differs from nearby base props;
- add a short placement reveal (focus pulse, construction puff, gleam, or camera
  cue) on purchase;
- show the exact room/slot destination in the Decor screen;
- ensure an owned piece is visible at gameplay zoom and cannot hide behind a
  wall, HUD element, or larger exhibit;
- provide at least one before/after visual assertion or screenshot-driven test
  per decor category;
- retain navigation clearance and `VenueFloor` rebuild behavior.

Add an automated integration test that buys one piece in the currently displayed
venue and proves, without reopening the venue:

- the save slot changed;
- `decor_purchased` fired once;
- the floor gained the intended decor node/spec;
- the piece has an on-screen anchor;
- satisfaction/decor points changed;
- save/load restores it.

## Core gameplay work remaining

### P0 — release-blocking gameplay correctness

1. Run the entire test suite and make it reliably green from a clean game state.
2. Add a single documented all-tests runner with a nonzero exit code on failure.
3. Fix the decor semantics and visual feedback described above.
4. Conduct a full six-venue playthrough using normal purchase paths:
   - no test-only level mutation;
   - every objective remains achievable;
   - capped departments are never recommended as bottlenecks;
   - completion cannot occur early;
   - completion cannot become impossible;
   - cash, managers, unlocks, decor ownership, and settings migrate correctly.
5. Verify every route after every decor/staff tier:
   - visitors never cross solid props, desks, walls, or rope lines;
   - porters never cross counters or exhibits;
   - café/rest guests can reach and leave seats;
   - exits cannot deadlock;
   - added staff cannot spawn inside furniture.
6. Test interrupted state transitions:
   - background/kill during purchase;
   - background/kill during venue completion;
   - save during an active queue/porter delivery;
   - device clock forward/backward;
   - corrupted/partial save recovery.

### P1 — core-loop completeness and clarity

1. Audit first-session teaching. Every new mechanic needs one clear introduction,
   then should stop interrupting the player.
2. Make the economic chain readable on the floor and in Statistics:
   arrival/service/transport/value/tips must agree numerically.
3. Confirm manager assignment from a department sheet, replacement, stand-down,
   unlock slots, and specialty filtering all work through normal taps.
4. Finish café/concession behavior as a reusable venue experience:
   seating capacity, service time, satisfaction, spend, tips, failure feedback.
5. Ensure every functional department can visually evolve with upgrades without
   colliding with authored dressing or navigation.
6. Audit manual cashier collection cooldown:
   readable remaining time, no multi-touch abuse, persistence through restart,
   and no bypass of the transport economy.
7. Audit active bags/tips:
   distributed across valid visited areas, reachable, expiry communicated,
   value tied to satisfaction/service/decor, and no inaccessible drops.
8. Ensure the completion celebration replaces all player-facing “Prestige”
   terminology. Legacy internal signal/file names may remain for compatibility.

### P2 — balance and retention validation

1. Re-run first-session, first-day, and first-week simulations after every
   significant economy change.
2. Validate real player pacing, not only accelerated scripts:
   - Level 1 is a short, inviting tutorial;
   - each venue is longer than the previous one;
   - difficulty comes from additional capacity planning and meaningful upgrade
     choices, not only larger numbers;
   - offline income helps but does not trivialize a venue;
   - no single porter/cashier/arrival stage becomes permanently dominant.
3. Validate manager acquisition and rank pacing without purchases and with
   reasonable rewarded-ad use.
4. Validate decor slot tradeoffs between spectacle, income, and seating.
5. Add telemetry events for tutorial steps, department opens, upgrade decisions,
   decor placement, dissatisfaction causes, venue completion time, and drop-off.

### Contextual progress rescue

`balance_core.json -> monetization_tuning.progress_rescue` defines the shared
contract for the user's requested stuck-player safety valve.

Surface an optional rewarded-ad rescue only when all are true:

- the current session has lasted at least `minimum_session_seconds`;
- the player has made no meaningful purchase for `no_purchase_seconds`;
- current income is positive;
- the cheapest actionable progression purchase is more than
  `minimum_upgrade_eta_seconds` away at the current banked-income rate;
- no completion/transition/modal/tutorial is active;
- the placement is loaded, under its daily cap, and outside cooldown/snooze.

The initial reward is 15 minutes of the current **banked** income rate. This is
already the established `instant_cash` value and exceeds the requested 5–10
minute rescue without inventing another currency grant path. The offer must:

- be player initiated, never an automatic interstitial;
- preview the exact cash amount before the ad;
- grant only from the verified reward callback;
- disappear immediately when the player can afford an actionable upgrade;
- be capped at three contextual surfaces per day;
- snooze for 30 minutes when dismissed;
- never claim the player is stuck merely because they chose to save;
- log shown, dismissed, accepted, rewarded, failed, and post-reward purchase.

Add deterministic tests for detection, false-positive suppression, cap/cooldown,
reward calculation, ad failure, forged callback, and the guarantee that every
venue remains completable with zero ad views.

The Store and its catalog/offer implementation remain in Claude's core/release
tranche. Preserve Codex's visual direction and request design review before
shipping new store surfaces. Paid offers may accelerate progress but must never
be required to escape an authored economy deadlock.

## Android and Play Store release work

There is currently no `export_presets.cfg` and no verified Android App Bundle
pipeline.

Claude should:

1. Create a reproducible Android release preset.
2. Configure the final application id, version code/name, icons, orientation,
   permissions, min SDK, target/compile SDK, and release feature flags.
3. Target API 36 for a submission on/after 2026-08-31.
4. Establish release signing without committing private keys or passwords.
5. Produce and install a signed `.aab`/test APK on physical devices.
6. Replace the current store-agnostic stubs:
   - `autoload/ad_service.gd`
   - `autoload/iap_service.gd`
   - `scripts/monetization/consent.gd`
   with production adapters while preserving their tested interfaces.
7. Implement and test:
   - Google Play Billing;
   - acknowledgement/consumption;
   - duplicate receipt protection;
   - restore non-consumables;
   - pending/cancelled/refunded purchases;
   - rewarded ads and failure paths;
   - UMP consent and non-personalized ads;
   - analytics/crash reporting only under declared consent.
8. Ensure release builds never grant simulated ads or purchases.
9. Prepare privacy-policy link/in-game entry, Data Safety answers, ads
   declaration, target audience, content rating, reviewer instructions, store
   listing, screenshots, feature graphic, and support contact.

Do not commit secrets. Use documented environment/local credential configuration.

## Performance and device QA

Before the latest satisfaction-cache optimization, the performance check was:

- monetization integrity tests pass;
- monetization behavior tests pass;
- policy-audit tests pass;
- Tidewater geometry/interaction/economy tests pass;
- one synthetic performance check was marginally red:
  `venue_rates` ×10,000 took ~2134 ms against a 2000 ms threshold;
  match-3 ×1,000 completed in ~603 ms.

Profile before optimizing. The 6.7% synthetic miss is not proof of a frame-time
problem, but release certification should leave the suite green.

Test at minimum:

- low/mid/high Android hardware;
- tall, narrow, wide, and cutout displays;
- 30/60/120 Hz;
- offline/poor network;
- low-memory resume and process death;
- long idle sessions;
- accessibility font scaling and touch targets;
- music/SFX lifecycle and audio interruptions;
- thermal/battery behavior;
- clean install, upgrade install, uninstall/reinstall, and cloud/restore policy.

## Venue system state Claude must preserve

`VenueFloor.VenueTheme` now supports:

- venue-authored rooms and roles;
- multiple storeys/stairs;
- `layout_spread`, which enlarges authored grid distances without enlarging
  furniture;
- `camera_zoom`, which frames a larger building;
- per-venue room names through `DataLoader.venue_dept_name`;
- venue-specific decor anchors;
- code-drawn props and exhibits;
- pathfinding/nav blockers and screen-aware transforms.

Tidewater currently uses:

- `layout_spread: 1.18`
- `camera_zoom: 0.78`

This expands its logical footprint from 15×17 to roughly 17.7×20.1 tiles while
keeping props and waypoints inside the camera. The capability is global, but
other venues have not yet opted into bespoke expansion values.

Do not apply Tidewater's numbers blindly to every level.

## Codex levels 7–12 design mandate (now implemented; preserve it)

Codex has created six new venues in the current data set. Preserve this
mandate while Claude completes engineering and release work.
Their design requirements are:

- each footprint and usable circulation area exceeds the preceding venue;
- increasingly ambitious exterior architecture and surroundings;
- increasingly distinct silhouettes and room topology;
- more departments/experiences or richer adaptations of shared economic roles;
- wider public circulation plus separate staff/service corridors;
- deliberate entrances, multiple exits where scale requires them, and no
  cross-traffic deadlocks;
- progressively richer upgrade-dependent scene evolution;
- venue-specific decor destinations in every major section;
- higher track caps, milestone requirements, upgrade costs, and completion time;
- increased strategic difficulty through capacity interactions, manager demand,
  satisfaction, service quality, and layout—not raw grind alone;
- every room, waypoint, prop, label, station overlay, and navigation route must
  pass geometry and interaction tests.

Claude should keep data/API support capable of more than six venues and avoid
hardcoded arrays or UI assumptions that stop at level 6.

## Useful commands

Compile/boot smoke:

```bash
/home/bustillo/bin/godot441 --headless --path /home/bustillo/godot-saga/repo --editor-pid 0 --quit
```

Run a test:

```bash
/home/bustillo/bin/godot441 --headless --path /home/bustillo/godot-saga/repo --editor-pid 0 --script tests/venue/test_aquarium.gd
```

Launch:

```bash
/home/bustillo/bin/godot441 --path /home/bustillo/godot-saga/repo --editor-pid 0
```

Prefer `grep`/`find` in this environment because `rg` is not currently installed.

## Completion definition for Claude's tranche

Claude's tranche is complete only when:

- the full automated suite is green and has one reliable runner;
- the six existing venues can be completed normally without blockers;
- decor ownership/placement is understandable and visibly works;
- save/load/migration and interrupted transitions are safe;
- production ads/billing/consent adapters pass sandbox/device tests;
- a signed release candidate installs and runs on representative Android devices;
- Play Console declarations and reviewer materials are ready;
- no release build contains simulated rewards/purchases;
- all known P0 issues are fixed or explicitly documented with reproduction,
  severity, owner, and ship decision.

---

# Current delta — authoritative state after the twelve-venue/menu pass

This section is the current-state correction to the historical notes above.
It is intentionally explicit so a new agent can continue without relying on
conversation memory.

## Product objective

The user's final quality bar is: twelve increasingly larger, grander, solvable
museum venues and every player-facing menu should feel commercially polished,
clear, responsive, and rewarding at phone scale, with an original museum
identity. “Inspired by Idle Bank Tycoon” means a comparable idle-management
cadence and presentation standard. It does **not** authorize copying IBT code,
assets, exact writing, layouts, branding, or proprietary behavior.

Codex owns venue composition, authored art direction, layout topology, camera
framing, visual hierarchy, and final menu presentation. Claude owns shared
engineering, persistence, monetization adapters, Android release, and wiring.
Claude may fix defects in shared systems, but should preserve the established
visual language and coordinate any substantial layout or menu redesign.

## Twelve-venue roster (current)

The authoritative order is `DataLoader.venue_order()` from `data/venues.json`:

1. `whispering_pines` — Whispering Pines Hall
2. `copper_kettle` — Tidewater Aquarium (legacy internal id retained for saves)
3. `grand_river` — Grand River Athenaeum
4. `sunspire` — Sunspire Museum
5. `cloudrest` — Cloudrest Citadel
6. `aurora_world` — Aurora World Museum
7. `celestial_conservatory` — Celestial Conservatory
8. `ironwood_citadel` — Ironwood Citadel
9. `pelagic_crown` — Pelagic Crown
10. `chronos_spire` — Chronos Spire
11. `empyrean_palace` — Empyrean Palace
12. `infinite_museum` — The Infinite Museum

Levels 7–12 are authored in `tools/author_venue.py` and generated into
`data/venues.json`. Do not hand-edit generated late-level geometry without also
updating the authoring source. The author check is:

```bash
GRAND_EXHIBIT_REPO=/home/bustillo/godot-saga/repo \
python3 tools/author_venue.py
```

The output should show distinct room bounds and low clipping warnings. Two
known author warnings remain and need visual review rather than blind deletion:
Cloudrest archive reports 18% clipping and Chronos lobby reports 22% clipping.

Late-level identity and scale:

| Level | Identity | Grid footprint | Storeys | Decor slots |
|---|---|---:|---:|---:|
| 7 | moonlit orbital glasshouse | 16×19 | 2 | 12 |
| 8 | mountain fortress / armory | 18×22 | 2 | 14 |
| 9 | coral ocean palace | 21×24 | 3 | 14 |
| 10 | four-storey time monument | 20×27 | 4 | 16 |
| 11 | palace of royal/cloud courts | 26×30 | 4 | 18 |
| 12 | world-spanning museum | 30×34 | 5 | 20 |

The late themes intentionally use larger `layout_spread` and authored
`camera_zoom`. `VenueFloor` now enforces a readable camera floor of 0.48 and
supports bounded mouse/touch drag panning. This keeps the Infinite Museum
legible instead of shrinking the whole campus into a tiny postcard. Do not
remove pan support to make a static screenshot fit; the design is a navigable
campus.

## Balance correction just made

The first expanded campaign simulation exposed a real Aurora progression wall:
Cloudrest-to-Aurora had an accidental cost/value spike of roughly 12.5×. The
late-run cost curve has now been normalized so later venues are harder without
becoming impossible. Source values are in `tools/author_venue.py`; generated
values are in `data/venues.json`.

Current authored late cost records are approximately:

```text
Celestial Conservatory: cost 84e18, base value 1.2e18
Ironwood Citadel:       cost 160e21, base value 2.0e21
Pelagic Crown:          cost 315e24, base value 3.5e24
Chronos Spire:          cost 600e27, base value 6.0e27
Empyrean Palace:        cost 110e31, base value 1.0e31
Infinite Museum:        cost 240e34, base value 2.0e34
```

Cloudrest and Aurora were also reduced from the previous 1000e12/20000e15
cost multipliers to approximately 250e12/480e15. This is deliberately a
balance change, not a test relaxation. Re-run the complete first-session
simulation after this handoff; the interrupted rerun had not yet produced
authoritative post-correction timings.

The invariant remains: venue track caps rise through the introduction and then
hold at the reference-style Level 100 ceiling:

```text
[15, 25, 40, 60, 80, 100, 100, 100, 100, 100, 100, 100]
```

Difficulty should come from larger layouts, more service capacity choices,
decor/satisfaction tradeoffs, managers, and longer but finite upgrade runway;
never from an unbounded Level-200 introductory track or a mathematically
unfinishable cost wall. The zero-ad campaign must remain completable.

## Current menu/art direction state

The player-facing menu suite has been rendered at the target 720×1280 phone
resolution and reviewed. The strongest current screens are:

- Managers: staff-pass carousel with authored procedural portraits, rarity,
  department, level/rank, traits, and assignment controls.
- Statistics: venue title, actionable bottleneck card, management assignment
  summary, visitor-flow bars, earnings, and visitor-experience rating.
- Store: hero offer, rewarded-free section, starter bundles, daily deals, and
  currency/insight categories.
- Lootboxes: clear Field/Specialist/Executive case progression, costs, free
  ad-open path, and drop-rate actions.
- Prestige/completion: “Museum Complete!” celebration, next-level preview,
  carry/leave explanation, and no player-facing Prestige terminology.
- Decor: two-column phone-readable cards, destination room/slot text, sets,
  satisfaction bars, and storage actions. The previous three-column layout was
  too cramped and has been corrected.
- Expedition locked state: now a feature teaser with iconography, rewards,
  progress toward Rep 7, and current reputation—not an empty two-line page.
- Inspection: manager portraits are displayed in a horizontal staff carousel;
  all six stage actions remain visible near the fold instead of being buried
  under a ten-card wrapping grid.

Relevant latest edits:

- `scenes/events/inspection_screen.gd`
- `scenes/events/expedition_screen.gd`
- `scenes/meta/decor_screen.gd`
- `scenes/venue/floor/venue_floor.gd`
- `autoload/economy.gd`
- `data/quests_milestones.json`

The Inspection manager cards must remain real Buttons with manager names in
their text for accessibility and automated input discovery. The visible child
layout is portrait + specialty/rarity + stats + add/team state. Do not replace
this with unlabelled decorative cards.

## Current tests and evidence

Green after the latest edits:

- `tests/events/test_battle_view.gd`
- `tests/events/test_battle_balance.gd`
- `tests/core/test_economy.gd`
- `tests/core/test_satisfaction.gd`
- `tests/qa/test_performance.gd`
- `tests/meta/test_meta.gd`
- `tests/meta/test_venue_progression.gd`
- venue floor, geometry, interaction, theme, variation, aquarium/city tests
- monetization integrity/behavior and policy tests from the existing suite

The performance regression was fixed by caching the fully formatted venue
satisfaction breakdown in `autoload/economy.gd` using live flow and decor
signatures. Latest synthetic result: `venue_rates × 10,000 = 1755 ms` against a
2000 ms budget; match-3 ×1000 remains about 564 ms. Keep the cache input-derived
so direct test/dev state mutations invalidate it; do not replace it with a stale
signal-only cache.

The first-session test previously failed before the cost correction because the
campaign stalled at Aurora and the final museum never opened within seven
simulated days. A post-correction run was started but interrupted before a
result was captured. This is the most important current verification task.

Run it with:

```bash
/home/bustillo/bin/godot441 --headless --path /home/bustillo/godot-saga/repo \
  -s tests/meta/test_first_session.gd
```

Do not mark the project balance-ready until this run proves:

- final museum opens inside seven simulated days;
- final arrival is later than one day and no later than two days under the
  test's stated attentive free-player model;
- every pre-finale venue reaches READY;
- the final venue shows material week-one progress;
- the introductory venue remains a short but meaningful first session.

The reliable test runner is `tools/run_tests.sh`. Use it after inspecting its
current list; it is untracked and should be retained. A command that stops on
the first failure is preferable for release CI, while a local full report may
continue and summarize failures.

## Decor: do not regress the diagnosis

Decor is code-drawn, not missing-file driven. The actual path is:

`DecorScreen._on_buy` → `DecorSystem.buy_decor` → venue save slot →
`EventBus.decor_purchased` → `VenueFloor._rebuild_props` → authored anchor/spec.

The remaining product requirement is making every named piece materially
recognizable and explaining global design ownership versus venue-local
placement. The recommended rule is global blueprint ownership plus a local
placement slot in each venue. Any change must include save migration, a
purchase-and-visible-spawn integration test, satisfaction update, and save/load
round trip. Never “fix” this by copying decor blindly between venues or by
silently granting currency.

## Shared engineering requirements still owned by Claude

1. Complete and harden the full test runner, including all twelve venues.
2. Re-run the corrected first-session campaign and tune only the source balance
   records when the result proves a genuine pacing issue.
3. Finish decor ownership/purchase/placement semantics and unique visual specs.
4. Validate manager assignment/replacement/stand-down and future expansion slots.
5. Finish Promotions/Café as a reusable service/rest destination; player-facing
   department names must come from `DataLoader.venue_dept_name`, not hardcoded
   “Promotions” strings.
6. Verify cash collection cooldown, bag placement, tips, dissatisfaction faces,
   and porter delivery under normal save/load and process death.
7. Implement the production Google Play Billing, rewarded ads, consent, privacy,
   restore, receipt, and failure adapters behind the existing interfaces.
8. Produce a signed Android App Bundle and device-test it on representative
   low/mid/high hardware, including process death, offline, clock abuse,
   orientation/cutouts, audio interruptions, and accessibility scaling.
9. Prepare Play Console metadata: application id, versioning, icons, privacy
   URL, Data Safety, ads declaration, target audience, content rating,
   reviewer instructions, screenshots, feature graphic, support contact.

The user explicitly wants a contextual rewarded-ad rescue when progress is
genuinely stuck. The contract is in `data/balance_core.json` under
`progress_rescue`: minimum five-minute session/no-purchase gate, positive
income, cheapest actionable upgrade ETA over ten minutes, 15 minutes of current
banked income, 15-minute offer cooldown, 30-minute dismiss snooze, and three
offers/day. It must be optional, player initiated, preview the exact reward,
grant only from a verified callback, and never be required for solvability.

Google production setup still requires the user's final package id, AdMob app
and rewarded placement ids, UMP consent/privacy configuration, Play Billing
product ids, signing identity, privacy-policy URL, and store-account access.
Use test ad ids until the release build is approved; never ship simulated
rewards or purchases in a production flag.

## Visual review harness

`tools/shot.gd` safely isolates the save and captures a 720×1280 SubViewport.
It can preview any venue or popup without mutating the live user save:

```bash
/home/bustillo/bin/godot441 --path /home/bustillo/godot-saga/repo \
  -s tools/shot.gd -- \
  out=/tmp/venue12.png warm=2 venue=infinite_museum cash=1e45 levels=100

/home/bustillo/bin/godot441 --path /home/bustillo/godot-saga/repo \
  -s tools/shot.gd -- \
  out=/tmp/store.png warm=2 cash=1e12 gems=1000 \
  open=res://scenes/store/store_screen.tscn
```

Graphical screenshot commands require the normal renderer (not `--headless`)
and may require the environment's approved GUI execution. Do not use the live
save as a screenshot seed.

## Safety and handoff rules

- Preserve the dirty worktree and all untracked `.gd`, `.tscn`, `.uid`, shader,
  audio, test, documentation, and authoring files.
- Never run `git reset --hard`, `git clean`, broad deletion, or checkout of
  unrelated files.
- Keep stable internal ids (`promotions`, `ticket`, `archive`, `gallery`) as
  save/API contracts while using venue-authored display names.
- Keep player-facing “Museum Complete!” and next-level language; internal
  `prestige_*` compatibility names may remain.
- Never copy IBT proprietary code/assets or represent reverse-engineering as
  implementation guidance.
- Report incomplete or unverified work explicitly. A green structural test is
  not visual proof, and a visual screenshot is not proof of persistence or
  balance.

## Definition of done

The project is ready for Play Store review only when the current twelve-venue
campaign simulation is green, every venue can be completed without ads, decor
is visibly and semantically understandable, the complete menu suite has been
reviewed at phone scale, navigation and save/migration tests pass, performance
is within budget, production ads/billing/consent are integrated and tested, and
a signed Android release candidate has been installed and exercised on real
devices. Until then, leave the goal active and keep the remaining risks visible
to the user.
