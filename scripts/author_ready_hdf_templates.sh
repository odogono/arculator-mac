#!/bin/bash
#
# One-time authoring workflow for ready-to-use hard-disc templates.
#
# This script uses the AppleScript automation surface to:
# - create a blank default-geometry HDF
# - attach it to a dedicated authoring config
# - boot the config
# - pause for in-guest formatting
# - verify the image classifier now reports "initialized"
# - reboot once more for manual first-desktop validation
#
# The guest formatting step is still manual because the repo does not yet
# contain a checked-in formatter coordinate/key sequence for either controller
# family. The host-side setup, verification, screenshots, and output naming are
# deterministic and repeatable.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_OUTPUT_DIR="$ROOT_DIR/macos/templates"
DEFAULT_WORK_DIR="$ROOT_DIR/tmp/template-authoring"
DEFAULT_SCREENSHOT_DIR="$DEFAULT_WORK_DIR/screenshots"

APP_PATH=""
IDE_CONFIG=""
ST506_CONFIG=""
OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
WORK_DIR="$DEFAULT_WORK_DIR"
SCREENSHOT_DIR="$DEFAULT_SCREENSHOT_DIR"
BOOT_DELAY=20
VALIDATION_DELAY=12
IDE_GUEST_AUTOMATION=""
ST506_GUEST_AUTOMATION=""
FORCE=0

usage() {
    cat <<EOF
Usage: $0 --app <Arculator.app> --ide-config <name> --st506-config <name> [options]

Required:
  --app PATH             Built Arculator.app to control via osascript.
  --ide-config NAME      Dedicated config name for IDE template authoring.
  --st506-config NAME    Dedicated config name for ST-506 template authoring.

Optional:
  --output-dir DIR       Final template destination. Default: $DEFAULT_OUTPUT_DIR
  --work-dir DIR         Scratch directory for candidate images. Default: $DEFAULT_WORK_DIR
  --screenshots DIR      Screenshot output directory. Default: $DEFAULT_SCREENSHOT_DIR
  --boot-delay SECONDS   Wait after first boot before prompting. Default: 20
  --validation-delay N   Wait after validation reboot before screenshot. Default: 12
  --ide-guest-automation PATH
                         Optional executable/script to run after IDE boot.
  --st506-guest-automation PATH
                         Optional executable/script to run after ST-506 boot.
  --force                Overwrite existing destination templates.
  --help                 Show this message.

Outputs:
  ide_101x16x63.hdf.zlib
  st506_615x8x32.hdf

Notes:
  - Arculator should already be running before you invoke this script.
  - Each config should already target the correct controller family.
  - The IDE template is normally provided by the checked-in formatted seed.
  - For templates that still need in-guest formatting, the script pauses for
    manual work, then verifies that the host-side image classifier reports
    "initialized".
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --app)
            APP_PATH="${2:-}"
            shift 2
            ;;
        --ide-config)
            IDE_CONFIG="${2:-}"
            shift 2
            ;;
        --st506-config)
            ST506_CONFIG="${2:-}"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="${2:-}"
            shift 2
            ;;
        --work-dir)
            WORK_DIR="${2:-}"
            shift 2
            ;;
        --screenshots)
            SCREENSHOT_DIR="${2:-}"
            shift 2
            ;;
        --boot-delay)
            BOOT_DELAY="${2:-}"
            shift 2
            ;;
        --validation-delay)
            VALIDATION_DELAY="${2:-}"
            shift 2
            ;;
        --ide-guest-automation)
            IDE_GUEST_AUTOMATION="${2:-}"
            shift 2
            ;;
        --st506-guest-automation)
            ST506_GUEST_AUTOMATION="${2:-}"
            shift 2
            ;;
        --force)
            FORCE=1
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

require_arg() {
    local name="$1"
    local value="$2"
    if [ -z "$value" ]; then
        echo "Missing required argument: $name" >&2
        usage >&2
        exit 1
    fi
}

require_arg --app "$APP_PATH"
require_arg --ide-config "$IDE_CONFIG"
require_arg --st506-config "$ST506_CONFIG"

if [ ! -d "$APP_PATH" ]; then
    echo "App not found: $APP_PATH" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR" "$WORK_DIR" "$SCREENSHOT_DIR"

run_inline_applescript() {
    local script="$1"
    shift
    osascript - "$@" <<APPLESCRIPT
$script
APPLESCRIPT
}

stop_if_running() {
    local state
    state="$(run_inline_applescript "
on run argv
    tell application \"$APP_PATH\"
        return emulation state
    end tell
end run
")"
    if [ "$state" != "idle" ]; then
        run_inline_applescript "
on run argv
    tell application \"$APP_PATH\"
        stop emulation
        clear injected input
    end tell
end run
"
    fi
}

assert_image_state() {
    local image_path="$1"
    local expected_state="$2"
    if [ ! -f "$image_path" ]; then
        echo "Expected image at '$image_path' but it does not exist" >&2
        exit 1
    fi

    local has_nonzero=0
    if LC_ALL=C od -An -t x1 -N 65536 "$image_path" | tr -d ' \n' | rg -q '[1-9a-fA-F]'; then
        has_nonzero=1
    fi

    case "$expected_state" in
        "blank raw")
            if [ "$has_nonzero" -ne 0 ]; then
                echo "Expected blank raw image at '$image_path', but found non-zero data in the first 64 KiB" >&2
                exit 1
            fi
            ;;
        "initialized")
            if [ "$has_nonzero" -eq 0 ]; then
                echo "Expected initialized image at '$image_path', but the first 64 KiB is still all zeroes" >&2
                exit 1
            fi
            ;;
        *)
            echo "Unknown expected image state '$expected_state'" >&2
            exit 1
            ;;
    esac
}

