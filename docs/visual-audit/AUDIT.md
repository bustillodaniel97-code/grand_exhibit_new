# Grand Exhibit: Visual Audit vs Idle Bank Tycoon

Audit date: 2026-09-28. Build audited: the `visual-overhaul` branch as of commit `56bf1dd`. I made no changes to it. All captures were taken from a throwaway copy of the project, with APPDATA redirected so no real save was touched.

Screenshots are in [`shots/`](shots/) next to this file. They are real runtime captures from Godot 4.4.1 using the project's own harness (`tools/shot.gd`, 720x1280 SubViewport, GL Compatibility), with cash, levels and venues seeded. The late-game state came from `tools/dev_unlock.gd`, run against the audit copy's save only. Competitor references are the Google Play and App Store listing screenshots. I viewed them in the browser and did not save them locally.

> Note: the brief says 540x960, but the project is **720x1280** (`project.godot` → `window/size/viewport_*`). All pixel numbers below are in 720x1280 design space.

---

## 1. Verdict

Grand Exhibit has a lot of solid systems work: 12 venues, a Blender-rendered cast of 36 looks with 8-frame walks, porters with carts, a city surround, per-station chips, manager cards, a store with rendered bundle art, and a match-3 event. Visually it sits clearly **below Idle Bank Tycoon (IBT)** on the things a player sees in the first 10 seconds:

- **Color.** The palette is muted and desaturated, graded toward teal/grey.
- **Characters.** They are tiny (about 22–30 px tall at the default camera), have no outline, and all look alike.
- **Exhibits.** Hero pieces are primitive "toy" models: capsules, spheres and rings.
- **Progression.** It is barely visible. Museum 12 fills the same screen area as museum 1, stands in the same suburb of identical houses, and has the same crowd cap (34).
- **Feedback.** Upgrades, level-ups and collections produce almost no juice: no particles, no celebrations, and a toast for a reputation level-up.
- **UI.** Dark-navy "admin panel" styling eats 27% of the screen and never shows the game world or characters inside panels.

IBT wins on three things:
- Saturated per-room color with thick outlines.
- A dense, readable workforce.
- Visible "stuff piling up" rewards (vault money piles) plus a derelict-to-renovated transformation.

Grand Exhibit has a real opening to beat IBT, because a museum's content (dinosaurs, whales, orreries, thrones) is far more spectacular than bank desks. Today that content is rendered so small and so plainly that the advantage is thrown away.

---

## 2. Inventory

Severity: **S1** = hurts first impression or store conversion; **S2** = clearly below the competitor; **S3** = polish.

