#!/usr/bin/env bash
# Gameplay-only debug APK or signed Gradle release AAB; never installs a build.
# See docs/ANDROID_DEBUG.md and docs/ANDROID_RELEASE.md.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
REPOSITORY="$(cd -- "$PROJECT/.." && pwd)"
MODE=release
PRESET_ONLY=0
CHECK_ONLY=0
for arg in "$@"; do
 case "$arg" in
  --debug) MODE=debug ;;
  --release) MODE=release ;;
  --preset-only) PRESET_ONLY=1 ;;
  --check) CHECK_ONLY=1 ;;
  *) echo "build_android: unknown argument '$arg'" >&2; exit 2 ;;
 esac
done
TOOLCHAIN="${GRAND_EXHIBIT_ANDROID_TOOLCHAIN:-$HOME/.local/share/grand-exhibit/android-debug-toolchain}"
GODOT="${GODOT:-/data/opt/godot/godot441}"
if [[ -z "${JAVA_HOME:-}" ]]; then
 for java_candidate in "$TOOLCHAIN"/jdk/*; do
  if [[ -x "$java_candidate/bin/java" ]]; then JAVA_HOME="$java_candidate"; break; fi
 done
fi
JAVA_HOME="${JAVA_HOME:-}"
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$TOOLCHAIN/android-sdk}}"
VERSION_CODE="${ANDROID_VERSION_CODE:-1}"
VERSION_NAME="${ANDROID_VERSION_NAME:-1.0.0}"
if [[ "$MODE" == debug ]]; then
 PACKAGE_ID="${ANDROID_PACKAGE_ID:-com.bustillo.grandexhibit.playtest}"
else
 PACKAGE_ID="${ANDROID_PACKAGE_ID:-com.bustillo.grandexhibit}"
fi
export JAVA_HOME ANDROID_SDK_ROOT
if [[ -n "$JAVA_HOME" ]]; then export PATH="$JAVA_HOME/bin:$PATH"; fi
TEMPLATE="$PROJECT/export_presets.template.cfg"
PRESET="$PROJECT/export_presets.cfg"
[[ -f "$TEMPLATE" ]] || { echo "build_android: missing template" >&2; exit 2; }
# Validate every external value before writing the generated Godot config.
python3 - "$VERSION_CODE" "$VERSION_NAME" "$PACKAGE_ID" <<'PY'
import re,sys
code,name,package=sys.argv[1:]
if not code.isdigit() or not 1 <= int(code) <= 2100000000:sys.exit('build_android: invalid version code')
if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9 ._+-]{0,63}',name):sys.exit('build_android: invalid version name')
if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+',package):sys.exit('build_android: invalid package ID')
PY
write_preset() {
 python3 - "$TEMPLATE" "$PRESET" "$MODE" "$VERSION_CODE" "$VERSION_NAME" "$PACKAGE_ID" <<'PY'
import json,sys
from pathlib import Path
source,target,mode,code,name,package=sys.argv[1:]
changes={'version/code':code,'version/name':json.dumps(name),'package/unique_name':json.dumps(package)}
if mode=='debug':
 changes.update({'name':'"Android Gameplay Debug"','gradle_build/use_gradle_build':'false','gradle_build/export_format':'0','gradle_build/target_sdk':'""','gradle_build/min_sdk':'""','architectures/x86_64':'false','export_path':'"build/grand-exhibit-debug.apk"','package/name':'"Grand Exhibit Playtest"'})
lines=Path(source).read_text().splitlines()
for i,line in enumerate(lines):
 key=line.split('=',1)[0]
 if key in changes:lines[i]=key+'='+changes[key]
Path(target).write_text('\n'.join(lines)+'\n')
PY
 echo "build_android: generated $MODE preset for $PACKAGE_ID ($VERSION_NAME / $VERSION_CODE)"
}
if [[ "$PRESET_ONLY" == 1 ]]; then write_preset; exit 0; fi
fail=0
note() { echo "build_android: $*" >&2; fail=1; }
[[ -x "$GODOT" ]] || note "Godot missing; set GODOT to the 4.4.1 executable"
[[ -x "$JAVA_HOME/bin/java" && -x "$JAVA_HOME/bin/keytool" ]] || note "OpenJDK 17 missing; set JAVA_HOME"
[[ -x "$ANDROID_SDK_ROOT/platform-tools/adb" ]] || note "Android platform-tools missing under ANDROID_SDK_ROOT"
APKSIGNER=""
for signer in "$ANDROID_SDK_ROOT"/build-tools/*/apksigner; do
 [[ -x "$signer" ]] && APKSIGNER="$signer"
done
[[ -n "$APKSIGNER" ]] || note "Android build-tools/apksigner missing under ANDROID_SDK_ROOT"
if [[ -x "$GODOT" ]]; then
 ENGINE_VERSION="$("$GODOT" --version)"
 [[ "$ENGINE_VERSION" == 4.4.1.* ]] || note "expected Godot 4.4.1, found $ENGINE_VERSION"
fi
if [[ -x "$JAVA_HOME/bin/java" ]]; then
 JAVA_VERSION="$("$JAVA_HOME/bin/java" -version 2>&1)"
 [[ "$JAVA_VERSION" == *'version "17.'* ]] || note "expected OpenJDK 17"
