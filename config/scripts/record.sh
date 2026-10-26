#!/usr/bin/env bash
# record.sh — wf-recorder wrapper used by the Quickshell recorder menu.
#
#   record.sh full            record the focused monitor
#   record.sh output NAME     record a specific output (e.g. HDMI-A-1, eDP-1)
#   record.sh region          pick an area with slurp
#   record.sh stop            stop the running recording
#   record.sh toggle          stop if recording, otherwise record the focused monitor
#   record.sh status          prints "recording" or "idle"

DIR="$HOME/Videos/screen-recordings"
STATE="${XDG_RUNTIME_DIR:-/tmp}/qs-record.last"
mkdir -p "$DIR"

is_recording() { pgrep -x wf-recorder >/dev/null; }

start() {
	if is_recording; then
		notify-send -a Recorder "Already recording" "Stop the current recording first."
		exit 0
	fi
	local file="$DIR/$(date +%Y-%m-%d_%H-%M-%S).mp4"
	echo "$file" >"$STATE"
	setsid -f wf-recorder "$@" -f "$file" >/dev/null 2>&1
}

stop() {
	is_recording || exit 0
	pkill -INT -x wf-recorder
	for _ in $(seq 1 40); do
		is_recording || break
		sleep 0.1
	done
	local last
	last=$(cat "$STATE" 2>/dev/null)
	notify-send -a Recorder "Recording saved" "${last/#$HOME/\~}"
}

focused_output() {
	hyprctl monitors -j | jq -r '.[] | select(.focused) | .name' | head -n1
}

case "$1" in
full)
	out=$(focused_output)
	if [ -n "$out" ]; then start -o "$out"; else start; fi
	;;
output)
	[ -z "$2" ] && { echo "usage: record.sh output NAME" >&2; exit 1; }
	start -o "$2"
	;;
region)
	is_recording && exit 0
	sleep 0.2 # let the menu slide away before slurp grabs the screen
	geom=$(slurp) || exit 0
	[ -z "$geom" ] && exit 0
	start -g "$geom"
	;;
stop) stop ;;
toggle)
	if is_recording; then stop; else "$0" full; fi
	;;
status)
	is_recording && echo recording || echo idle
	;;
*)
	echo "usage: record.sh {full|output NAME|region|stop|toggle|status}" >&2
	exit 1
	;;
esac
