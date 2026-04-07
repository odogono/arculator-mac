#!/bin/bash
#
# AppleScript internal-drive smoke test.
#
# Validates that the built app can create, attach, and query a blank HDF through
# the real osascript surface.
#
# Usage:
#   ./tests/applescript_internal_drive_smoke_test.sh build/Debug/Arculator.app "My Config" ide
#
# Optional fourth argument overrides the temp directory.

set -euo pipefail

APP_PATH="${1:-}"
CONFIG_NAME="${2:-}"
CONTROLLER="${3:-ide}"
TMP_ROOT="${4:-/tmp/arculator-applescript-smoke}"

if [ -z "$APP_PATH" ] || [ -z "$CONFIG_NAME" ]; then
    echo "Usage: $0 <Arculator.app> <config-name> [ide|st506] [temp-dir]" >&2
    exit 1
fi

if [ ! -d "$APP_PATH" ]; then
    echo "FAIL: App not found at $APP_PATH" >&2
    exit 1
fi

case "$CONTROLLER" in
    ide)
        CYLINDERS=100
        HEADS=16
        SECTORS=63
        ;;
    st506)
        CYLINDERS=615
        HEADS=8
        SECTORS=32
        ;;
    *)
        echo "FAIL: controller must be 'ide' or 'st506'" >&2
        exit 1
        ;;
esac

mkdir -p "$TMP_ROOT"
IMAGE_PATH="$TMP_ROOT/${CONTROLLER}_${CYLINDERS}x${HEADS}x${SECTORS}.hdf"
rm -f "$IMAGE_PATH"

cleanup() {
    rm -f "$IMAGE_PATH"
}
trap cleanup EXIT

run_inline_applescript() {
    local script="$1"
    shift
    osascript /dev/stdin "$@" <<APPLESCRIPT
$script
APPLESCRIPT
}

echo "AppleScript Internal Drive Smoke Test"
echo "App:        $APP_PATH"
echo "Config:     $CONFIG_NAME"
echo "Controller: $CONTROLLER"
echo "Image:      $IMAGE_PATH"
echo ""

run_inline_applescript "
on run argv
    set configName to item 1 of argv
    set imagePath to item 2 of argv
    tell application \"$APP_PATH\"
        if emulation state is not \"idle\" then
            stop emulation
        end if
        load config configName
        create hard disc image imagePath cylinders $CYLINDERS heads $HEADS sectors $SECTORS controller \"$CONTROLLER\" initialization \"blank\"
        set internal drive 4 path imagePath cylinders $CYLINDERS heads $HEADS sectors $SECTORS
        set driveInfo to (internal drive info 4)
        return (path of driveInfo as text) & linefeed & (controllerKind of driveInfo as text) & linefeed & (imageState of driveInfo as text)
    end tell
end run
" "$CONFIG_NAME" "$IMAGE_PATH" >"$TMP_ROOT/result.txt"

mapfile -t result_lines <"$TMP_ROOT/result.txt"
ACTUAL_PATH="${result_lines[0]:-}"
ACTUAL_CONTROLLER="${result_lines[1]:-}"
ACTUAL_STATE="${result_lines[2]:-}"

FAIL=0

if [ "$ACTUAL_PATH" != "$IMAGE_PATH" ]; then
    echo "FAIL: internal drive path mismatch" >&2
    echo "  expected: $IMAGE_PATH" >&2
    echo "  actual:   $ACTUAL_PATH" >&2
    FAIL=1
else
    echo "PASS: created image path reported correctly"
fi

if [ "$ACTUAL_CONTROLLER" != "$CONTROLLER" ]; then
    echo "FAIL: controller kind mismatch" >&2
    echo "  expected: $CONTROLLER" >&2
    echo "  actual:   $ACTUAL_CONTROLLER" >&2
    FAIL=1
else
    echo "PASS: controller kind reported correctly"
fi

if [ "$ACTUAL_STATE" != "blank raw" ]; then
    echo "FAIL: expected blank raw state" >&2
    echo "  actual: $ACTUAL_STATE" >&2
    FAIL=1
else
    echo "PASS: blank image classified as blank raw"
fi

run_inline_applescript "
on run argv
    set configName to item 1 of argv
    tell application \"$APP_PATH\"
        if emulation state is not \"idle\" then
            stop emulation
        end if
        load config configName
        eject internal drive 4
    end tell
end run
" "$CONFIG_NAME" >/dev/null

if [ "$FAIL" -ne 0 ]; then
    exit 1
fi
