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

## 2026-07-24 · Game-Feel Engineer · Living floor replaces menu-panels as the Museum tab
Player verdict on M1-M5: "it's only menus." Phase 2 renders the existing (correct) economy sim
live: procedural chibi cast (original designs — IP guardrail: IBT is mechanics-inspiration only,
zero copied expression), visitor FSM door->queue->served->gallery->exit, porter loops window->
vault, choke made visible (full ropes / overflowing stacks / sparse floor), tap-zone bottom-sheet
upgrade cards with IBT-style bold buttons. Palette brightened per user call (overrides muted
default). Economy autoload untouched; floor reads venue_rates at 0.5Hz. 20/20 suites green,
motion verified via xvfb frame deltas.

## 2026-07-25 · Handover · Typeface replaced, font-fallback hack removed
Kenney Future renders "X" as "H" and "$" as "S". ui_kit dodged that by applying
the display font only to strings containing neither glyph, so the UI mixed two
typefaces at random — the single biggest reason it read as unfinished. Replaced
with Quicksand Bold/Medium (OFL-1.1, ~96KB per weight) plus a real type scale and
ThemeDB.fallback_font so no Control silently falls back to Open Sans.

## 2026-07-25 · Handover · Palette pushed to high chroma
The SPEC §2 "warm museum" scheme was built from desaturated earth tones and read
as beige office software on a phone. Replaced with a deep indigo shell and
saturated, hue-separated room accents. Cards and buttons moved off the tinted
Kenney parchment nine-patches — parchment carries its own beige value, so tinting
it with saturated colour produced mud — onto flat rounded styleboxes with a
chunky bottom lip that collapses on press.

## 2026-07-25 · Handover · Cast is baked, not drawn live
Characters are rasterised once per look into 4x supersampled textures and blitted
as a single quad. This fixed the aliasing (`draw_colored_polygon` has no edge
smoothing, and the antialiased stroke flag both broke canvas batching and only
smoothed outlines) and cut the cast from ~1189 draw calls to ~42, which in turn
made per-figure shading detail free. Headless has no rendering context, so the
baker no-ops and Character falls back to drawing primitives — the suites run that
path. A blank read-back is never cached: transparent means "render target not
ready", and caching it left three of four staff uniforms permanently invisible.

## 2026-07-25 · Handover · True isometric, floor bleeding off-screen
Phase 2 shipped a flat plan; the parity reference (Idle Bank Tycoon) is a 2:1
isometric diorama. Rebuilt on an iso grid: the simulation runs in tile space and
projects only at draw and tap time, which let the visitor/porter FSM come across
unchanged. An iso diamond's bounding box is (grid.x + grid.y) * TILE/2 on BOTH
axes, so its aspect is fixed by the tile ratio alone and no floor plan reshaping
will make it fill a portrait screen — so the floor is drawn wider than the
viewport and clipped, which is what the reference games do. Props are individual
Y-sorted nodes, not one static layer, so a visitor can stand behind a counter and
in front of a bench in the same frame.

## 2026-07-25 · Handover · Mobile correctness pass
stretch/aspect keep -> expand ("keep" letterboxed every 19.5:9 and 20:9 phone).
HUD and BottomNav became self-sizing PanelContainers; the HUD's hardcoded 136px
was shorter than its content and painted over the Venue Progress strip. Safe-area
insets are mobile-only and capped at 12% per edge: DisplayServer.get_display_safe_area()
reports the whole screen work area on desktop, which handed the nav 254px of
phantom inset and tore the layout in half. 2D MSAA is NOT enabled — GLES3 does not
implement it and warns; smoothing comes from the supersampled bake instead.

## 2026-07-25 · Handover · z_index is global, not parent-scoped
Two bugs from the same misconception. A negative z_index on the floor's static
layer put it behind main.gd's full-screen background, so the entire diorama
vanished. A large positive z_index on the room-label layer painted plaques over
the department bottom sheet. Layers now use small values relative to the cast
(plaques 2, cash floats 1, sheet 8-9) rather than large absolute ones.

## 2026-09-30: modern chrome, matte diorama

The owner found the cream-and-brass "toy chrome" antique and the 3D too
glossy, and pointed at a matte, softly lit low-poly diorama as the target.

- **UI:** white cards on a soft neutral page, 1px hairlines and wide faint
  shadows instead of thick brown rims; pill buttons, one calm green-teal
  action colour (#2B8468) with white lettering; tinted badges instead of
  solid ribbons; a plain tab bar with a pill behind the active icon;
  notification dots instead of glowing tiles. Inter SemiBold/Medium replaces
  Quicksand in the interface (Quicksand stays for signs inside the 3D world).
  All in `scripts/ui/museum_chrome.gd` and `scripts/ui/ui_kit.gd`.
- **3D:** `scripts/render/toy_look.gd` gives the museum, café and dig site
  one light rig (warm-neutral ambient 0.4, sun 0.6, wide soft shadows,
  saturation 0.78) and flattens every material to matte at load time. The
  Blender kit's default roughness is now 0.88 to match.

## 2026-09-30: open-plan museums ("a mall retrofitted as a museum")

The owner liked the new art but not the layout: every museum was a set of
walled rooms. The brief: open yet grand, the vibe of an open mall converted
into a museum.

- **No partitions.** Each storey is one concourse of large warm-stone slabs.
  Walls between rooms on the same level are not built; the outer shell stays.
- **Departments are zones,** each an inset floor in its own finish with a
  trim border, like a store front on the mall floor, and a sign in the
  department's colour with its (translated) name, on the back wall or hung
  over the zone.
- **Grandeur from structure:** a colonnade stands where the walls ran
  (columns at each old wall end, flanking what were doorways, and every
  3.5 grid units), and every open edge, the street front and the lip of each
  raised storey, is a glass balustrade, so multi-storey museums read as
  mezzanines round a mall atrium, joined by the existing glass lifts.
- Room data is unchanged: the rules (queues, stations, exhibit views, the
  store room) still read the same rectangles, and navigation is baked from
  the shell, so visitors simply walk the open floor.