fi
if [[ "$MODE" == release ]]; then
 for name in GODOT_ANDROID_KEYSTORE_RELEASE_PATH GODOT_ANDROID_KEYSTORE_RELEASE_USER GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD; do
  [[ -n "${!name:-}" ]] || note "missing release signing variable: $name"
 done
 key="${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-}"
 if [[ -n "$key" ]]; then
  [[ -f "$key" ]] || note "release keystore does not exist"
  case "$(realpath -m -- "$key")" in "$REPOSITORY"/*) note "release keystore must be outside the repository" ;; esac
 fi
 [[ -f "$PROJECT/android/.build_version" && -d "$PROJECT/android/build" ]] || note "matching Android Gradle build template is not installed"
 echo "build_android: release still requires integrated/verified billing, ads and current store requirements"
else
 TEMPLATE_DIR="${GODOT_EXPORT_TEMPLATES:-${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates}/4.4.1.stable"
 [[ -f "$TEMPLATE_DIR/android_debug.apk" ]] || note "Godot 4.4.1 Android debug export template missing"
 if [[ "$TEMPLATE_DIR" != "${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/4.4.1.stable" ]]; then
  note "custom template directory is not supported; install templates in Godot's normal data directory"
 fi
fi
if [[ "$fail" != 0 ]]; then echo "build_android: preflight failed; no preset or artifact changed" >&2; exit 1; fi
"$APKSIGNER" --version >/dev/null
if [[ "$CHECK_ONLY" == 1 ]]; then echo "build_android: dependency preflight passed ($MODE); no export performed"; exit 0; fi
write_preset
mkdir -p "$PROJECT/build/android-config/godot"
# Isolate exporter settings; normal editor configuration and game saves stay intact.
export XDG_CONFIG_HOME="$PROJECT/build/android-config"
python3 - "$XDG_CONFIG_HOME/godot/editor_settings-4.4.tres" "$JAVA_HOME" "$ANDROID_SDK_ROOT" <<'PY'
import json,sys
from pathlib import Path
path,java,sdk=sys.argv[1:]
Path(path).write_text('[gd_resource type="EditorSettings" format=3]\n\n[resource]\nexport/android/java_sdk_path='+json.dumps(java)+'\nexport/android/android_sdk_path='+json.dumps(sdk)+'\n')
PY
if [[ "$MODE" == debug ]]; then
 export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="${GODOT_ANDROID_KEYSTORE_DEBUG_PATH:-$TOOLCHAIN/debug.keystore}"
 export GODOT_ANDROID_KEYSTORE_DEBUG_USER="${GODOT_ANDROID_KEYSTORE_DEBUG_USER:-androiddebugkey}"
 export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="${GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD:-android}"
 if [[ ! -f "$GODOT_ANDROID_KEYSTORE_DEBUG_PATH" ]]; then
  mkdir -p "$(dirname -- "$GODOT_ANDROID_KEYSTORE_DEBUG_PATH")"
  "$JAVA_HOME/bin/keytool" -genkeypair -noprompt -keystore "$GODOT_ANDROID_KEYSTORE_DEBUG_PATH" -alias "$GODOT_ANDROID_KEYSTORE_DEBUG_USER" -storepass:env GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD -keypass:env GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD -dname 'CN=Android Debug,O=Android,C=US' -keyalg RSA -keysize 2048 -validity 10000
 fi
 OUT="$PROJECT/build/grand-exhibit-debug.apk";FLAG=--export-debug;PRESET_NAME='Android Gameplay Debug'
else
 OUT="$PROJECT/build/grand-exhibit.aab";FLAG=--export-release;PRESET_NAME='Android Release'
fi
# A failed export never replaces an earlier known artifact.
TEMP_OUT="${OUT%.*}.candidate.${OUT##*.}"
trap 'rm -f -- "$TEMP_OUT"' EXIT
"$GODOT" --headless --audio-driver Dummy --import --path "$PROJECT"
"$GODOT" --headless --audio-driver Dummy --path "$PROJECT" "$FLAG" "$PRESET_NAME" "$TEMP_OUT"
[[ -s "$TEMP_OUT" ]] || { echo 'build_android: export produced no artifact' >&2; exit 1; }
if [[ "$MODE" == debug ]]; then
 "$APKSIGNER" verify --verbose "$TEMP_OUT"
 python3 - "$TEMP_OUT" <<'PY'
import sys,zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
 if z.testzip() is not None:sys.exit('build_android: corrupt APK')
 names=z.namelist()
 if 'AndroidManifest.xml' not in names or 'lib/arm64-v8a/libgodot_android.so' not in names:sys.exit('build_android: incomplete Android package')
 if any(n.startswith(('assets/tests/','assets/tools/','assets/docs/')) for n in names):sys.exit('build_android: development files leaked into APK')
PY
fi
mv -f -- "$TEMP_OUT" "$OUT"
sha256sum "$OUT"
echo "build_android: built $OUT"
if [[ "$MODE" == debug ]]; then
 echo 'Gameplay-only DEBUG build: ads and purchases are simulated. Not a Play release. No device installation performed.'
else
 echo 'Signed export created; device verification and store acceptance remain required.'
fi
