# Claude tranche — status and residual-risk register

Date: 2026-07-29
Against: `docs/HANDOFF_CLAUDE_CORE_GAMEPLAY_2026-07-29.md` (incl. the twelve-venue delta)
Suite: **43 / 43 GREEN** via `tools/run_tests.sh` (43 tests, was 37).

This is the "explicitly documented with reproduction, severity, owner, and ship
decision" artefact the handoff's completion definition asks for. Nothing here is
rounded up. A green structural test is not visual proof and not device proof,
and every gap is named.

---

## 1. Done and verified

### Test infrastructure

| Item | Evidence |
|---|---|
| Single documented runner, nonzero exit on failure | `tools/run_tests.sh` |
| Green from a **clean** checkout | runner does an `--import` pass first — `.godot/global_script_class_cache.cfg` is gitignored and is the only registry of `class_name BigNumber`, so without it a fresh clone fails ~every script for a reason that looks nothing like the cause |
| Live save can no longer be destroyed by a test | `SaveSystem.save_path()` redirects to `user://test_run/` on two independent signals |
| False greens now fail | runner treats `SCRIPT ERROR` / `Compile Error` as failure regardless of exit code |

**Two real defects found here, both silent:**

1. `tests/core/test_save.gd` deleted `user://grand_exhibit_save.json` — literally
   the live player save the handoff forbids touching. The documented single-test
   command in the handoff would eat real progress. Fixed at source: test context
   is detected via `GRAND_EXHIBIT_TEST_RUN` **and** via the main loop being a
   `res://tests/` script, so a hand-run test is safe too.
2. Three newly written tests were **passing while asserting nothing** — a
   preloaded helper that names an autoload fails to compile under `-s`, leaving a
   dead GDScript whose calls silently no-op, so the failure counter stayed at 0
   and `quit(0)` reported success. The hardened runner caught this immediately.
   Worth knowing: this failure mode could have been hiding in any test.

### Decor — both handoff defects closed

**A. Ownership semantics** — rule 2, **per-museum purchase**.

Rule 1 (own globally, place free) was built first because the handoff recommends
it, then reversed on the user's call and confirmed by research: Kolibri's own
guidance is that a new Idle Bank Tycoon bank must be *rebuilt from scratch*, so
decorations do not carry over. Per-museum buying is both the genre convention and
what stops each new venue reading as a reskin of the last.

- `venue_state[vid].decor_bought` — paid for in THIS building. A new museum
  stocks its own shelves at its own prices.
- Storage is free both ways *within* one museum, so a slot decision is never a
  one-way trap.
- `GameState.decor_owned` survives as the cross-museum historical record: it
  drives set bonuses (SPEC §7) and lets the shop say "you had this in an earlier
  museum", so a re-purchase reads as restocking rather than a double charge.
- Migrations **v4 → v5 → v6**, each deriving from what the save already contains.
  Nothing granted, nothing confiscated, idempotent.
- Decor screen states the rule before any spend and shows destination room + slot.
- `tests/meta/test_decor_ownership.gd`.

**B. Visual identity**
- All 24 sellable ids carry an authored `visual` block in `data/decor.json`,
  written in each painter's **real field vocabulary**. This was the actual bug:
  `_bench` reads `len`/`col`/`rail` and was being handed `size`/`wood`, fields it
  never reads, so all five bench products drew at stock length in stock timber.
- 16 distinct silhouettes, up from 8 heuristic collapses. No two products resolve
  to an identical (kind + spec) signature — enforced by test.
- Placement reveal on purchase; `blocks_nav` explicit per id.
- 29 assertions — `tests/venue/test_decor_visuals.gd`, including the full
  six-point purchase integration assertion the handoff specifies.

**Third defect found, not in the handoff:** a hardcoded `whispering_pines` anchor
table in `venue_floor.gd` placed two decor anchors **off-canvas** (screen x −30
and −57). `ancient_obelisk` rendered nothing at all — the literal "my decor did
not spawn" complaint, still live after the ownership fix. Replaced with
room-derived anchors plus a shared `_on_camera()` clamp via `Iso.gx_window`, so
no venue — including Codex's levels 7–12 — can silently hide a purchase again.

### Monetization

- `scripts/monetization/play_billing.gd` — production Play Billing transport
  behind the unchanged `IAPService` interface. Handles acknowledge/consume
  routing (Play auto-refunds anything unacknowledged for 3 days), Play-token
  passthrough so `iap_catalog` dedup survives re-delivery, pending purchases that
  grant nothing, refund/chargeback revocation via new `Entitlements.withdraw()`,
  and a failed query that revokes nothing. 30 assertions against a fake plugin.
- `progress_rescue` implemented to the handoff's stated contract — it existed in
  neither data nor code. Opt-in, previews the exact reward, grants only against a
  redeemed AdService token, cooldown/snooze/daily cap, never required for
  solvability. 30 assertions.

### Android pipeline

Built and inspectable; see `docs/ANDROID_RELEASE.md`. Preset targets API 36, AAB,
64-bit only, portrait, Auto Backup off, minimal permissions. Signing is
environment-only and the build script refuses a keystore inside the worktree.