| Area / screen | Current state (screenshot) | Key problems | Sev |
|---|---|---|---|
| First launch, museum 1 empty | `00_fresh_start.png` | Only 2 visitors on screen. Building fills about 45% of the world view; the rest is identical suburban houses and grey road. No roof or facade, so the "museum" reads as a floor plan. | S1 |
| M1 Whispering Pines Hall (natural history) | `01_whispering_pines.png`, `_far`, `_zoom` | Single low-walled storey. The one hero piece (a dino skeleton, `art/environment/whispering_pines-skeleton.png`) is about 70 px wide at the default camera. Beige/khaki floor on khaki lawn, low contrast. | S1 |
| M1 fully upgraded | `36_unlocked_main.png` | Looks almost identical to `00_fresh_start` apart from extra ticket desks. Maxing a museum does not change its look. | S1 |
| M2 Tidewater Aquarium | `02_copper_kettle.png`, `_zoom` | Pale white/cyan interior with small tanks. The water feature is a flat blue lot outside. No big tank or tunnel moment. | S2 |
| M3 Grand River Athenaeum | `03_grand_river.png` | Brown bookshelves on brown floor. Only 4 exhibits in the data; the centre globe is tiny. | S2 |
| M4 Sunspire Gallery (dunes) | `04_sunspire.png` | First upper storey (arcade + stair), which is good. The "dunes" setting is just a tan recolor of the same houses and roads; no pyramid or obelisk landmark outside. | S2 |
| M5 Cloudrest Citadel (alpine) | `05_cloudrest.png` | Navy truss balconies. The "alpine" surround is a grey-green recolor; no mountains, snow or cliff. Very few exhibits are readable. | S2 |
| M6 Aurora World Museum (night) | `06_aurora_world.png` | Best mood of the set (dark plaza, dome buildings), but the interior is a white tile grid with tiny props. The "orrery" hero is about 50 px. | S2 |
| M7 Celestial Conservatory | `07_celestial_conservatory.png` | Green glasshouse arches are the best silhouette in the game. The interior is still a flat cream grid, with no canopy or glass roof overhead. | S2 |
| M8 Ironwood Citadel | `08_ironwood_citadel.png` | Arched windows and one stair. The "Iron Wyvern" hero (`ironwood_citadel-iron_wyvern.png`) looks like a toy airplane. | S1 |
| M9 Pelagic Crown | `09_pelagic_crown.png`, `_zoom` | Round lagoon tank is the best hero in the game. Whale skeleton (`pelagic_crown-crown_whale.png`) is a string of beads. Pale blue on pale blue. | S2 |
| M10 Chronos Spire | `10_chronos_spire.png` | Three storeys, but the "spire" is a box with no clock tower silhouette. The "Age Engine" hero is two gears on a gallows frame. | S1 |
| M11 Empyrean Palace | `11_empyrean_palace.png`, `42_empyrean_zoom.png` | Throne/carriage/fountain set dressing is the richest. The hall is very empty of people (2 staff visible at 2.6x zoom), and the petal fountain is a flat disc. | S2 |
| M12 The Infinite Museum (finale) | `12_infinite_museum.png`, `_zoom` | The "finale" is the same screen size as M1 (camera zoom 0.50 vs 0.72 cancels its 2.5x larger footprint). The Colossus of Ages (`infinite_museum-colossus_of_ages.png`) is a mannequin holding a globe. Same surrounding houses as M1. No sense of arrival. | S1 |
| HUD (top + bottom) | every world shot | Top block 0–195 px (15%) plus bottom dock and nav 1132–1280 px (11.5%) is **27% of the screen** before the Stats/Decor rail. Dark navy with small low-contrast text; "Insight 0" and a 5-segment venue bar compete for attention. | S1 |
| Station chips / collect | `40_maxzoom_a.png` | Coin chips with values ("$54.9M") drawn at about 6 px text at the default zoom, so they are unreadable. Paired with small teal up-arrows. | S2 |
| Department upgrade sheet | `35_tap_316_735.png`, `35_tap_150_520.png` | Plain text rows with teal buttons. No station art, no before/after preview, no staff portraits. "Team size 15 members · maximum" while the floor shows about 5 desks. | S1 |
| Managers | `20_managers.png` (sealed), `30_managers_unlocked.png` | 3D portraits are the best art in the game. But the card is a dark admin panel. The Founder's Ghost portrait is a normal man in a vest (`manager_portraits/founders_ghost.png`). Legendary and Common cards look almost identical. Portrait faces use a different style from the floor sprites (open eyes and smile vs sleepy lids). | S2 |
| Recruitment cases | `21_lootbox.png` | Text-only list. No case art or chest model, and no opening sequence visible. | S1 |
| Store | `22_store.png` | Rendered bundle chests are good. Tabs and rows are fine. This is the most finished screen. | S3 |
| Venues / prestige | `23_prestige.png`, `32_prestige_unlocked.png` | Shows a small 413x310 venue thumbnail, then text bars. "Your next museum" is cropped and uses the same grey suburb. No landmark hero or exterior. | S1 |
| Decor | `24_decor.png`, `33_decor_unlocked.png` | Text-only shop list with no item thumbnails. | S1 |
| Statistics | `25_statistics.png` | Clean, readable. Fine as a utility screen. | S3 |
| Expedition | `26_expedition.png`, `31_expedition_unlocked.png` | Pure text list ("Local Dig Site — +20 insight / Invest 1K"). No dig-site map or boss art for "The Temple Guardian". | S1 |
| Inspection event | `27_inspection.png`, `34_inspection_unlocked.png` | Text stages. Match-3 tiles are still **letter glyphs** (G/T/A/P) per `scenes/events/battle_view.gd:258-615`. Old capture: `docs/screenshots/match3_battle.png`. | S1 |
| Welcome back | `28_welcome_back.png` | One flat coin circle. No money pile or animation. | S2 |
| Store icon / feature graphic | `assets/android/play_icon_512.png`, `play_feature_1024x500.png` | Placeholder flat orange temple on a dark background. IBT's feature graphic is a character close-up. | S1 |
| Rendering defect | `43_floor_seam_crop_3x.png` (from `41_exhibit_zoom_pines.png`) | Triangle-seam hairlines across floor polygons, visible at 2x zoom and above, over the whole floor. | S2 |

