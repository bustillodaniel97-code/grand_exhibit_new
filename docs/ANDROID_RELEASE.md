# Grand Exhibit — Android release runbook

Status (17 September 2026): **production release remains unverified**. A separate
standard-template gameplay debug export is now available; see [ANDROID_DEBUG.md](ANDROID_DEBUG.md).
OpenJDK 17, Android build-tools/platform-tools and Godot 4.4.1 export templates
are present locally. The commercial release still needs the Gradle build
setup, real platform integrations, release signing and physical-device QA.
A debug APK does not establish any of those release requirements.

---

## 1. What exists

| Artefact | Path | Tracked? |
|---|---|---|
| Export preset (source of truth) | `export_presets.template.cfg` | yes |
| Generated preset | `export_presets.cfg` | **no** — gitignored |
| Build script | `tools/build_android.sh` | yes |
| Launcher icons | `assets/android/*.png` | yes |
| Icon generator | `tools/make_android_icons.py` | yes |
| Test runner | `tools/run_tests.sh` | yes |

`export_presets.cfg` is gitignored on purpose: the Godot editor writes keystore
paths — and passwords, if typed into the export dialog — directly into it. The
template is the committed, secret-free source; the build script materialises the
real preset at build time and takes signing from the environment.

## 2. One-time setup

**Install the Android build template for a commercial Gradle release.** Play Billing,
AdMob and UMP arrive as Godot Android plugins, and plugins are only linked when
the project builds from the installed template rather than the prebuilt APK.

    Editor > Project > Install Android Build Template

**Create the signing key.** Once, ever. Play binds the app's signing identity
permanently; losing this key means never updating the app again.

```bash
keytool -genkey -v -keystore ~/keys/grand-exhibit-release.keystore \
  -alias grandexhibit -keyalg RSA -keysize 2048 -validity 10000
```

Store it **outside the repository**. `tools/build_android.sh` refuses to build
if the keystore path resolves inside the worktree, and `.gitignore` blocks
`*.keystore` / `*.jks` as a second line of defence. Back it up somewhere that is
not this machine.

**Export the signing environment** (a shell profile, or CI secrets — never a
tracked file):

```bash
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$HOME/keys/grand-exhibit-release.keystore"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="grandexhibit"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="…"
```

## 3. Building

```bash
tools/build_android.sh --preset-only      # regenerate export_presets.cfg only
tools/build_android.sh --debug            # gameplay-only debug APK; simulated ads/purchases
tools/build_android.sh --debug --check    # dependency preflight; no export
ANDROID_VERSION_CODE=2 ANDROID_VERSION_NAME=1.0.1 \
  tools/build_android.sh --release        # signed .aab for Play
```

The script validates configuration values and build dependencies before generating
the preset. A release additionally requires signing variables, an existing
keystore outside the project (including symlink resolution), and the Gradle template. A failed
preflight builds nothing rather than producing an unsigned or
debug-flagged artifact.

`ANDROID_VERSION_CODE` must increase on every upload — Play rejects a reused
code, and it is the single most common release-day mistake.

## 4. Configuration decisions already made

| Setting | Value | Why |
|---|---|---|
| Format | `.aab` | Play requires App Bundles for new apps |
| `min_sdk` | 24 | Android 7.0; below this the WebView/GL surface costs more than the install base is worth |
| `target_sdk` | **36** | Play requirement for submissions on/after 2026-08-31 |
| Architectures | `arm64-v8a`, `x86_64` | 64-bit only; 32-bit slices would roughly double download size for hardware not targeted |
| Orientation | portrait | matches `project.godot` `window/handheld/orientation=1`; UI authored at 720×1280 |
| Auto Backup | **off** | the save holds currency and entitlements; letting Android restore an old copy is a rollback/duplication vector |
| Permissions | `INTERNET`, `ACCESS_NETWORK_STATE` | minimum for ad fill, billing and consent; each must be justified in Data Safety |
| `AD_ID` | contributed by the AdMob plugin manifest | must be declared as advertising-identifier collection |
| Excluded from bundle | `tests/`, `tools/`, `docs/`, `*.md` | authoring/test code and several hundred KB of Markdown nobody installs |

**The application id is a placeholder.** `com.bustillo.grandexhibit` is a guess.
Play binds the package name permanently at first upload and it can never be
changed. Confirm it before the first release, then set `ANDROID_PACKAGE_ID` or
edit the template.

## 5. Monetization adapters

The production transport is `scripts/monetization/play_billing.gd`
(`PlayBillingBackend`), sitting behind the unchanged `IAPService` interface.
`IAPService` binds it automatically when an Android billing plugin singleton is
present and stays on the honest no-SDK path otherwise.

What the adapter handles, and why each one matters:

- **Acknowledge / consume.** Play auto-refunds any purchase not acknowledged
  within three days. Non-consumables are acknowledged, consumables consumed.
  Getting this wrong fails silently and refunds paying customers later.
- **Re-delivery.** Play re-sends unacknowledged purchases on every reconnect.
  The adapter passes Play's own `purchase_token` through unchanged so
  `iap_catalog` can redeem it exactly once.
- **Pending.** Cash/voucher purchases arrive as `PENDING` and are *not* a
  purchase. Reported as an explicit `pending` non-success; granted only when
  they later arrive as `PURCHASED`.
- **Refund / chargeback.** An entitlement that disappears from `queryPurchases`
  is revoked and withdrawn via `Entitlements.withdraw()`, so refunding the
  ad-free upgrade does not keep it. A *failed* query revokes nothing, so a
  network blip cannot strip entitlements.
- **Restore.** `restore_purchases()` asks Play what the account owns rather than
  trusting the local record.
