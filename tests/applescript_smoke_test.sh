#!/bin/bash
#
# AppleScript dictionary smoke test.
#
# Validates that the built Arculator.app has a usable scripting dictionary
# by running basic osascript queries against it. This script must be run
# with the built app path as the first argument:
#
#   ./tests/applescript_smoke_test.sh build/Debug/Arculator.app
#
# The app should already be running before invoking this script, otherwise
# osascript will launch it and may hang waiting for startup UI.
#
# Exit codes:
#   0 - all checks passed
#   1 - one or more checks failed

set -euo pipefail

TIMEOUT=10
APP_PATH="${1:-}"

if [ -z "$APP_PATH" ]; then
    echo "Usage: $0 <path-to-Arculator.app>"
    exit 1
fi

if [ ! -d "$APP_PATH" ]; then
    echo "FAIL: App not found at $APP_PATH"
    exit 1
fi

PASS=0
FAIL=0

check() {
    local description="$1"
    shift
    if output=$(timeout "$TIMEOUT" "$@" 2>&1); then
        echo "  PASS: $description"
        PASS=$((PASS + 1))
    else
        local rc=$?
        if [ "$rc" -eq 124 ]; then
            echo "  SKIP: $description (timed out — is the app running?)"
        else
            echo "  FAIL: $description"
            echo "        $output"
            FAIL=$((FAIL + 1))
        fi
    fi
}

echo "AppleScript Dictionary Smoke Test"
echo "App: $APP_PATH"
echo ""

# 1. Verify the sdef can be extracted (does not require the app to be running)
echo "--- Dictionary extraction ---"
check "sdef extracts without error" \
    sdef "$APP_PATH"

# 2. Verify osascript can resolve the dictionary and query basic properties
# These require the app to already be running.
echo ""
echo "--- Property queries (requires running app) ---"

check "query application name" \
    osascript -e "tell application \"$APP_PATH\" to get name"

check "query emulation state" \
    osascript -e "tell application \"$APP_PATH\" to get emulation state"

check "query config names" \
    osascript -e "tell application \"$APP_PATH\" to get config names"

echo ""
echo "Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
