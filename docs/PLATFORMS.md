# Shipping Grand Exhibit: mobile first, then PC stores

Grand Exhibit is a portrait phone game (720×1280 canvas, Godot 4.4.1, GL
Compatibility renderer). One project exports to every target below. The
preset template (`export_presets.template.cfg`) never holds signing identities,
keystores or store credentials. Those come from the build machine.

| Target | Preset | Feature tag | Store backend |
|---|---|---|---|
| Google Play | Android Release | – | Play Billing (`play_billing.gd`), AdMob (`admob_ads.gd`), Play Games achievements |
| App Store | iOS | – | StoreKit (`app_store.gd`), AdMob (`admob_ads.gd`), Game Center achievements |
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
   **Steam Cloud** needs no code: in Steamworks, turn on Auto-Cloud with the
   save file `grand_exhibit_save.json` (and `.bak`) under the Godot user data
   folder: root `WinAppDataRoaming`, path `Godot/app_userdata/Grand Exhibit`
   on Windows; `LinuxXdgDataHome` + `godot/app_userdata/Grand Exhibit` on
   Linux/Deck; `MacAppSupport` + `Godot/app_userdata/Grand Exhibit` on macOS.
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

## Android / Google Play

1. Export the "Android Release" preset (`tools/build_android.sh`; keystore
   details come from the build machine, see `docs/ANDROID_RELEASE.md`).
2. **Purchases**: install the Play Billing plugin. `scripts/monetization/play_billing.gd`
   drives it behind IAPService.
3. **Ads**: install the Poing Studios **godot-admob-plugin** into
   `addons/admob/` and enable it (Project > Project Settings > Plugins).
   Put the AdMob **app id** in the plugin's Android export settings; it lands in
   the manifest. `scripts/monetization/admob_ads.gd` finds the plugin's classes by
   name at runtime (the project compiles without the addon), so AdService uses
   real ads as soon as the plugin is in the build, in debug and release builds
   alike, and the simulator only runs where there's no SDK. Ad units come from
   `data/store_iap.json` `ads.units`; they're Google's public **test** units
   today, which always fill and earn nothing. Replace them (and set
   `is_test` to false) before release. Rewarded ads pay only after the ad closes
   with a reward (a reward reported just after the close is honoured), the
   game is muted while an ad is up, and without the player's consent every
   request is non-personalized (`npa=1`). The content rating and the
   child-directed flag come from the `policy` block. The adapter is tested
   against a fake plugin (`tests/monetization/test_admob.gd`); what needs a
   device is the real SDK's fill and callbacks.
4. **Achievements**: install the **godot-play-game-services** plugin (singleton
   `GodotPlayGameServices`) and set the Play Games project id in its export
   settings. Create the 17 achievements in the Play Console, then paste the ids
   it generates into `data/achievements.json` `platform_ids.play_games`
   (`"FIRST_UPGRADE": "CgkI..."`). `platform_services.gd` waits for the
   automatic sign-in, sends everything earned so far, then each new unlock,
   and Settings gets a button that opens the Play Games achievements screen.
   An achievement with no Play Console id stays local.
5. **Cloud save**: turn on *Saved Games* in the Play Console (Play Games
   Services > Configuration). `scripts/platform/cloud_save.gd` uses the same
   plugin: after sign-in it downloads the cloud copy; one further along
   (museums, then milestones, then reputation) is offered in Settings (load it,
   or keep this phone's) and never applied silently; otherwise this phone's
   save is uploaded, and again whenever the app goes to the background (at most
   every 5 minutes). Tested against a fake (`tests/meta/test_cloud_save.gd`).
6. **Notifications**: install the **godot-notification-scheduler** plugin
   (singleton `NotificationSchedulerPlugin`) and put its notification icon in
   `res://assets/NotificationSchedulerPlugin/android`. Reminders
   (`scripts/meta/reminders.gd`: vault full, Daily Gift, café opening or last
   call, dig energy full) are scheduled when the app is backgrounded and
   cancelled when the player returns: never at night (22:00 to 08:00 moves to
   08:00), at most 4, an hour apart. Permission is requested once, right after
   the first Daily Gift. Settings has an on/off switch. Tested against a fake
   (`tests/meta/test_reminders.gd`).

## iOS / App Store

1. On a Mac with Xcode, install the Godot 4.4.1 export templates, then export
   the "iOS" preset. Enter the Team ID in the export dialog; it isn't stored here.
2. Add Godot's official iOS plugins (godot-ios-plugins) to the export:
   **InAppStore** for purchases and **GameCenter** for achievements.
   `scripts/monetization/app_store.gd` already drives InAppStore behind
   IAPService: localized prices, purchases finished only after the grant is
   saved, and a player-initiated Restore Purchases for the ad-free unlock.
   It's tested against a fake plugin (`tests/monetization/test_app_store.gd`);
   what needs a device is that the plugin's method names match. Create the
   products in App Store Connect with the ids in `data/store_iap.json`.
3. **Achievements**: turn on Game Center for the app and create the 17
   achievements in App Store Connect. Their ids are ours (`FIRST_UPGRADE`, ...)
   with `platform_ids.game_center_prefix` in front (empty by default), unless
   `platform_ids.game_center` maps one. `platform_services.gd` authenticates at
   launch, reads the answer from the plugin's event queue, back-fills what was
   earned (quietly), then awards each new unlock with Game Center's banner.
   Tested against a fake (`tests/meta/test_platform_achievements.gd`).
4. **Notifications**: the same godot-notification-scheduler plugin (it ships
   an iOS part) and the same reminders as Android.
5. **Cloud save**: not wired on iOS yet. Game Center saved games or iCloud
   key-value storage need a plugin; `cloud_save.gd` is the place for a second
   backend.
6. **Ads**: the same godot-admob-plugin as Android, with the iOS app id in its
   iOS export settings and `ads.ios_units` in `data/store_iap.json` (Google's
   test units today). Add the `GADApplicationIdentifier` and
   SKAdNetwork items the plugin's docs list, and an App Tracking Transparency
   prompt if ads are ever personalized.
7. The layout is portrait only, and the 1024×1024 icon comes from
   `assets/android/play_icon_512.png`, which needs a real 1024 master before
   submission.

## Build size

A pack-only export (`--export-pack`) is about 45 MB. Every museum runs on the
3D toy-diorama floor (`art3d/`, about 35 MB), so every preset in
`export_presets.template.cfg` leaves out the 2D floor's sprite sheets
(`art/npc_*`, `art/environment`, `art/vehicles`; about 150 MB). The 2D sprite
loaders check for their files and fall back to procedural drawing, so the
2D floor still works in tests, where it's switched on explicitly.
