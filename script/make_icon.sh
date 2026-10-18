#!/usr/bin/env bash
# Regenerates Resources/AppIcon.icns and Resources/AppIcon.png from script/make_icon.swift.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/t150-icon.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
swiftc -O -module-cache-path "$WORK/cache" "$ROOT/script/make_icon.swift" -o "$WORK/make_icon"
"$WORK/make_icon" "$WORK"
mkdir -p "$ROOT/Resources"
cp "$WORK/AppIcon.icns" "$ROOT/Resources/AppIcon.icns"
cp "$WORK/AppIcon.png" "$ROOT/Resources/AppIcon.png"
echo "Wrote Resources/AppIcon.icns and Resources/AppIcon.png"
