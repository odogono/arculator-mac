#!/bin/bash
#
# IDE-first guest automation helper for template authoring.
#
# This script is intended to be called by author_ready_hdf_templates.sh through
# --ide-guest-automation. It drives a conservative sequence:
# - open the RISC OS command line with F12
# - type a formatter launch command
# - perform optional absolute mouse clicks
# - stop and hand control back to the authoring script for classifier checks
#
# The exact formatter command and click coordinates remain configurable because
# they depend on the guest ROM/tools layout.

set -euo pipefail

APP_PATH=""
CONFIG_NAME=""
CONTROLLER=""
IMAGE_PATH=""
SCREENSHOT_DIR=""
BASE_NAME=""
FORMATTER_COMMAND=""
POST_TASKMANAGER_DELAY=1
POST_COMMAND_DELAY=2
CLICK_DELAY=1
CLICK_SEQUENCE=""
REQUIRE_CAPTURE_CONFIRMATION=0

usage() {
    cat <<EOF
Usage: $0 --app <Arculator.app> --config <name> --controller ide --image <path> --screenshot-dir <dir> --base-name <name> [options]

Required:
  --app PATH
  --config NAME
  --controller ide
  --image PATH
  --screenshot-dir DIR
  --base-name NAME

Optional:
  --formatter-command TEXT
      Command typed into the RISC OS command line after F12.
      Default: none. If omitted, the script stops at the '*' prompt so the
      correct formatter path can be discovered manually.
  --click-sequence "x1,y1;x2,y2;..."
      Optional absolute guest click coordinates to perform after launching the formatter.
  --post-taskmanager-delay SECONDS
      Delay after opening Task Manager. Default: $POST_TASKMANAGER_DELAY
  --post-command-delay SECONDS
      Delay after submitting the formatter command. Default: $POST_COMMAND_DELAY
  --click-delay SECONDS
      Delay after each click. Default: $CLICK_DELAY
  --no-capture-confirmation
      No-op for backward compatibility. Guest automation no longer requires host capture.
  --require-capture-confirmation
      Re-enable the manual "click to capture mouse" confirmation step for debugging.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --app)
            APP_PATH="${2:-}"
            shift 2
            ;;
        --config)
            CONFIG_NAME="${2:-}"
            shift 2
            ;;
        --controller)
            CONTROLLER="${2:-}"
            shift 2
            ;;
        --image)
            IMAGE_PATH="${2:-}"
            shift 2
            ;;
        --screenshot-dir)
            SCREENSHOT_DIR="${2:-}"
            shift 2
            ;;
        --base-name)
            BASE_NAME="${2:-}"
            shift 2
            ;;
        --formatter-command)
            FORMATTER_COMMAND="${2:-}"
            shift 2
            ;;
        --click-sequence)
            CLICK_SEQUENCE="${2:-}"
            shift 2
            ;;
        --post-taskmanager-delay)
            POST_TASKMANAGER_DELAY="${2:-}"
            shift 2
            ;;
        --post-command-delay)
            POST_COMMAND_DELAY="${2:-}"
            shift 2
            ;;
        --click-delay)
            CLICK_DELAY="${2:-}"
            shift 2
            ;;
        --no-capture-confirmation)
            REQUIRE_CAPTURE_CONFIRMATION=0
            shift
            ;;
        --require-capture-confirmation)
            REQUIRE_CAPTURE_CONFIRMATION=1
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [ -z "$APP_PATH" ] || [ -z "$CONFIG_NAME" ] || [ -z "$IMAGE_PATH" ] || [ -z "$SCREENSHOT_DIR" ] || [ -z "$BASE_NAME" ]; then
    usage >&2
    exit 1
fi

if [ "$CONTROLLER" != "ide" ]; then
    echo "This helper only supports --controller ide" >&2
    exit 1
fi

mkdir -p "$SCREENSHOT_DIR"

