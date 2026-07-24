# DESIGN DECISIONS LOG — Grand Exhibit

Format: date · role · decision · rationale. Newest last. Agents append here on their branch ONLY
if the decision is confined to their files; cross-cutting calls are made by the Executive
Producer (main agent) and recorded on main.

## 2026-07-24 · Executive Producer · Keep the Natural History Museum theme
Handoff default theme maps 1:1 onto every mechanic (visitors/ticket halls/archive carts/docents/
inspections/decor) with zero weakening, and no top idle-tycoon competitor owns it. Working title
stays "Grand Exhibit".

## 2026-07-24 · Lead Engineer · Procedural placeholder art instead of downloaded packs
M1 requires "placeholder-but-licensed" art. Network asset pipelines are flaky in this build
environment, so all placeholder visuals are drawn in code (StyleBoxFlat + canvas primitives) in a
single cohesive warm-museum palette (SPEC §2). This is original work we dedicate CC0 in CREDITS.md.
A Kenney CC0 pass is queued for M4 polish.

## 2026-07-24 · Lead Engineer · One-scene-per-screen, built from code
Every screen is a Control script that builds its widget tree in _ready() (no .theme, no binary
art deps). Screens reference each other only by path string via PopupManager (SPEC §11).
Rationale: six agents build UI in parallel with zero scene-file merge conflicts and no
cross-branch compile dependencies.

## 2026-07-24 · Lead Systems Designer · Three tracks per department, all meaningful
promotions.value = audience quality (multiplies cash per visitor); archive.value = cart capacity
(multiplies transport); gallery.speed = tour flow (multiplies gallery bonus). This preserves the
mandate "add staff / speed / value" on every department without dead stats.

## 2026-07-24 · Lead Engineer · Log-space BigNumber (mantissa + base-10 exponent)
Floats die at 1e308; idle economies blow past that. m*10^e with m in [1,10) gives arbitrary
range with float-grade precision, exact K/M/B/T/aa.. notation, and cheap serialize {"m","e"}.

## 2026-07-24 · Lead Engineer · Save integrity via sha256 checksum envelope
Corrupt/tampered saves rename to .bak and start fresh rather than crash — QA mandate.

## 2026-07-24 · Lead Engineer · Ads/IAP behind debug-first interfaces
AdMob/billing SDKs are platform exports; this build ships interfaces + debug stubs (ads succeed,
purchases succeed) so all six RV placements and the full IAP catalog are playable and testable
today. Release flip: debug_ads/debug_iap = false + SDK plugin.

## 2026-07-24 · Executive Producer · SPEC SIM MODEL amended (all tracks meaningful)
Lead Engineer flagged that the literal SPEC §3 formula left promotions.value, archive.value and
gallery.speed as no-ops while UI sells them. Amended SPEC + economy.gd: promotions.value =
audience quality (multiplies cash per visitor), archive.value = cart capacity (multiplies
transport), gallery.speed = tour flow (multiplies gallery bonus). Neutral at level-1 base stats
(all 1.0), so existing test identities hold. No-op upgrades would violate the spirit of the
handoff's "increase value per unit" mandate; shipping them was not an option.

## 2026-07-24 · Lead Engineer (integration) · Headless test bootstrap pattern settled
Under `godot -s`, autoload singletons come up as live root children AFTER the entry script
compiles. Suites therefore run from `_initialize()`/deferred `run()`, fetch singletons via
`root.get_node("GameState")` etc., and `load()` (never const-preload) system scripts. Manual
double-instantiation of autoloads is forbidden — it shadows real singletons. All branch suites
follow this; QA keeps it.

## 2026-07-24 · Meta Engineer · Decor sets carry "id" mirror of "set_id"
DataLoader._index_by_id keys dicts by "id"; SPEC's set schema named it "set_id". Resolved
data-side (sets carry both keys) so the shared autoload stays untouched.

## 2026-07-24 · Executive Producer · Bundle-first delivery over this filesystem
The /mnt mount silently truncates files >100 MiB and eats push object transfers (refs arrive,
objects don't). Team protocol: agents deliver branches via git bundle files (atomic, verified)
in addition to push; integration fetches from bundles when refs dangle. Godot itself ships to
agents as a zip on the mount.

## 2026-07-24 · Managers Engineer · "NEW" badge = owned-but-unviewed this session
Card-collection UX reading: owned (>=1 card) managers show NEW until first tap in the screen
session; 0-card managers render as locked silhouettes ("?", "Undiscovered").

## 2026-07-24 · QA Lead · M5 hardening verdicts (full report in tests/qa)
Clock-cheating clamped (rollback→0, far-future→cap), v1→v2 migration + checksum-corruption
recovery verified, aa+/1e45 overflow stable (m∈[1,10) invariant), ad/IAP failure paths grant
nothing, venue_rates 10k calls = 1.34s / match-3 1k boards = 0.5s, policy audit clean
(rates published, prices end in 9, CREDITS has no NC/ND). Headless teardown memory spike
documented as engine-level, non-gameplay. One fix shipped: README documents debug flag flip.

## 2026-07-24 · Executive Producer · Visual audit via xvfb + viewport capture
Headless tests prove logic, not pixels. Every screen was rendered under Xvfb and audited as
PNG: venue shell, store, prestige, managers, lootboxes, decor, both event gates, and the
match-3 battle board. Two layout defects found and fixed: popup card had no height floor
(collapsed to a strip) and word-wrapped labels in HBox rows with expand-fill siblings
squeezed to 1-char columns (prestige milestones, decor set rows). PopupManager now grants
648x896 to every screen; squeezed labels set AUTOWRAP_OFF.

## 2026-07-24 · Executive Producer · Milestone M1-M5 closed
All five milestones delivered as data-driven systems with 19 headless suites green.
Android export not produced in this environment (export templates not installed; /mnt mount
truncates files >100MiB) — documented in README as the on-device next step.