---

## 3. NPCs (visitors, staff, porters, managers)

How they're built: pre-rendered Blender sprites (`tools/blender/make_cast.py`), loaded via `scripts/characters/*_sprites.gd` from:
- `art/npc_motion`: 3,265 files; 36 sets × directions × 8 walk frames + idle.
- `art/npc_activities`: `feed` only.
- `art/npc_seating`, `art/npc_carts`, `art/npc_cart_steering`.

The roster is in `scripts/characters/npc_roster.gd`: 24 visitor looks (4 ages × 2 genders × 3 variants) and 12 staff looks (ticket/docent/promotions/porter × 3). `README.md`/`CREDITS.md` still say the cast is "procedural `_draw` code". That is stale.

Findings:

1. **Too small to read.** Sprite canvas is 48x72 design px (`motion.json → draw_rect`). At the default camera (`camera_zoom` 0.72 → 0.50 per venue in `data/venues.json`), people render about 22–30 px tall on a 1280-tall screen (`01_whispering_pines.png`, `12_infinite_museum.png`). IBT characters are roughly 1.5–2x larger relative to the frame and have **thick dark outlines**, so they read as silhouettes.
   - *Grander:* raise the base zoom floor (`VenueTheme.MIN_CAMERA_ZOOM = 0.48`, `venue_floor.gd:128`) or scale the cast about 1.4x.
   - Add a 2–3 px dark rim to the baked sprites (the Blender inverted hull is already in `make_cast.py`: `OUTLINE_MM = 0.018`; it barely shows, so raise it about 3x).
2. **No personality.** Every body is the same mannequin with a helmet-like hair cap, half-closed "sleepy" eyes and no accessories (`npc_motion/visitor_young_adult_female-front-idle.png`, `staff-ticket-0-front-idle.png`). There are no hats, bags, cameras, backpacks, strollers, school groups, tourists with maps or VIPs.
   - IBT's store art sells *character* (rich clients, a construction worker, a grandmother with pearls).
   - *Grander:* visitor archetypes that match each museum. Examples: school group with a teacher for M1, a scuba-kid or family with balloons for the aquarium, a scholar for the Athenaeum, a royal-court cosplayer for the Palace, wealthy patrons for late venues. Add 2–3 accessory slots per look.
3. **Staff don't read as staff.** Teal and blue shirts overlap the visitor palette (`SHIRT` list in `make_cast.py`). Porters are the only role with a unique silhouette (carts).
   - *Grander:* distinct uniforms per department (red-vest ticketing, green docents with clipboards, purple promoters with megaphones or sandwich boards, a brown porter apron), and a hat or badge on every staff member.
4. **Density is capped low and flat across venues.** The limits apply to all 12 venues equally:
   - `venue_floor.gd:53-56`: `MAX_ALIVE = 34`, `MAX_CROWD = 14`, `HARD_MAX_WINDOWS = 5`.
   - `public_plaza.gd:9`: `MAX_PEOPLE = 4`.

   The Infinite Museum has the same crowd as the first hall. The upgrade sheet says "Team size 15" but about 5 desks and staff appear (`35_tap_316_735.png`).
   - *Grander:* scale `MAX_ALIVE` per venue (about 34 → 90), use cheap far-LOD "crowd" sprites (2–4 frame, 24 px) for queue filler, and make team size visibly add staff.
5. **Animation vocabulary is thin.** There are walk (8 frames), idle (1 frame), sit and a single activity `feed`. Nobody points at exhibits, takes photos, cheers, tugs a parent's hand, or reacts when a hero exhibit is upgraded. Staff don't gesture while serving.
   - *Grander:* per-exhibit "wow" reactions (jump, point, photo flash), a queue idle fidget, and staff serve loops. All can be rendered by the same Blender rig.
