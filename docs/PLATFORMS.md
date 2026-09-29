# Shipping Grand Exhibit: mobile first, then PC stores

Grand Exhibit is a portrait phone game (720×1280 canvas, Godot 4.4.1, GL
Compatibility renderer). One project exports to every target below. The
preset template (`export_presets.template.cfg`) never holds signing identities,
keystores or store credentials. Those come from the build machine.

| Target | Preset | Feature tag | Store backend |
|---|---|---|---|
| Google Play | Android Release | – | Play Billing + AdMob (see `autoload/iap_service.gd`, `ad_service.gd`) |
| App Store | iOS | – | StoreKit backend in (`app_store.gd`); Game Center to wire |
| Steam (Windows) | Windows Desktop (Steam) | `steam` | GodotSteam |
| Steam Deck / Linux | Linux (Steam Deck) | `steam` | GodotSteam |
| Steam (macOS) | macOS | `steam` | GodotSteam |
| Epic Games Store | Windows Desktop (Epic) | `epic` | EOS plugin |
| Microsoft Store | Windows Desktop (Microsoft Store) | `msstore` | none (offline) |

## What the game already does for PC

- **Window**: opens at 540×960 so it fits a 1080p screen. The player can resize it.
  On PC the canvas letterboxes instead of stretching (`window/stretch/aspect.pc="keep"`),
  so the phone layout never distorts.
- **Input**: everything is tappable with a mouse. The 3D museum pans with a
  click-drag and zooms with the wheel, Esc is Back, and taps use the same code
  paths as touch.
- **Textures**: S3TC/BPTC import is on alongside ETC2/ASTC, which desktop exports need.
- **Icons**: `assets/desktop/icon.ico` (Windows) and `icon.icns` (macOS) are made
  from the store icon.
- **Achievements**: `data/achievements.json` lists 17 achievements, tracked locally
  on every build by `autoload/platform_services.gd`. When a store SDK is present,
  each unlock is mirrored to the store, and `sync_store()` back-fills anything
  earned before the SDK was attached.

## Steam

1. Create the app in Steamworks and note its **App ID**.
2. Install the GodotSteam **GDExtension** for Godot 4.4 into `addons/godotsteam/`
   (from the Godot Asset Library or github.com/GodotSteam/GodotSteam). No engine
   rebuild is needed. The `Steam` singleton appears at runtime, and
   `platform_services.gd` detects it.
3. For local runs, create `steam_appid.txt` at the project root containing the App ID.
   It's already in the Steam presets' include filter. Ship it only for playtest
   branches.
4. In Steamworks, register achievement API names that match the `id`s in
   `data/achievements.json` (`FIRST_UPGRADE`, `SECOND_FLOOR`, …).
5. Export "Windows Desktop (Steam)", "Linux (Steam Deck)" and "macOS", then
   upload each with SteamPipe (`steamcmd +run_app_build`).
6. **Steam Deck**: the portrait window letterboxes on the Deck's 16:10 screen,
   and the touch screen works as a mouse. Declare "Partial controller support"
   until a gamepad cursor is added.
7. **Monetisation on Steam**: Steam doesn't allow rewarded video ads. For PC
   builds, set `AdService.debug_ads = false` and replace ad rewards with free
   timers. Sell gem packs through Steam microtransactions (ISteamMicroTxn)
   behind `IAPService`, or go premium with the gem store removed.

## Epic Games Store

1. Create the product in the Epic Developer Portal and set up EOS (product,
   sandbox and deployment IDs, plus a client ID and secret).
2. Install an EOS plugin for Godot 4 (for example "EOS Godot" / `IEOS`) into
   `addons/`. `platform_services.gd` looks for an `EOS` or `IEOS` singleton on
   builds with the `epic` feature tag.
3. Put the credentials in the plugin's settings on the build machine, never in
   this repository.
4. Register the same achievement IDs, then export "Windows Desktop (Epic)" and
   upload with BuildPatchTool.

## Microsoft Store

Godot 4 has no UWP exporter. The Microsoft Store accepts ordinary Win32 apps
packaged as **MSIX**:

1. Export "Windows Desktop (Microsoft Store)" (single `.exe` with the embedded
   `.pck`).
2. Package it with the MSIX Packaging Tool, or with `makeappx` and a
   hand-written `AppxManifest.xml`. Use the identity (publisher, package name)
   that Partner Center gives you.
3. Sign it with the Store certificate and submit through Partner Center. Store
   IAP (Windows.Services.Store) would need a GDExtension. Until then, ship the
   Store build premium or with the gem store off.

## iOS / App Store

1. On a Mac with Xcode, install the Godot 4.4.1 export templates, then export
   the "iOS" preset. Enter the Team ID in the export dialog; it isn't stored here.
2. Add Godot's official iOS plugins (godot-ios-plugins) to the export:
   **InAppStore** for purchases and GameCenter for achievements.
   `scripts/monetization/app_store.gd` already drives InAppStore behind
   IAPService: localized prices, purchases finished only after the grant is
   saved, and a player-initiated Restore Purchases for the ad-free unlock.
   It's tested against a fake plugin (`tests/monetization/test_app_store.gd`);
   what needs a device is that the plugin's method names match. Create the
   products in App Store Connect with the ids in `data/store_iap.json`. Game
   Center achievements can use the same IDs through `platform_services.gd`.
3. The layout is portrait only, and the 1024×1024 icon comes from
   `assets/android/play_icon_512.png`, which needs a real 1024 master before
   submission.

## Build size

A pack-only export (`--export-pack`) is about 45 MB. Every museum runs on the
3D toy-diorama floor (`art3d/`, about 35 MB), so every preset in
`export_presets.template.cfg` leaves out the 2D floor's sprite sheets
(`art/npc_*`, `art/environment`, `art/vehicles`; about 150 MB). The 2D sprite
loaders check for their files and fall back to procedural drawing, so the
2D floor still works in tests, where it's switched on explicitly.
