# Grand Exhibit — Idle Museum Tycoon

Godot 4.4 · portrait 720x1280 · Android-first. See `docs/SPEC.md` (architecture contracts)
and `docs/DESIGN_DECISIONS.md` (why things are the way they are).

## Run
```bash
godot --path .                      # editor
godot --headless --path . --quit-after 3   # sanity check
```
Open the project in Godot 4.4+ and press Play.

## Tests
Every suite is a standalone SceneTree script:
```bash
godot --headless --path . -s tests/core/test_big_number.gd
# exit code 0 = pass, 1 = fail
```

## Notes
- Ads and IAP are behind `AdService` / `IAPService` interfaces with debug stubs
  (ads always succeed, purchases always succeed). Wire AdMob / billing plugins there.
- All balance lives in `data/*.json` — retune without touching code.
- Art is procedural placeholder (drawn in code, CC0 by us) pending a Kenney/CC0 pass.