run_inline_applescript() {
    local script="$1"
    shift
    osascript - "$@" <<APPLESCRIPT
$script
APPLESCRIPT
}

press_key() {
    local key_name="$1"
    local hold="${2:-0.05}"
    run_inline_applescript "
on run argv
    set keyName to item 1 of argv
    set holdSeconds to (item 2 of argv) as real
    tell application \"$APP_PATH\"
        inject key down keyName
        delay holdSeconds
        inject key up keyName
    end tell
end run
" "$key_name" "$hold"
}

open_command_line() {
    run_inline_applescript "
on run argv
    tell application \"$APP_PATH\"
        inject key down \"escape\"
        delay 0.1
        inject key up \"escape\"
        delay 0.2
        inject key down \"f12\"
        delay 0.1
        inject key up \"f12\"
    end tell
end run
"
}

type_formatter_command() {
    run_inline_applescript "
on run argv
    set formatterCommand to item 1 of argv
    tell application \"$APP_PATH\"
        type text formatterCommand
        delay 0.1
        inject key down \"return\"
        delay 0.05
        inject key up \"return\"
    end tell
end run
" "$FORMATTER_COMMAND"
}

click_point() {
    local x="$1"
    local y="$2"
    run_inline_applescript "
on run argv
    set xpos to (item 1 of argv) as integer
    set ypos to (item 2 of argv) as integer
    tell application \"$APP_PATH\"
        move guest mouse to x xpos y ypos
        delay 0.05
        inject mouse down button 1
        delay 0.05
        inject mouse up button 1
    end tell
end run
" "$x" "$y"
}

echo "Opening command line in $CONFIG_NAME"
if [ "$REQUIRE_CAPTURE_CONFIRMATION" -eq 1 ]; then
    cat <<EOF

The emulator window is still showing "Click to capture mouse".
Click once inside the emulated display area to capture input, then press Enter.
EOF
    read -r _
fi

open_command_line
sleep "$POST_TASKMANAGER_DELAY"

run_inline_applescript "
on run argv
    tell application \"$APP_PATH\"
        capture emulation screenshot \"$SCREENSHOT_DIR/${BASE_NAME}-task-manager.png\"
    end tell
end run
" || true

if [ -n "$FORMATTER_COMMAND" ]; then
    echo "Typing formatter command: $FORMATTER_COMMAND"
    type_formatter_command
    sleep "$POST_COMMAND_DELAY"
else
    cat <<EOF

No formatter command configured.
The guest is now at the RISC OS '*' prompt. Launch the correct formatter
manually from here or via the desktop, then press Enter in this terminal to
continue screenshot capture.
EOF
    read -r _
fi

run_inline_applescript "
on run argv
    tell application \"$APP_PATH\"
        capture emulation screenshot \"$SCREENSHOT_DIR/${BASE_NAME}-formatter-launched.png\"
    end tell
end run
" || true

if [ -n "$CLICK_SEQUENCE" ]; then
    old_ifs="$IFS"
    IFS=';'
    for point in $CLICK_SEQUENCE; do
        IFS="$old_ifs"
        x="${point%%,*}"
        y="${point##*,}"
        if [ -z "$x" ] || [ -z "$y" ] || [ "$x" = "$point" ]; then
            echo "Invalid click point: $point" >&2
            exit 1
        fi
        echo "Clicking guest point $x,$y"
        click_point "$x" "$y"
        sleep "$CLICK_DELAY"
        IFS=';'
    done
    IFS="$old_ifs"
fi

cat <<EOF

IDE guest automation completed.
Config:               $CONFIG_NAME
Image:                $IMAGE_PATH
Formatter command:    ${FORMATTER_COMMAND:-<manual>}
Screenshots:
  $SCREENSHOT_DIR/${BASE_NAME}-task-manager.png
  $SCREENSHOT_DIR/${BASE_NAME}-formatter-launched.png

If the formatter still requires extra guest interaction, complete it now and
then return to the calling authoring script.
EOF
