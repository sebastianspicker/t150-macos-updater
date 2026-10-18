#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-run}"
case "$MODE" in run|--debug|--logs|--telemetry|--verify) ;; *) echo "Usage: $0 [--debug|--logs|--telemetry|--verify]" >&2; exit 2;; esac
"$ROOT/script/package_app.sh"
APP="$ROOT/dist/T150 Firmware Updater.app"
case "$MODE" in
    --debug) exec lldb -- "$APP/Contents/MacOS/T150Updater" ;;
    --logs|--telemetry)
        /usr/bin/open -n "$APP"
        exec /usr/bin/log stream --info --style compact --predicate 'process == "T150Updater"' ;;
    --verify)
        /usr/bin/open -n "$APP"
        sleep 2
        /usr/bin/lsappinfo find bundleID=org.t150updater.app | grep -q ASN:
        echo 'App registered with Launch Services; no firmware operation requested.' ;;
    run) /usr/bin/open -n "$APP" ;;
esac
