# Grand Exhibit — Idle Museum Tycoon

Godot 4.4 · portrait 720x1280 · Android-first. See `docs/SPEC.md` (architecture contracts)
and `docs/DESIGN_DECISIONS.md` (why things are the way they are).

## Run
```bash
godot --headless --path . --import   # once on a fresh clone (builds class cache)
godot --path .                       # editor
godot --headless --path . --quit-after 3   # sanity check
```
Open the project in Godot 4.4+ and press Play.

## Tests
19 standalone SceneTree suites (core, venue, managers, events, meta, monetization, qa):
```bash
godot --headless --path . -s tests/core/test_big_number.gd   # one suite
for t in tests/*/test_*.gd; do godot --headless --path . -s "$t" || echo "FAIL $t"; done
# exit code 0 = pass, 1 = fail
```

## Export
Android APK/AAB: install Godot 4.4 export templates, add an Android preset (portrait,
package e.g. `dev.grandexhibit.game`), export. Not produced in the build environment
(templates not installed) — the project is export-ready; flip the debug flags below
and wire the real ad/billing SDKs in `autoload/ad_service.gd` / `autoload/iap_service.gd`.

## Notes
- Ads and IAP are behind `AdService` / `IAPService` interfaces with debug stubs
  (ads always succeed, purchases always succeed). Wire AdMob / billing plugins there.
  Release flip: set `AdService.debug_ads = false` and `IAPService.debug_iap = false`
  (both default `true` in debug builds; with `false` the stubs fail gracefully until
  the real SDK is wired).
- All balance lives in `data/*.json` — retune without touching code.
- Art is procedural placeholder (drawn in code, CC0 by us) pending a Kenney/CC0 pass.
