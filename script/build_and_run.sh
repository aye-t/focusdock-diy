#!/bin/bash
set -euo pipefail

mode="${1:-run}"
app_name="FocusDock"
bundle_id="com.focusdock.mac"
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_dir="$root_dir/FocusDockMac"
app_bundle="$project_dir/dist/$app_name.app"
app_binary="$app_bundle/Contents/MacOS/$app_name"

pkill -x "$app_name" >/dev/null 2>&1 || true
"$project_dir/Scripts/build-app.sh"

open_app() {
    /usr/bin/open -n "$app_bundle"
}

verify_process() {
    for _ in {1..30}; do
        if pgrep -x "$app_name" >/dev/null; then
            return 0
        fi
        sleep 0.1
    done
    echo "$app_name did not stay running after launch." >&2
    return 1
}

case "$mode" in
    run)
        open_app
        ;;
    --debug|debug)
        lldb -- "$app_binary"
        ;;
    --logs|logs)
        open_app
        /usr/bin/log stream --info --style compact --predicate "process == \"$app_name\""
        ;;
    --telemetry|telemetry)
        open_app
        /usr/bin/log stream --info --style compact --predicate "subsystem == \"$bundle_id\""
        ;;
    --verify|verify)
        open_app
        verify_process
        echo "$app_name is running."
        ;;
    *)
        echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
        exit 2
        ;;
esac