6. **Manager portraits** (`art/manager_portraits/*.png`, 512x640) are the strongest character art, but:
   - their style doesn't match the in-world sprites (open eyes and smile vs sleepy lids);
   - rarity has no visual language: "Founder's Ghost" (Legendary) is an opaque, normal-looking man;
   - backgrounds are only 4 department rooms (`art/manager_backgrounds/`).
   - *Grander:* rarity frames (bronze/silver/gold/prismatic with animated foil), per-manager props (Rex with a fossil hammer, the Ghost translucent with a glow), and a full-body pose for Legendary cards. Put managers **on the floor** as walking hero NPCs with a nameplate and aura when assigned. `Character._draw_manager_aura` exists; make it far louder.

## 4. Museums & layouts

How they're built:
- Floors, walls and props are procedural isometric geometry: `scenes/venue/floor/venue_floor.gd` (195 KB), `iso.gd`, `museum_architecture.gd`, `exhibits.gd`.
- Plans are data in `data/venues.json → theme` (authored through `tools/author_venue.py` and `tools/venue_kit.py`).
- About 500 pre-rendered Blender prop and exhibit PNGs live in `art/environment/`, loaded by `museum_props.gd` and `public_plaza.gd`.
- The Blender script that made the environment PNGs is **not in the repo** (only `tools/blender/make_cast.py` exists). Those assets cannot be regenerated.

Measured scale per venue (from `data/venues.json`):

| Venue | Footprint (tiles) | Rooms | Exhibits | camera_zoom |
|---|---|---|---|---|
| 1 whispering_pines | 14x18 | 6 | 6 | 0.72 |
| 4 sunspire | 18x20 | 14 | 7 | 0.57 |
| 8 ironwood_citadel | 19x22 | 13 | 9 | 0.53 |
| 12 infinite_museum | 23x27 | 19 | 18 | 0.50 |

Findings:

1. **Every museum is a cutaway slab with no exterior.** There are no roofs, facades, entrance porticos, domes, towers or signage, so from the default camera every museum reads as a floor plan on a parking lot. Compare `00_fresh_start.png` and `12_infinite_museum.png`. IBT also uses cutaways, but sells the building with a thick red-brick outer wall band, curved glass, and saturated room walls (listing screenshot "Be an idle bank tycoon").
   - *Grander:* give each venue a **front facade and landmark silhouette** that stays visible at the top of the frame and hides with wall occlusion only over the rooms. Examples: columns and pediment for M1, a glass whale-arch for M2, a copper dome for M3, an obelisk gate for M4, a clock tower for M10, a gilded dome and flag for M11, and a floating portal ring for M12. Show a grand entrance stair and banner at the queue.
