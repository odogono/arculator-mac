#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-Debug}"
APP_NAME="Arculator"
APP_PATH="${APP_PATH:-$PWD/build/$CONFIGURATION/$APP_NAME.app}"
APP_SCRIPT="$PWD/tests/macos_session1_check.applescript"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/arculator-session1.XXXXXX")"
BACKUP_ROOT="$TMP_ROOT/backups"
COPIED_APP_DIR="$TMP_ROOT/copied-app"
COPIED_APP_PATH="$COPIED_APP_DIR/$APP_NAME.app"
REAL_HOME="${HOME}"
SUPPORT_ROOT="$REAL_HOME/Library/Application Support/Arculator"
CONFIGS_DIR="$SUPPORT_ROOT/configs"
GLOBAL_CONFIG_PATH="$SUPPORT_ROOT/arc.cfg"
GLOBAL_BACKUP_PATH="$BACKUP_ROOT/arc.cfg"
CONFIGS_BACKUP_PATH="$BACKUP_ROOT/configs"
SCRIPT_LOG1="$TMP_ROOT/session1-ui.log"
SCRIPT_LOG2="$TMP_ROOT/session1-relaunch.log"
BASE_NAME="session1-$$"
CREATED_NAME="$BASE_NAME-created"
RENAMED_NAME="$BASE_NAME-renamed"
COPIED_NAME="$BASE_NAME-copy"
RENAMED_CONFIG_PATH="$CONFIGS_DIR/$RENAMED_NAME.cfg"
COPIED_CONFIG_PATH="$CONFIGS_DIR/$COPIED_NAME.cfg"
CREATED_CONFIG_PATH="$CONFIGS_DIR/$CREATED_NAME.cfg"

app_pid=""
global_backup_mode="absent"
configs_backup_mode="absent"

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

	rm -rf "$CONFIGS_DIR"
	case "$configs_backup_mode" in
		dir)
			mv "$CONFIGS_BACKUP_PATH" "$CONFIGS_DIR"
			;;
		absent)
			mkdir -p "$CONFIGS_DIR"
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
	"$COPIED_APP_DIR" \
	"$SUPPORT_ROOT" \
	"$SUPPORT_ROOT/cmos" \
	"$SUPPORT_ROOT/hostfs" \
	"$SUPPORT_ROOT/podules" \
	"$SUPPORT_ROOT/roms"

if [ -d "$CONFIGS_DIR" ]; then
	mv "$CONFIGS_DIR" "$CONFIGS_BACKUP_PATH"
	configs_backup_mode="dir"
fi
mkdir -p "$CONFIGS_DIR"

if [ -f "$GLOBAL_CONFIG_PATH" ]; then
	cp "$GLOBAL_CONFIG_PATH" "$GLOBAL_BACKUP_PATH"
	global_backup_mode="file"
fi

cat >"$GLOBAL_CONFIG_PATH" <<EOF
sound_enable = 0
stereo = 1
sound_gain = 0
sound_filter = 0
disc_noise_gain = 9999
first_fullscreen = 0
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
	echo "Session 1 automation requires System Events UI scripting access." >&2
	echo "Enable accessibility for the terminal running the test, then rerun." >&2
	exit 77
fi

cp -R "$APP_PATH" "$COPIED_APP_PATH"

launch_app() {
	before_pids="$(pgrep -x "$APP_NAME" 2>/dev/null || true)"
	if [ -n "${2:-}" ]; then
		open -n "$1" --args "$2"
	else
		open -n "$1"
	fi

	app_pid=""
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
		if [ "$attempt" -ge 120 ]; then
			echo "Failed to determine launched $APP_NAME PID" >&2
			exit 1
		fi
		sleep 0.25
	done
}

launch_app "$COPIED_APP_PATH" ""
osascript "$APP_SCRIPT" exercise "$APP_NAME" "$app_pid" "$CREATED_NAME" "$RENAMED_NAME" "$COPIED_NAME" >"$SCRIPT_LOG1" 2>&1 || {
	cat "$SCRIPT_LOG1" >&2
	exit 1
}
wait "$app_pid" 2>/dev/null || true
app_pid=""

[ -f "$RENAMED_CONFIG_PATH" ] || { echo "Expected renamed config missing: $RENAMED_CONFIG_PATH" >&2; exit 1; }
[ ! -f "$CREATED_CONFIG_PATH" ] || { echo "Original config still present after rename: $CREATED_CONFIG_PATH" >&2; exit 1; }
[ ! -f "$COPIED_CONFIG_PATH" ] || { echo "Copied config still present after delete: $COPIED_CONFIG_PATH" >&2; exit 1; }

grep -Eq '^mem_size *= *2048$' "$RENAMED_CONFIG_PATH" || {
	echo "Edited config did not persist expected memory size in $RENAMED_CONFIG_PATH" >&2
	exit 1
}

launch_app "$COPIED_APP_PATH" "$RENAMED_NAME"
osascript "$APP_SCRIPT" exit_after_launch "$APP_NAME" "$app_pid" >"$SCRIPT_LOG2" 2>&1 || {
	cat "$SCRIPT_LOG2" >&2
	exit 1
}
wait "$app_pid" 2>/dev/null || true
app_pid=""

echo "Session 1 automation passed."
echo "Copied app path: $COPIED_APP_PATH"
echo "Verified config: $RENAMED_CONFIG_PATH"