- **Durable grant-before-settle ordering.** The catalog saves rewards and receipt
  history together before confirming delivery to the backend. Failed writes
  leave the receipt outstanding for retry. The backend cannot consume or
  acknowledge from receipt delivery alone. Filesystem/fake-store interruption
  cases are covered by `test_purchase_durability.gd`; real-device validation
  remains required.

`tests/monetization/test_play_billing.gd` covers all of the above against a fake
plugin — 30 assertions, green. **What it cannot prove** is that the real
plugin's method and signal names match the candidates
`PlayBillingBackend._SINGLETON_NAMES` / `_call_any` probes for. That is a device
check (§7).

**Localized prices.** `IAPService.localized_price()` prefers Play product
details when real billing is bound (`PlayBilling.query_product_details` →
`product_details_received` → `IAPService.prices_updated`, which the store
listens to for label rebuilds, including resume/reconnect). A product Play did
not report shows **Unavailable** and stays blocked in `iap_catalog` — the
authored `price_usd` is only the simulator fallback, never a live offer.
`tests/monetization/test_store_prices.gd` covers simulator/unknown/reported/
reconnect/card states against a fake backend. Real catalog reconciliation and
the native binding still need a device (§7 items 4, 9).

Release safety: `AdService.debug_ads` and `IAPService.debug_iap` are both derived
from `OS.is_debug_build() and not OS.has_feature("release")`, so an exported
release build cannot run the simulators even if someone forgets a flag.
`tests/monetization/test_integrity.gd` and `tests/qa/test_policy_audit.gd` guard
this in CI.

## 6. Play Console submission checklist

Ready to fill in; none of it can be submitted from here.

**Store listing**
- App name: Grand Exhibit
- Short description (≤80 chars): idle museum tycoon — build, staff and grow twelve museums
- Full description: draft from `README.md`; must not reference Idle Bank Tycoon
- Category: Games → Simulation
- Screenshots: ≥4 phone (720×1280 native). Capture with `tools/shot.gd`
- Feature graphic: 1024×500 — **produced**: `assets/android/play_feature_1024x500.png`
- App icon: 512×512 — **produced**: `assets/android/play_icon_512.png`

**Data Safety** — answers implied by the code as built:
- Collected: advertising ID (AdMob), approximate device/usage diagnostics
- Not collected: name, email, location, contacts, files, photos
- Data is not sold; ad data shared with Google AdMob for advertising
- Encrypted in transit: yes. Deletion request path: required — needs the support contact
- Analytics writes nothing before consent resolves (`autoload/analytics.gd`)

**Ads declaration** — yes, the app contains ads (rewarded + interstitial).

**Content rating** — questionnaire: simulated gambling **no**; the lootbox
surface is a paid random-reward mechanic and must be declared, with drop rates
disclosed in-game (already surfaced in the Lootboxes screen).

**Target audience** — 13+. Not a Families-programme title. If that changes, flip
`policy.child_directed` in `data/store_iap.json`; `scripts/monetization/consent.gd`
reads it and forces non-personalized ads everywhere.

**Privacy policy** — a public URL is mandatory. **Drafted at `docs/PRIVACY_POLICY.md`**, written against what the code actually does with per-claim source references. Fill three placeholders (developer name, support email, published URL) and host it. An in-game
entry point already exists ("Privacy choices" in the store), which is required
for GDPR revocability.

**Reviewer instructions** — the game needs no login. Rewarded ads use Google's
official public TEST units, wired in `data/store_iap.json` → `ads`, until
production ids are configured. `is_test` must flip to false with real ids before
release: shipping test units means zero revenue and an AdMob policy strike.

## 7. Blocked — cannot be completed in this environment

Each of these is a genuine release blocker, with the specific unblock.

| # | Blocked item | Severity | Unblocked by |
|---|---|---|---|
| 1 | Gradle release build/platform dependencies and template installation unverified; minimal debug toolchain is installed | P0 | configure and verify the release setup in §2 |
| 2 | No signed `.aab` produced or installed | P0 | §2 + §3 with a real keystore |
| 3 | No physical device QA — low/mid/high hardware, 30/60/120 Hz, cutout displays, process death, thermal | P0 | devices |
| 4 | Play Billing plugin method/signal names unverified against a real plugin | P0 | one device run with the plugin installed; adapter probes candidates and degrades safely, so a mismatch shows as "no billing", not a crash |
| 5 | AdMob + UMP production adapters not written | P0 | AdMob app id and rewarded placement ids |
| 6 | Final application id unconfirmed (placeholder in use) | P0 | user decision — **permanent once uploaded** |
| 7 | Privacy policy URL does not exist | P0 | user must publish one |
| 8 | Feature graphic, 512 icon, store screenshots not produced | P1 | `tools/shot.gd` for screenshots; art for the graphic |
| 9 | Play Billing product ids not reconciled with `data/store_iap.json` | P1 | Play Console product setup |
| 10 | No SSV (server-side verification) endpoint for rewarded ads | P1 | `AdService.reward_verifier` is the hook; needs a server |
| 11 | 16 KB page-size alignment unverified: on a physical Android 16 device the debug APK raises "isn't 16 KB compatible — ELF alignment check failed" for `libgodot_android.so` and `libc++_shared.so` | P0 for Play submission | verify the installed export templates are 16 KB aligned (Godot's NDK r28+ template builds are), rebuild and re-run the device warning check before uploading; Google requires 16 KB support for new submissions targeting recent API levels |

The gameplay debug export and production release are separate acceptance gates.
The debug package uses a dedicated application ID and debug signing identity;
its ads and purchases are simulators. No physical-device installation or signed
release AAB is established by creating that APK. Historical target-SDK, policy,
Data Safety and plugin assumptions in this runbook must be rechecked against the
actual release configuration and current store requirements before submission.
