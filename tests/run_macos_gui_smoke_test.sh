#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-Debug}"
APP_NAME="Arculator"
APP_PATH="${APP_PATH:-$PWD/build/$CONFIGURATION/$APP_NAME.app}"
APP_SCRIPT="$PWD/tests/macos_gui_smoke_test.applescript"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/arculator-gui-smoke.XXXXXX")"
BACKUP_ROOT="$TMP_ROOT/backups"
REAL_HOME="${HOME}"
SUPPORT_ROOT="$REAL_HOME/Library/Application Support/Arculator"
CONFIG_NAME="smoke-test-$$"
CONFIG_PATH="$SUPPORT_ROOT/configs/$CONFIG_NAME.cfg"
GLOBAL_CONFIG_PATH="$SUPPORT_ROOT/arc.cfg"
SCRIPT_LOG="$TMP_ROOT/ui-script.log"
CONFIG_BACKUP_PATH="$BACKUP_ROOT/config.cfg"
GLOBAL_BACKUP_PATH="$BACKUP_ROOT/arc.cfg"

app_pid=""
config_backup_mode="absent"
global_backup_mode="absent"

process_state() {
	ps -o stat= -p "$1" 2>/dev/null | awk 'NR == 1 { print $1 }'
}

process_is_live() {
	state="$(process_state "$1")"
	[ -n "$state" ] && [ "${state#Z}" = "$state" ]
}

cleanup() {
	if [ -n "$app_pid" ] && process_is_live "$app_pid"; then
		kill "$app_pid" 2>/dev/null || true
	fi
	if [ -n "$app_pid" ]; then
		wait "$app_pid" 2>/dev/null || true
	fi

	case "$config_backup_mode" in
		file)
			mkdir -p "$(dirname "$CONFIG_PATH")"
			cp "$CONFIG_BACKUP_PATH" "$CONFIG_PATH"
			;;
		absent)
			rm -f "$CONFIG_PATH"
			;;
	esac

	case "$global_backup_mode" in
		file)
			mkdir -p "$(dirname "$GLOBAL_CONFIG_PATH")"
			cp "$GLOBAL_BACKUP_PATH" "$GLOBAL_CONFIG_PATH"
			;;
		absent)
			rm -f "$GLOBAL_CONFIG_PATH"
			;;
	esac

	rm -rf "$TMP_ROOT"
}

trap cleanup EXIT INT TERM

mkdir -p \
	"$BACKUP_ROOT" \
	"$SUPPORT_ROOT/configs" \
	"$SUPPORT_ROOT/cmos" \
	"$SUPPORT_ROOT/hostfs" \
	"$SUPPORT_ROOT/podules" \
	"$SUPPORT_ROOT/roms"

if [ -f "$CONFIG_PATH" ]; then
	cp "$CONFIG_PATH" "$CONFIG_BACKUP_PATH"
	config_backup_mode="file"
fi

if [ -f "$GLOBAL_CONFIG_PATH" ]; then
	cp "$GLOBAL_CONFIG_PATH" "$GLOBAL_BACKUP_PATH"
	global_backup_mode="file"
fi

cat >"$GLOBAL_CONFIG_PATH" <<EOF
rom_path = $PWD/roms
sound_enable = 0
stereo = 1
sound_gain = 0
sound_filter = 0
disc_noise_gain = 9999
first_fullscreen = 0
EOF

cat >"$CONFIG_PATH" <<'EOF'
machine = a3000
disc_name_0 = 
disc_name_1 = 
disc_name_2 = 
disc_name_3 = 
mem_size = 4096
cpu_type = 0
memc_type = 0
fpa = 0
fpu_type = 1
display_mode = 0
double_scan = 1
video_scale = 1
video_fullscreen_scale = 0
video_linear_filtering = 0
video_black_level = 0
fdc_type = 1
st506_present = 0
rom_set = riscos311
monitor_type = multisync
joystick_if = none
unique_id = 1
hd4_fn = 
hd4_sectors = 63
hd4_heads = 16
hd4_cylinders = 100
hd5_fn = 
hd5_sectors = 63
hd5_heads = 16
hd5_cylinders = 100
renderer_driver = auto
podule_0 = 
podule_1 = 
podule_2 = 
podule_3 = 
5th_column_fn = 
support_rom_enabled = 1

[Joysticks]
joystick_0_nr = 0
joystick_1_nr = 0
EOF

if [ "${SKIP_BUILD:-0}" != "1" ]; then
	xcodebuild \
		-project Arculator.xcodeproj \
		-target "$APP_NAME" \
		-configuration "$CONFIGURATION" \
		CODE_SIGNING_ALLOWED=NO \
		build
fi

ui_enabled="$(osascript -e 'tell application "System Events" to get UI elements enabled' 2>/dev/null || echo false)"
if [ "$ui_enabled" != "true" ]; then
	echo "Interactive macOS GUI smoke test requires System Events UI scripting access." >&2
	echo "Enable accessibility for the terminal running the test, then rerun." >&2
	exit 77
fi

before_pids="$(pgrep -x "$APP_NAME" 2>/dev/null || true)"
open -n "$APP_PATH" --args "$CONFIG_NAME"

attempt=0
while [ -z "$app_pid" ]; do
	current_pids="$(pgrep -x "$APP_NAME" 2>/dev/null || true)"
	for pid in $current_pids; do
		case " $before_pids " in
			*" $pid "*) ;;
			*)
				if process_is_live "$pid"; then
					app_pid="$pid"
					break
				fi
				;;
		esac
	done

	attempt=$((attempt + 1))
	if [ "$attempt" -ge 80 ]; then
		echo "Failed to determine launched $APP_NAME PID" >&2
		exit 1
	fi
	sleep 0.25
done

osascript "$APP_SCRIPT" "$APP_NAME" "$app_pid" >"$SCRIPT_LOG" 2>&1 &
script_pid=$!

while kill -0 "$script_pid" 2>/dev/null; do
	if ! process_is_live "$app_pid"; then
		kill "$script_pid" 2>/dev/null || true
		wait "$script_pid" 2>/dev/null || true
		wait "$app_pid" 2>/dev/null || true
		echo "$APP_NAME exited before the GUI smoke test completed" >&2
		if [ -s "$SCRIPT_LOG" ]; then
			echo "AppleScript log:" >&2
			cat "$SCRIPT_LOG" >&2
		fi
		exit 1
	fi
	sleep 0.25
done

if ! wait "$script_pid"; then
	if [ -s "$SCRIPT_LOG" ]; then
		echo "AppleScript log:" >&2
		cat "$SCRIPT_LOG" >&2
	fi
	exit 1
fi

attempt=0
while process_is_live "$app_pid"; do
	attempt=$((attempt + 1))
	if [ "$attempt" -ge 80 ]; then
		echo "App did not exit after GUI smoke actions" >&2
		exit 1
	fi
	sleep 0.25
done

wait "$app_pid" 2>/dev/null || true
