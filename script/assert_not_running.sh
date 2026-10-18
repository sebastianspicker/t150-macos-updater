#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Never kill or replace a potentially active firmware updater.
BUNDLE_ID=org.t150updater.app
RUNNING="$(/usr/bin/lsappinfo find "bundleID=$BUNDLE_ID")"
if [[ "$RUNNING" == *ASN:* ]]; then
    echo 'T150 Firmware Updater is running. Finish its operation and quit before rebuilding.' >&2
    exit 1
fi
mkdir -p "$ROOT/.build/packaging"
xcrun clang -Wall -Wextra -Werror "$ROOT/script/check_lock.c" -o "$ROOT/.build/packaging/check-lock"
"$ROOT/.build/packaging/check-lock" \
    "$HOME/Library/Application Support/T150 Firmware Updater/gui.lock" \
    "/private/tmp/t150-native-engine-$(id -u).lock"
