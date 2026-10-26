#!/usr/bin/env bash
# ~/.config/scripts/brightness.sh — external monitor brightness (DDC/CI)
set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_FILE="$STATE_DIR/brightness"
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/brightness.lock"
DDC_BUS=5
DDC_SLEEP=0.5

mkdir -p "$STATE_DIR"

# ddcutil calls must never overlap; the monitor chokes on concurrent I2C traffic.
ddc() { flock "$LOCK_FILE" ddcutil "$@"; }

edp_active() {
	command -v hyprctl >/dev/null 2>&1 &&
		hyprctl monitors -j 2>/dev/null | grep -q '"name"[[:space:]]*:[[:space:]]*"eDP-1"'
}

# Valid = integer 1-100
is_valid() {
	case "$1" in
	'' | *[!0-9]*) return 1 ;;
	esac
	[ "$1" -ge 1 ] && [ "$1" -le 100 ]
}

read_ddc() {
	local val
	val=$(ddc --bus "$DDC_BUS" --sleep-multiplier "$DDC_SLEEP" getvcp 10 --brief 2>/dev/null |
		awk '{print (NF >= 4 ? $4 : $3)}') || true
	if [ -z "$val" ]; then
		val=$(ddc --display 1 --sleep-multiplier "$DDC_SLEEP" getvcp 10 --brief 2>/dev/null |
			awk '{print (NF >= 4 ? $4 : $3)}') || true
	fi
	printf '%s' "$val"
}

# Prints current brightness to stdout and exits 0 on success.
# On failure prints nothing to stdout, logs to stderr, exits 1.
get_brightness() {
	local val
	if edp_active && command -v brightnessctl >/dev/null 2>&1; then
		val=$(brightnessctl -m | awk -F, '{gsub(/%/,"",$4); print $4}')
		if is_valid "$val"; then
			echo "$val"
			return 0
		fi
		echo "brightness.sh: brightnessctl returned invalid value '${val:-<empty>}'" >&2
		return 1
	fi
	val=$(read_ddc)
	if is_valid "$val"; then
		echo "$val"
		return 0
	fi
	echo "brightness.sh: DDC/CI read failed (bus $DDC_BUS and --display 1); got '${val:-<empty>}'" >&2
	return 1
}

set_brightness() {
	local n="$1"
	if ! is_valid "$n"; then
		echo "brightness.sh: invalid brightness '${n:-<empty>}' (expected integer 1-100)" >&2
		return 2
	fi
	if edp_active && command -v brightnessctl >/dev/null 2>&1; then
		brightnessctl set "${n}%"
		return
	fi
	if ! ddc --bus "$DDC_BUS" --sleep-multiplier "$DDC_SLEEP" setvcp 10 "$n"; then
		ddc --display 1 --sleep-multiplier "$DDC_SLEEP" setvcp 10 "$n"
	fi
}

case "${1:-get}" in
get)
	get_brightness
	;;
set)
	if [ $# -lt 2 ]; then
		echo "usage: brightness.sh set <1-100>" >&2
		exit 2
	fi
	set_brightness "$2"
	;;
save)
	if val=$(get_brightness); then
		printf '%s\n' "$val" >"$STATE_FILE"
	else
		exit 1
	fi
	;;
restore)
	val=""
	[ -f "$STATE_FILE" ] && val=$(cat "$STATE_FILE" 2>/dev/null || true)
	if ! is_valid "$val"; then
		echo "brightness.sh: no valid saved brightness; restoring to 100" >&2
		val=100
	fi
	set_brightness "$val"
	;;
*)
	echo "usage: brightness.sh {get|set <n>|save|restore}" >&2
	exit 2
	;;
esac