compress_zlib() {
    local source_path="$1"
    local destination_path="$2"
    python3 -c 'import pathlib, sys, zlib; source = pathlib.Path(sys.argv[1]); destination = pathlib.Path(sys.argv[2]); compressor = zlib.compressobj(9, zlib.DEFLATED, -15); data = source.read_bytes(); destination.write_bytes(compressor.compress(data) + compressor.flush())' "$source_path" "$destination_path"
}

author_template() {
    local controller="$1"
    local config_name="$2"
    local cylinders="$3"
    local heads="$4"
    local sectors="$5"
    local guest_automation="$6"
    local base_name="${controller}_${cylinders}x${heads}x${sectors}.hdf"
    local candidate_path="$WORK_DIR/${base_name%.hdf}.candidate.hdf"
    local final_path="$OUTPUT_DIR/$base_name"
    local final_resource_path="$final_path"
    if [ "$controller" = "ide" ]; then
        final_resource_path="$final_path.zlib"
    fi

    if [ -e "$final_resource_path" ] && [ "$FORCE" -ne 1 ]; then
        echo "Destination already exists: $final_resource_path (use --force to overwrite)" >&2
        exit 1
    fi

    rm -f "$candidate_path"
    rm -f "$SCREENSHOT_DIR/${base_name%.hdf}"-*.png

    stop_if_running

    echo "Creating blank $controller candidate: $candidate_path"
    run_inline_applescript "
on run argv
    set configName to item 1 of argv
    set imagePath to item 2 of argv
    tell application \"$APP_PATH\"
        load config configName
        create hard disc image imagePath cylinders $cylinders heads $heads sectors $sectors controller \"$controller\" initialization \"blank\"
        set internal drive 4 path imagePath cylinders $cylinders heads $heads sectors $sectors
        clear injected input
    end tell
end run
" "$config_name" "$candidate_path"

    assert_image_state "$candidate_path" "blank raw"

    echo "Booting $config_name for $controller formatting"
    run_inline_applescript "
on run argv
    tell application \"$APP_PATH\"
        start config \"$config_name\"
    end tell
end run
"
    sleep "$BOOT_DELAY"

    run_inline_applescript "
on run argv
    tell application \"$APP_PATH\"
        capture emulation screenshot \"$SCREENSHOT_DIR/${base_name%.hdf}-pre-format.png\"
    end tell
end run
" || true

    if [ -n "$guest_automation" ]; then
        if [ ! -x "$guest_automation" ] && [ ! -f "$guest_automation" ]; then
            echo "Guest automation script not found: $guest_automation" >&2
            exit 1
        fi

        echo "Running guest automation: $guest_automation"
        "$guest_automation" \
            --app "$APP_PATH" \
            --config "$config_name" \
            --controller "$controller" \
            --image "$candidate_path" \
            --screenshot-dir "$SCREENSHOT_DIR" \
            --base-name "${base_name%.hdf}"
    else
        cat <<EOF

[$controller] Guest formatting required
Config:       $config_name
Candidate:    $candidate_path
Screenshot:   $SCREENSHOT_DIR/${base_name%.hdf}-pre-format.png

Format the hard disc inside the guest until it is fully usable, then return here.
Press Enter to continue with host-side verification.
EOF
        read -r _
    fi

    stop_if_running
    assert_image_state "$candidate_path" "initialized"

    echo "Rebooting $config_name for first-desktop validation"
    run_inline_applescript "
on run argv
    tell application \"$APP_PATH\"
        start config \"$config_name\"
    end tell
end run
"
    sleep "$VALIDATION_DELAY"

    run_inline_applescript "
on run argv
    tell application \"$APP_PATH\"
        capture emulation screenshot \"$SCREENSHOT_DIR/${base_name%.hdf}-validation.png\"
    end tell
end run
" || true

    cat <<EOF

[$controller] Validation checkpoint
Validation screenshot: $SCREENSHOT_DIR/${base_name%.hdf}-validation.png

Confirm that the hard disc mounts on first desktop load, then press Enter to finalize.
EOF
    read -r _

    stop_if_running
    run_inline_applescript "
on run argv
    tell application \"$APP_PATH\"
        load config \"$config_name\"
        eject internal drive 4
    end tell
end run
"

    if [ -e "$final_resource_path" ]; then
        rm -f "$final_resource_path"
    fi
    if [ "$controller" = "ide" ]; then
        compress_zlib "$candidate_path" "$final_resource_path"
        rm -f "$candidate_path"
    else
        mv "$candidate_path" "$final_resource_path"
    fi
    echo "Wrote template: $final_resource_path"
}

IDE_TEMPLATE="$OUTPUT_DIR/ide_101x16x63.hdf.zlib"
if [ -f "$IDE_TEMPLATE" ] && [ "$FORCE" -ne 1 ]; then
    echo "Using existing IDE seed template: $IDE_TEMPLATE"
else
    author_template ide "$IDE_CONFIG" 101 16 63 "$IDE_GUEST_AUTOMATION"
fi
author_template st506 "$ST506_CONFIG" 615 8 32 "$ST506_GUEST_AUTOMATION"

echo ""
echo "Template authoring complete."
echo "Templates:"
echo "  $OUTPUT_DIR/ide_101x16x63.hdf.zlib"
echo "  $OUTPUT_DIR/st506_615x8x32.hdf"
echo "Screenshots:"
echo "  $SCREENSHOT_DIR"
