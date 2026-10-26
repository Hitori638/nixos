#!/usr/bin/env bash
# power.sh — session actions for the Quickshell dashboard.
#   power.sh lock | suspend | logout | reboot | poweroff
# Runs detached from Quickshell, so closing the dashboard can't kill it half-way.

lock() {
	pidof hyprlock >/dev/null || setsid -f hyprlock >/dev/null 2>&1
}

case "$1" in
lock)
	lock
	;;
suspend)
	# lock first so the machine wakes up locked, give hyprlock a moment to draw, then sleep
	lock
	sleep 1
	systemctl suspend
	;;
logout)
	sleep 0.3
	# Lua-config Hyprland takes hl.dsp.*; older configs take the plain dispatcher
	out=$(hyprctl dispatch 'hl.dsp.exit()' 2>&1)
	case "$out" in *ok*) exit 0 ;; esac
	out=$(hyprctl dispatch exit 2>&1)
	case "$out" in *ok*) exit 0 ;; esac
	loginctl terminate-session "${XDG_SESSION_ID:-self}"
	;;
reboot)
	systemctl reboot
	;;
poweroff)
	systemctl poweroff
	;;
*)
	echo "usage: power.sh lock|suspend|logout|reboot|poweroff" >&2
	exit 1
	;;
esac
