#!/usr/bin/env bash
# nightlight.sh — night light control used by the Quickshell dashboard and Hyprland startup.
#
#   nightlight.sh on          start at the saved temperature
#   nightlight.sh off         stop (screen goes back to normal)
#   nightlight.sh toggle
#   nightlight.sh set 3500    save a new temperature (restarts it if running)
#   nightlight.sh status      prints "on 3000" / "off 3000"
#   nightlight.sh restore     on login: start again if it was on last time (default: on)
#
# Uses hyprsunset when installed (native to Hyprland), otherwise gammastep in
# continuous mode. `gammastep -O` is one-shot: on wlroots/Hyprland the gamma is
# dropped as soon as that process exits, which is why the old toggle misbehaved.

STATE_DIR="$HOME/.config/quickshell/state"
ON_FILE="$STATE_DIR/night-on"
TEMP_FILE="$STATE_DIR/night-temp"
mkdir -p "$STATE_DIR"

PATTERN='^[^ ]*/?(\.?hyprsunset|\.?gammastep)(-wrapped)?( |$)'

temp() {
	local t
	t=$(cat "$TEMP_FILE" 2>/dev/null)
	[[ "$t" =~ ^[0-9]+$ ]] || t=3000
	echo "$t"
}

running() { pgrep -f "$PATTERN" >/dev/null; }

kill_all() {
	pkill -f "$PATTERN" 2>/dev/null
	for _ in $(seq 1 20); do
		running || return 0
		sleep 0.1
	done
	pkill -9 -f "$PATTERN" 2>/dev/null
}

start() {
	local t
	t=$(temp)
	kill_all
	if command -v hyprsunset >/dev/null 2>&1; then
		setsid -f hyprsunset -t "$t" >/dev/null 2>&1
	else
		setsid -f gammastep -m wayland -r -l 0:0 -t "$t:$t" >/dev/null 2>&1
	fi
	echo on >"$ON_FILE"
}

stop() {
	kill_all
	echo off >"$ON_FILE"
}

case "$1" in
on) start ;;
off) stop ;;
toggle) if running; then stop; else start; fi ;;
set)
	[[ "$2" =~ ^[0-9]+$ ]] || { echo "usage: nightlight.sh set KELVIN" >&2; exit 1; }
	echo "$2" >"$TEMP_FILE"
	running && start
	;;
status)
	if running; then echo "on $(temp)"; else echo "off $(temp)"; fi
	;;
restore)
	[ "$(cat "$ON_FILE" 2>/dev/null || echo on)" = "on" ] && start
	;;
*)
	echo "usage: nightlight.sh {on|off|toggle|set KELVIN|status|restore}" >&2
	exit 1
	;;
esac