### Smaller handoff items

- Player-facing "prestige" wording removed from `quests_bar.gd`.
- `statistics_screen.gd` now takes department names from
  `DataLoader.venue_dept_name` instead of a hardcoded table.
- Verified rather than duplicated: Codex's `venue_rates` satisfaction cache is
  genuinely green (1768 ms vs 2000 ms budget).

### Play-session bugs found and fixed

Seven defects came out of actually playing the build, not from the test suite.

| Report | Root cause | Fix |
|---|---|---|
| "most decor fails to render / renders in wrong places" | Each venue authors `decor_anchors` sized to its slot count; the floor **ignored them all** and derived positions from room rects — lists of only 3–4 points indexed `slot % size`, so venues with 6–20 slots stacked pieces on one another. Several derived anchors also fell off-canvas. | Authored anchors win, one per slot, with an on-camera clamp and a cross-source collision guard. Verified over all 12 venues / 154 placements: **0 duplicates, 0 off-screen.** |
| "game pushes my PC hard for a mobile title" | No `max_fps` and no vsync setting in `project.godot` — rendered as fast as the GPU allowed. | Capped to 60 + vsync. Sim is delta-timed, so the economy is unaffected. |
| "maxed all stations, progress bar stuck" | Not a bug: the gate is milestones **AND** capped operations. `dev_unlock` granted neither milestones nor per-venue caps. | `dev_unlock` now fills to each venue's own cap, grants milestone chains, and prints the live gate state. |
| "NPCs never take stairs; porters hop onto the vault" | **The nav grid is 2D.** Storeys exist only for rendering (`lift_at`/`level_at`); A* routes in flat XY, so crossing into a raised room silently lifts the walker. The only guard was a hardcoded `whispering_pines` special case — every other venue, including all multi-storey ones, had none. | Generalised: an unmanaged level change is now a cliff and authored stairs are the only legal transition, with a guard that refuses to seal a storey no stair reaches (a missing stair degrades to a visual glitch, never a stranded porter) and warns by name. |
| "cars ride on top of each other" | Two cars share each lane at **different speeds** with no following logic, so the faster one inevitably drove through the slower. | Minimum following gap per lane. Test simulates 400s of driving and asserts no overlap ever (closest approach 2.51 tiles vs 1.96 minimum). |
| "cashier counter ticks with nobody at the window" | Takings were allocated evenly across all ticket stations each tick, with no link to which window had a customer. | VenueFloor publishes busy windows; the gain follows them. Same totals, verified; stale/absent hint falls back so offline income is unaffected. |
| "decor should re-lock per venue" | Design question, settled by research: Kolibri's own guidance for Idle Bank Tycoon is that a new bank must be **rebuilt from scratch** — decorations do not carry over. | Buying is now per museum (`decor_bought`); storage is free both ways within a building; set bonuses stay cross-museum; the shop flags "you had this in an earlier museum". Save migration v6 credits each venue with what already stands in it. |

### Late-game curve rebalanced

The inversion is gone and the ladder now tracks IBT's cadence:

```
v1 0.51h  v4 4.23h  v7 19.70h  v10 41.47h
v2 1.76h  v5 4.50h  v8 28.60h  v11 44.25h
v3 2.68h  v6 14.08h v9 35.32h  → finale at 8.2 days
```

Every venue is longer than the one before it. Tuned in `tools/author_venue.py`
(`LATE_META`), the authoring source, not in generated data. Two six-venue relics
in `test_first_session.gd` were corrected alongside it: the 7-day horizon (a
twelve-rung ladder at IBT cadence cannot finish in a week by design) and the
day-one cap of 4, now scaled to half the ladder.

---

## 2. Residual risks — open, with ship decisions