2. **Progression is invisible on screen.** The footprint grows about 2.5x from M1 to M12, but camera zoom shrinks from 0.72 to 0.50, so every museum occupies roughly the same 600x500 px. The "grander" part is erased by the camera.
   - *Grander:* grow **vertically and outward in frame**. More storeys (M1 = 1, M6 = 2, M10 = 3, M12 = 4 or more), a taller landmark, and pan-able width wider than the screen (IBT's floor runs off both edges). Let the player pan across a museum instead of shrinking it.
3. **The surround is a recolor, not a place.** `scenes/venue/floor/city.gd:115-442`: the `dunes`, `alpine`, `nightfall`, `palace_gardens`, `clock_district` and `worlds_campus` styles are mostly **palette dictionaries** over the same two-storey houses, roads and trees. The code comment at about line 168 says the surround must "recede", and it does, too much.
   - *Grander:* one bespoke landmark set per surround. Pyramids and palms for dunes, snowy peaks and a funicular for alpine, harbour cranes and a lighthouse for the aquarium, a starry sky and observatory for nightfall, and a palace garden with fountains for Empyrean. The "world" should visibly move from town to city to capital to other-worldly.
4. **Hero exhibits are primitive and tiny.** Examples:
   - `infinite_museum-colossus_of_ages.png`: capsule man holding a globe.
   - `pelagic_crown-crown_whale.png`: beads.
   - `ironwood_citadel-iron_wyvern.png`: toy plane.
   - `chronos_spire-age_engine.png`: gallows with gears.
   - `empyrean_palace-petal_fountain.png`: flat daisy.
   - `sunspire-colossus.png`: lego figure with a halo.

   Most sit in 320–512 px canvases with the subject covering 25–40% of it, so on screen they are 40–90 px. A museum game lives or dies on its "wow" objects.
   - *Grander:* 1–2 **hero pieces per museum at 3–5x current screen size**, each on a raised plinth with a spotlight cone, rope ring, plaque and crowd ring. Examples: a full T-rex that breaks the wall line, a blue whale hanging from the ceiling across two rooms, a 3-storey Foucault pendulum or clock for Chronos, a gilded throne dais for Empyrean, a floating planet orrery for Infinite. Each hero should gain visible tiers when upgraded (restoration scaffolding → finished → gilded or animated).
5. **Rooms lack identity.** Most rooms share the venue's single cream or beige floor. IBT gives each department its own saturated wall color (orange promo office, blue vault, cyan service, purple lounge), so zones read at a glance. PocketGamer.biz notes that IBT's own weak point was zone legibility, so there is room to beat it.
   - *Grander:* per-department wall colors and floor materials (carpet vs marble vs wood), plus a big department sign over each doorway.
6. **Walls are low and thin.** Walls are about 1–1.5 tiles tall and the same light tone as the floor, so rooms flatten (`01_whispering_pines.png`, `07_celestial_conservatory.png`). Taller back walls with trim, wall art, windows and ceiling light pools would add depth.
7. **Lighting is one flat grade.** `scenes/venue/floor/venue_grade.gdshader` adds a 7–13% tinted overlay, and `scenes/ui/grade.gdshader` adds a gentle split-tone and vignette. There are no light pools, spotlights on exhibits, window light shafts, or night mode. Adding cheap additive light sprites under hero exhibits would make the biggest mood jump per effort.
8. **Floor seam defect.** Diagonal triangle-edge hairlines cross floor polygons (see `43_floor_seam_crop_3x.png`). Likely cause: antialiased polygon edges or overlapping alpha between triangulated floor polys. Check with `rendering/quality/world_edge_smoothing` off and by baking floors to a texture.
9. **Composition in portrait.** The building sits in the vertical middle with about 200 px of empty road and lawn below it (`01`, `03`, `05`, `08`). That space could hold the entrance plaza, queue and parked buses, where IBT puts its queue.

## 5. UI / HUD

1. **Two palettes are fighting.**
   - `scripts/ui/ui_kit.gd` defines a vivid set (ACCENT `#FF7A3D`, BRASS `#FFC53D`, SAGE `#2ED573`, BG `#2A2150`).
   - `scripts/ui/museum_chrome.gd` overrides the shell with navy, teal and brass (`#14232d`, `#27766a`, `#d6b579`).
   - What ships is the muted navy/teal one. `docs/IBT_PARITY.md` marks "Palette vivid, high chroma" as **done**, which the pixels contradict.
   - *Fix:* one warm, high-chroma museum brand. Examples: deep burgundy or royal-blue panels, gold trim, cream parchment cards, green "BUY" and orange "BOOST" buttons with a chunky bevel and drop shadow like IBT's `UPGRADE` button.
2. **The HUD is too heavy.** 27% of the screen is chrome. The quest row ("Upgrade Ticket Station 1 to Lv.3") is a full-width 70 px card. IBT uses one thin top bar.
   - *Fix:* collapse to one about 90 px top bar (rep star, cash, gems), move the quest to a small pill that expands, and float the ad buttons as round icons over the world.
3. **Panels are text spreadsheets.** Decor, Expedition, Inspection, Recruitment and Upgrade sheets have no images (`21`, `24`, `26`, `27`, `35_*`).
   - *Fix:* every row gets a thumbnail. Decor items, dig sites, case chests, the station, and a level-up preview (IBT shows the station icon next to UPGRADE).
4. **Iconography.** Kenney CC0 icons, tinted, are fine as placeholders but generic (the lock, arrow and star in the bottom nav). A museum-themed icon set (bust, ticket, compass, crate, gem) would lift everything.
5. **Typography.** Quicksand Bold/Medium is readable but thin at small sizes. There's no display face for big numbers or titles; IBT uses a heavy outlined display font. Add a chunky outlined display font for cash, titles and rewards.
6. **Store and marketing art.** The Play icon and feature graphic are placeholders (`assets/android/*`). Replace them before any store test.

## 6. Feedback / juice

- **No particle systems anywhere.** A grep for `CPUParticles2D`/`GPUParticles2D` across `scenes/` finds nothing.
- **Upgrade feedback:**
  - `dept_panel.gd:317-332` scales the button to 1.035 and tints it.
  - `venue_floor.gd:851-861` only refreshes the cast and chips.
  - There is no in-world pop, dust puff, sparkle, or "Lv UP" flag over the station.
- **Reputation level-up** is a toast (`scenes/main.gd:141-143`). IBT's store art shows a full-screen star-burst celebration with rays. It's their "Get more rich clients!" frame.
- **Routine income:** `income_feedback.gd` draws a 4.5 px check circle for automatic service and a small dark box for manual collects. These are nearly invisible.
- **Coin bursts exist** only for the vault or porter drops (`venue_floor.gd:3108`, `_spawn_coin_burst`).
- **The vault pile** (the yellow stack in the archive room) is IBT's single best visual reward. In IBT the vault fills with shelves of green money, which is literal visible wealth. Ours is a small gold ziggurat of about 40 px (`01_whispering_pines.png`, near the top room).

What to add:
- Floating coin sprites that fly to the HUD counter.
- Number popups with a scale-in overshoot.
- Station level-up burst with confetti and a ring.
- Rep level-up full-screen star.
- Screen-flash, glow and "NEW!" reveal when a hero exhibit is upgraded.
- A growing collection-storage room (crates → shelves → gold artifacts) as the museum's vault equivalent.
- Haptics hooks.

## 7. Progression

- **Within a museum:** fresh versus maxed looks almost the same (`00_fresh_start.png` vs `36_unlocked_main.png`). Only ticket desks are added. IBT's key visual beat is **derelict → renovated**: grey, dusty, boarded rooms become saturated and furnished when unlocked (listing screenshot "Build your bank empire!").
  - *Grander:* each department and hero exhibit has 3–4 visual tiers. Examples: tarps and scaffolding → basic → deluxe with lights → gilded with an animated centerpiece. Locked rooms render as dusty construction with a "Unlock $X" sign.
- **Between museums:** the prestige screen shows a small thumbnail (`venue_previews/*.png`, 960x720) inside a text-heavy panel. There's no fly-over, opening ceremony or ribbon cut.
  - *Grander:* a "Grand Opening" sequence: camera sweep over the new facade, crowd rush, confetti, curator speech bubble.
- **Density and scale** don't escalate. See §3.4 and §4.2.
- **Decor purchases** are a text shop (`24_decor.png`). Placement results are not previewed.

## 8. Art pipeline and consistency

- **Mixed pipelines:**
  - Procedural `_draw` geometry for architecture and floors.
  - Blender pre-renders for cast, props, heroes, vehicles, store items and portraits.
  - Kenney CC0 UI icons, panels and bars.
  - Code-drawn UI styleboxes.

  The pre-renders use a soft, flat, low-contrast "clay" look without outlines. The procedural walls use flat fills with edge lines. They mostly match in tone but not in edge treatment.
- **Reproducibility:** only the cast script is in the repo (`tools/blender/make_cast.py`). Environment, exhibit, portrait and store renders have no generator in `tools/`. Recover or re-author these scripts before the overhaul so every asset can be re-rendered at a new scale.
- **Stale docs:** `README.md` and `CREDITS.md` say "Art is fully procedural (drawn in code)". That is untrue for the cast, props, portraits and store art. `docs/IBT_PARITY.md` claims palette parity. Fix these so decisions aren't made on false premises.
- **Texture budget:** about 5,500 PNGs (≈132 MB source) imported **lossless** (`compress/mode=0`) with mipmaps and no atlasing. Examples: `art/npc_motion/*.png.import`, `art/environment/*.png.import`.
  - `tools/perf.gd` on the audit copy (desktop, M1 maxed) reported 538 draw calls for the full floor: 345 statics-only, 98 with the floor hidden.
  - On mid-range Android, lossless 3,000-frame cast sheets plus about 540 draw calls will be a VRAM and battery problem.
  - Plan atlases per character (one sheet per look), VRAM compression (ETC2/ASTC; the project already sets `import_etc2_astc=true`, but per-file mode 0 overrides it), and a baked static layer per storey.
- **Wasted canvas:** hero PNGs often use 25–40% of their canvas (for example `pelagic_crown-crown_whale.png`, 512x512 with a small subject). Trim before atlasing.

## 9. What Idle Bank Tycoon does that we must match

Source: Play and App Store listing screenshots, PocketGamer.biz deconstruction, store reviews.

1. **Saturated per-room color** with thick outlines. Rooms are identifiable at a glance.
2. **A dense, busy workforce.** Many desks, dozens of staff and a long snaking customer queue in frame at once.
3. **Visible accumulated wealth.** Vault rooms fill with shelves of stacked money, and porters with carts haul it.
4. **Derelict-to-renovated transformation** when unlocking or upgrading areas.
5. **Characterful cast.** Exaggerated cartoon faces, distinct archetypes ("rich clients" with pearls or a red dress, a construction worker), and a mascot host who appears in marketing and tutorials.
6. **Chunky, bright UI.** Big green UPGRADE button, heavy outlined display font, star-burst reputation celebrations, and a thin HUD that leaves the world visible.
7. **Bank progression by name and scale** ("Big Town, Bigger Bank", "Making Waves"). Bigger, fancier buildings with a city around them.
8. **A marketing layer.** Key art, mascot, feature graphic.

## 10. Where Grand Exhibit can clearly beat it

- **Spectacle content.** Banks have desks and cash; we have dinosaurs, whales, orreries, thrones, clockwork and alien worlds. Making hero exhibits big, lit and animated gives a "wow" IBT can't have.
- **Verticality and landmarks.** We already support multi-storey venues with stairs (M4, M5, M10, M12). Push that into towers, domes and atriums with facades. IBT is flat.
- **Themed worlds.** 12 distinct settings (natural history → aquarium → library → desert → alpine → space → conservatory → castle → ocean → clock tower → palace → infinite). Make each surround a place, not a recolor.
- **Living crowds with reactions.** Visitors who stop, point, photograph and cheer at exhibits give emotional feedback that bank customers can't.
- **Real 3D-rendered portraits.** Our Blender portrait pipeline already beats IBT's flat 2D cards on form. Add rarity foil, props and poses and it wins outright.
- **Exhibit restoration as the upgrade fantasy.** Dusty crates → scaffolded skeleton → finished, lit display is a better story than a bank-desk level-up.
- **Day/night and events.** A "Night at the Museum" mode (the Night Curator manager already exists) for events is a visual differentiator.

## 11. Prioritized overhaul plan (highest visual impact per effort first)

| # | Item | Impact | Effort | How to make it |
|---|---|---|---|---|
| 1 | **Palette and UI rebrand.** Kill the navy/teal chrome, adopt one vivid warm scheme, a chunky outlined display font, a thin HUD (≤12% of screen), and big bevelled green/orange buttons. | Very high | Low–Med | Code (`museum_chrome.gd`, `ui_kit.gd`, `hud.gd`). Needs one font license (OFL). |
| 2 | **Readable cast.** About 1.4x scale, thick outline, uniforms by role, 2–3 accessory slots, open-eyed faces. | Very high | Med | **Procedural:** extend `tools/blender/make_cast.py` (outline 3x, accessory meshes, eye rig) and re-render all sets. |
| 3 | **Juice pack.** Coin fly-to-HUD, number pop overshoot, station level-up burst, rep level-up full-screen star-burst, upgrade confetti, bigger vault or collection pile. | Very high | Low–Med | Code plus a few particle textures (can be generated). CPUParticles2D is fine under GL Compatibility. |
| 4 | **Hero exhibits, 1–2 per venue at 3–5x screen size**, with spotlight pools, plinth and plaque, and 3 upgrade tiers each. | Very high | Med–High | **Procedural:** Blender scripts for the tiered hero models (skeletons, whale, orrery, clock, throne) with spotlight baked. Hero silhouettes need an art director's concepts; the modelling can be scripted or kitbashed. |
| 5 | **Facades and landmarks** per venue (portico, dome, tower) plus a grand entrance and queue plaza in the empty lower 200 px. | High | Med–High | **Procedural:** a Blender facade kit (columns, pediments, domes, arches, clock face) parameterised per venue, rendered at the exact 41.81° iso camera (`make_cast.py` has the math). |
| 6 | **Progression visibility.** Derelict → renovated room states, visible staff per team-size level, per-venue scaling of `MAX_ALIVE`/`MAX_CROWD`, and camera framing that lets later venues exceed the screen (pan) instead of zooming out. | High | Med | Code (`venue_floor.gd` limits, `VenueTheme.MIN_CAMERA_ZOOM`) plus "dusty/boarded" overlay sprites (procedural). |
| 7 | **Per-department room colors and signage.** | High | Low | Data (`data/venues.json` palette per room) plus a sign sprite kit. |
| 8 | **Bespoke surrounds per theme** (dunes pyramids, alpine peaks, harbour cranes, night sky, palace gardens, cosmic campus). | Med–High | Med | **Procedural:** Blender landmark kit per style, referenced from `city.gd` STYLES. |
| 9 | **Image-rich panels.** Thumbnails for decor, dig sites, cases, stations, events; case-opening animation; expedition map. | Med–High | Med | Blender renders for thumbnails (procedural). Case opening is code. Expedition map needs hand-authored illustration or a Blender diorama. |
| 10 | **Match-3 tile art** instead of letters. | Med | Low | Procedural: department icon tiles rendered from Blender or vector. |
| 11 | **Manager rarity frames, per-manager props, Legendary full-body poses; managers walk the floor.** | Med | Med | Blender portrait pipeline (procedural) plus hand-directed poses. |
| 12 | **Store icon, feature graphic, key art with a mascot curator.** | High for conversion | Med | **Needs a hand-authored or art-directed illustration.** A mascot is a brand decision. |
| 13 | **Lighting pass.** Additive light pools, window shafts, per-venue time of day, a night event mode. | Med | Low–Med | Code plus generated light textures. |
| 14 | **Tech hygiene.** Fix the floor seam artifact, VRAM compression, per-character atlases, trim hero canvases, recover or recreate the Blender scripts for environment, portrait and store renders, and correct `README.md`, `CREDITS.md` and `IBT_PARITY.md`. | Enabler | Low–Med | Scripts and import settings. |

**Procedural (Blender scripts / code) vs hand-authored:**
- **Can be generated:** items 2, 3, 5, 6, 7, 8, 10, 13, 14, most of 4 and 9, and most of 11.
- **Needs human art direction or hand work:** hero exhibit concepts (4), the mascot, key art and store assets (12), the expedition map illustration (9), and final palette sign-off (1).

The fastest visible win is 1 + 2 + 3 together. Those three alone would move the first-10-seconds impression from "muted prototype" to competitive with IBT. Items 4–6 are what would make it clearly *grander* than IBT.

---

## Appendix: capture commands (on the audit copy)

```
$env:APPDATA = "<museum_audit>\appdata"
godot --path <museum_audit>\game -s tools/shot.gd -- out=user://X.png venue=<id> levels=12 cash=1e12 sim=90 warm=10 [zoom=2.2 at=x,y] [open=res://scenes/...tscn] [tap=x,y]
godot --headless --path <museum_audit>\game -s tools/dev_unlock.gd -- venue=whispering_pines   # late-game state
godot --path <museum_audit>\game -s tools/perf.gd
```

(Godot could not write PNGs directly to a subst/long path, so shots were written to `user://` and moved into `shots\`.)

Screenshot index: `00` fresh start; `01–12` venues (base = default camera, `_far` = +3 s, `_zoom` = 2.2x); `20–28` popups at an early save; `30–34` popups with everything unlocked; `35_tap_*` department upgrade sheet; `36` maxed M1; `40_maxzoom_a/b/c` 3.2x cast sequence; `41` exhibit close-up; `42` Empyrean close-up; `43` floor-seam crop.

Competitor sources: [Google Play listing](https://play.google.com/store/apps/details?id=com.luckyskeletonstudios.idlebanktycoon&hl=en_US), [App Store listing](https://apps.apple.com/us/app/idle-bank-tycoon-money-game/id1645281275), [PocketGamer.biz deconstruction](https://www.pocketgamer.biz/game-analysis-deconstructing-idle-bank-tycoon-by-kolibri-games/), [Pocket Gamer launch article](https://www.pocketgamer.com/idle-bank-tycoon-money-empire/official-launch-android-ios/), [FatWallet Refugee guide](https://fatwalletrefugee.com/2024/02/27/idle-bank-tycoon/).
