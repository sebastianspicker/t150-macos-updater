#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT/dist/T150 Firmware Updater.app}"
plutil -lint "$APP/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$APP"
for NOTICE in README.md T150Updater-LICENSE.txt licenses/unshield-MIT.txt licenses/RSA-MD5.txt; do
    [[ -s "$APP/Contents/Resources/ThirdPartyNotices/$NOTICE" ]] || { echo "Missing notice: $NOTICE" >&2; exit 1; }
done
[[ -s "$APP/Contents/Resources/AppIcon.icns" ]] || { echo "Missing app icon" >&2; exit 1; }
for REL in MacOS/T150Updater Resources/Tools/t150-engine Resources/Tools/unshield; do
    TOOL="$APP/Contents/$REL"
    [[ -x "$TOOL" ]] || { echo "Missing tool: $REL" >&2; exit 1; }
    while IFS= read -r DEP; do
        case "$DEP" in /usr/lib/*|/System/Library/*) ;; *) echo "Non-system dependency in $REL: $DEP" >&2; exit 1;; esac
    done < <(otool -L "$TOOL" | tail -n +2 | awk '{print $1}')
    MIN="$(xcrun vtool -show-build "$TOOL" | awk '/minos/{print $2}')"
    [[ "$MIN" == 14.0 ]] || { echo "Unexpected minimum macOS in $REL: $MIN" >&2; exit 1; }
    if strings "$TOOL" | grep -E '/Users/|/opt/homebrew/' > /dev/null; then
        echo "Developer machine path remains in $REL." >&2; exit 1
    fi
done
if find "$APP" -type f \( -iname '*.exe' -o -iname '*.sys' -o -iname '*.tmf' -o -iname '*.cab' -o -iname '*.bin' \) | grep -q .; then
    echo 'Proprietary installer/firmware or capture found in bundle.' >&2; exit 1
fi
"$APP/Contents/Resources/Tools/t150-engine" self-test
"$APP/Contents/Resources/Tools/unshield" -V
echo 'Bundle audit passed (offline; no wheel commands).'