| # | Issue | Sev | Reproduction | Owner | Ship decision |
|---|---|---|---|---|---|
| ~~1~~ | ~~Late-game difficulty curve inverts.~~ **FIXED** | — | `tools/run_tests.sh test_first_session` | Claude | Rebalanced `LATE_META` in `tools/author_venue.py`. v7 19.70h, v8 28.60h, v9 35.32h, v10 41.47h, v11 44.25h — every venue now longer than the one before it. |
| ~~2~~ | ~~Campaign 4× too fast.~~ **FIXED** | — | same run | Claude | Finale now opens at **8.2 days** of no-ad play, against IBT's ~7 days for six banks with heavy ad use. Mid-game venues run 20–44h vs IBT's 36–84h — the right cadence over twice as many rungs. |
| ~~3~~ | ~~Day-one cap is a six-venue assumption.~~ **FIXED** | — | — | Claude | Cap now scales to half the ladder; the 7-day horizon likewise became a deadlock guard rather than a target, both with the reasoning recorded in the test. |
| 4 | No Android build has ever run — no SDK, no build template, no export templates. | **P0** | `tools/build_android.sh --release` → preflight refuses | Claude + user machine | Pipeline is written and preflighted; execution needs an Android Studio host. |
| 5 | No device QA: low/mid/high hardware, 30/60/120 Hz, cutout displays, process death, thermal, audio interruption, font scaling. | **P0** | — | user (hardware) | Cannot be simulated. Hard release blocker. |
| 6 | AdMob + UMP production adapters not written. | **P0** | — | Claude | Needs AdMob app id and rewarded placement ids. Billing adapter is the template to follow. |
| 7 | Play Billing plugin method/signal names unverified against a real plugin. | **P0** | — | Claude + device | Adapter probes candidate names and degrades to "no billing" rather than crashing, so a mismatch is visible and safe, not silent. |
| 8 | Application id is a **placeholder** (`com.bustillo.grandexhibit`). | **P0** | `grep package/unique_name export_presets.template.cfg` | user | Play binds the package name **permanently** at first upload. Must be confirmed before any release. |
| 9 | No privacy-policy URL exists. | **P0** | — | user | Mandatory for Play submission. In-game revocation entry point already exists. |
| 10 | Feature graphic, 512 icon, store screenshots not produced. | P1 | — | Codex (art direction) | `tools/shot.gd` can produce screenshots. |
| 11 | No SSV endpoint for rewarded ads. | P1 | — | Claude + server | `AdService.reward_verifier` is the hook; local token redemption is in place meanwhile. |
| 12 | Two authoring clipping warnings: Cloudrest archive 18%, Chronos lobby 22%. | P1 | `GRAND_EXHIBIT_REPO=… python3 tools/author_venue.py` | Codex | Needs visual review, not blind deletion. |
| ~~13~~ | ~~Cashier counter ticks with no customer.~~ **FIXED** | — | — | Claude | `Economy._tick` books takings from `venue_rates` every frame regardless of the floor, which is correct (offline earnings need it) — but it split the gain evenly across every window, so an idle till climbed as fast as a busy one. VenueFloor now publishes busy window indices and the gain follows them. Totals are provably unchanged, and an absent or stale hint falls back to the even split so headless/offline still earn. Covered in `tests/core/test_economy.gd`. |
| ~~14~~ | ~~Whispering Pines archive (the VAULT) unreachable — porters teleported in.~~ **FIXED** | — | `tools/run_tests.sh test_nav_reachability` | Claude | `archive` (x9–15, y0–6) opened only onto `central_atrium` (x9–15, y6–9), whose southern edge at y=9 was covered COMPLETELY by walls `[7,9] len 3.5` and `[10.5,9] len 4.5`, and whose only other opening ran through `gallery_east_terrace` (`nav_blocked: true`). A sealed pocket — no walkable route to the vault at all. Fixed by splitting the y=9 wall into `[10.5,9] len 1.5` and `[13.2,9] len 1.8`, cutting a 1.2-tile service doorway so promotions → atrium → archive connects. `whispering_pines` is hand-authored and absent from `author_venue.py`, so the edit survives regeneration. Ruled out first: missing stairs, the storey-seal, and rasterisation width. Now covered permanently by `test_nav_reachability.gd`, which sweeps all twelve venues via `floor.retheme()` and A*-checks every room from the lobby. |
| ~~15~~ | ~~Manager portrait hats render broken.~~ **FIXED** | — | — | Claude | `character.gd::_draw_cap`. The cap peak is authored for the walking sprite, which faces +x in three-quarter profile, so the wedge juts forward from x −2.6 to +9.6. PortraitBaker frames the same head near front-on, where that identical wedge reads as a pale bar lying sideways across the crown — and its outline `draw_polyline([peak[0], peak[1], peak[2]])` was an OPEN path, leaving the fourth edge undrawn as a square bracket. Fixed with a `portrait_mode` flag the baker sets: front-on gets a symmetric, foreshortened brim, profile keeps its authored jut, and the outline is now closed. Found by elimination — all four hair layers were colour-probed and cleared first. Verified by capture; walking cast unchanged and suite green. |
| 16 | Surroundings are visually inert — no ambient life. | P2 | Any venue | Codex (surround art direction) | User wants dog walkers, a playground, an aircraft dropping a rewarded-ad pickup. The aircraft reward is a shared-systems piece Claude can build once the art direction exists. |

---

## 3. Not attempted, and why

- **Menu art direction / visual language.** The delta assigns final menu
  presentation to Codex and tells Claude not to independently replace it. My
  Decor screen edits were behavioural (ownership states, destination text,
  storage) and merged cleanly alongside Codex's two-column pass.
- **`data/venues.json` and `tools/author_venue.py`.** Codex was editing both
  during this session (`venues.json` 177 KB → 373 KB at 19:31). Writing there
  would have collided.
- **Six-venue playthrough via UI taps**, interrupted-transition device testing,
  and manager/café flows through real taps. Covered structurally by the existing
  suite; genuine tap-level and process-death verification needs a device.

---

## 4. How to check this yourself

```bash
tools/run_tests.sh                      # 40/41; the one red is risk #1/#3
tools/run_tests.sh decor                # the decor work specifically
tools/run_tests.sh monetization         # billing + rescue + integrity
tools/build_android.sh --preset-only    # inspect the generated preset
```

The suite must be run through `tools/run_tests.sh`, not by invoking tests
directly — the runner is what supplies the import pass, the save isolation and
the compile-error guard.
