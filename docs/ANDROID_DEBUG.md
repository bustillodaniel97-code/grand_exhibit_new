# Private Android gameplay build

`tools/build_android.sh --debug` creates `build/grand-exhibit-debug.apk` using
Godot's standard debug export template. It does not require Gradle, an NDK,
a release keystore, a Play Console account or a connected phone. It does not
install the APK. The debug package is `com.bustillo.grandexhibit.playtest`,
separate from the release placeholder, so it has its own Android save storage.

**This build simulates ads and purchases. It is for private gameplay testing,
not store submission or production monetization validation.** It contains the
current live NPC artwork; the revised staged cast is not installed by exporting.

## Commands

```bash
tools/build_android.sh --debug --check   # validate dependencies, write nothing
tools/build_android.sh --debug          # import, export, sign and verify APK
```

Defaults on this development machine:

- Godot: `/data/opt/godot/godot441`, exactly 4.4.1.
- Templates: normal Godot data directory, `export_templates/4.4.1.stable`.
- JDK and Android SDK: `~/.local/share/grand-exhibit/android-debug-toolchain`.
- Debug keystore: `debug.keystore` in that toolchain directory. It uses the
  conventional public Android debug credentials; this is not a release identity.

Override `GODOT`, `JAVA_HOME`, `ANDROID_SDK_ROOT` or
`GRAND_EXHIBIT_ANDROID_TOOLCHAIN` when using another machine. Version overrides:
`ANDROID_VERSION_CODE`, `ANDROID_VERSION_NAME`, `ANDROID_PACKAGE_ID`.
All values are validated before writing the generated, ignored preset.
The build uses an isolated editor-settings directory under `build/android-config`;
it does not change normal Godot settings or existing desktop game saves.

## Toolchain provenance

The September 17 setup downloaded OpenJDK 17 from the official Adoptium GitHub
release and Android build-tools 34.0.0/platform-tools from Google's repository.
Published checksum and archive size were verified before extraction or execution.
See [verified downloads](../../evidence/android-debug-2026-09-17/verified-downloads.json)
for pinned URLs and hashes. No system packages were replaced.

For setup elsewhere, follow [Godot 4.4 Android export documentation](https://docs.godotengine.org/en/4.4/tutorials/export/exporting_for_android.html).
Its general instructions include the larger Gradle/native-build toolchain.
The prebuilt APK path uses the template's SDK levels; Godot rejects min/target
SDK overrides unless Gradle is enabled. Consequently the gameplay debug preset
clears those overrides. The verified template produces min API 21 and target API 34;
these debug settings are not a claim of current Play submission eligibility. Commercial build and current store requirements belong
to [ANDROID_RELEASE.md](ANDROID_RELEASE.md).

## Verification and limits

The script checks APK signing, ZIP integrity, ARM64 engine presence and exclusion
of test/tool/document directories. It promotes the candidate APK to the final
filename only after those checks pass, preserving an earlier artifact on failure.
Only ARM64 is included to keep the private phone build small.

A successful package export does not prove the game launches on a phone. Next
acceptance needs a connected ARM64 Android device: launch, touch controls, frame
pacing, crowded museums, memory/heat, background/resume, offline returns and
museum graduation followed by save/reopen. No automated phone installation is
part of this script.
