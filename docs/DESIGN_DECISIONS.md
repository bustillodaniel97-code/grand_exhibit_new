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
