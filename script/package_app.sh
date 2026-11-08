#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
if [[ "${1:-}" != --under-update-locks ]]; then
    "$ROOT/script/assert_not_running.sh"
    BASE="$HOME/Library/Application Support/T150 Firmware Updater"
    # shellcheck disable=SC2174 # only BASE must be 0700; parents keep their modes
    mkdir -p -m 700 "$BASE"
    [[ "$(stat -f '%u:%Lp' "$BASE")" == "$(id -u):700" && ! -L "$BASE" ]] || { echo 'Unsafe updater support directory.' >&2; exit 1; }
    exec "$ROOT/.build/packaging/check-lock" --hold \
        "$BASE/gui.lock" "/private/tmp/t150-native-engine-$(id -u).lock" \
        -- /bin/bash "$0" --under-update-locks
fi
[[ -s "$ROOT/Resources/AppIcon.icns" ]] || { echo "Missing Resources/AppIcon.icns; run script/make_icon.sh." >&2; exit 1; }
export MACOSX_DEPLOYMENT_TARGET=14.0
"$ROOT/script/build_unshield.sh"
"$ROOT/Native/build.sh"
swift build -c release --product T150Updater \
    -Xswiftc -file-prefix-map -Xswiftc "$ROOT=."
BIN="$(swift build -c release --show-bin-path)"
mkdir -p "$ROOT/dist"
STAGE="$(mktemp -d "$ROOT/dist/.package.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/T150 Firmware Updater.app"
CONTENTS="$APP/Contents"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources/Tools" "$CONTENTS/Resources/ThirdPartyNotices/licenses"
cp "$BIN/T150Updater" "$CONTENTS/MacOS/T150Updater"
cp "$ROOT/Native/build/t150-engine" "$CONTENTS/Resources/Tools/t150-engine"
cp "$ROOT/.build/third-party/unshield-build/src/unshield" "$CONTENTS/Resources/Tools/unshield"
for TOOL in "$CONTENTS/MacOS/T150Updater" "$CONTENTS/Resources/Tools/"*; do xcrun strip -S -x "$TOOL"; done
cp "$ROOT/docs/licenses/"*.txt "$CONTENTS/Resources/ThirdPartyNotices/licenses/"
cp "$ROOT/docs/THIRD_PARTY.md" "$CONTENTS/Resources/ThirdPartyNotices/README.md"
cp "$ROOT/LICENSE" "$CONTENTS/Resources/ThirdPartyNotices/T150Updater-LICENSE.txt"
cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>T150Updater</string>
<key>CFBundleIdentifier</key><string>org.t150updater.app</string>
<key>CFBundleName</key><string>T150 Firmware Updater</string>
<key>CFBundleDisplayName</key><string>T150 Firmware Updater</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleShortVersionString</key><string>0.6.0</string>
<key>CFBundleVersion</key><string>7</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSMultipleInstancesProhibited</key><true/>
</dict></plist>
PLIST
# All helper dependencies are statically linked or supplied by macOS. Sign inside out.
for TOOL in "$CONTENTS/Resources/Tools/"*; do codesign --force --sign - "$TOOL"; done
codesign --force --sign - "$CONTENTS/MacOS/T150Updater"
codesign --force --sign - "$APP"
"$ROOT/script/audit_bundle.sh" "$APP"
DEST="$ROOT/dist/T150 Firmware Updater.app"
if [[ -e "$DEST" ]]; then
    rm -rf "$ROOT/dist/T150 Firmware Updater.previous.app"
    mv "$DEST" "$ROOT/dist/T150 Firmware Updater.previous.app"
fi
mv "$APP" "$DEST"
ditto -c -k --sequesterRsrc --keepParent "$DEST" "$ROOT/dist/T150-Firmware-Updater-macOS-$(uname -m).zip"
echo "App: $DEST"
echo "Local ad-hoc signature only; this build is not notarized."
