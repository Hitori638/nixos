#!/usr/bin/env bash
# bar-blur.sh on|off — Hyprland blur behind the Quickshell bar (layer namespace "quickshell").
# ignore_alpha keeps fully see-through parts of other Quickshell windows from being blurred.
export PATH="/run/wrappers/bin:/run/current-system/sw/bin:$PATH"
LOG="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/bar-blur.log"
mkdir -p "$(dirname "$LOG")"
log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG"; }

case "$1" in
on) blur=true; legacy=("blur, quickshell" "ignorealpha 0.3, quickshell") ;;
off) blur=false; legacy=("unset, quickshell") ;;
*) echo "usage: bar-blur.sh on|off" >&2; exit 1 ;;
esac

# Lua config (hl.layer_rule); a rule with the same name replaces the previous one
out=$(hyprctl eval "hl.layer_rule({ name = \"qs-bar-blur\", match = { namespace = \"quickshell\" }, blur = $blur, ignore_alpha = 0.3 })" 2>&1)
if [[ "$out" == *ok* ]] || [ -z "$out" ]; then
	log "$1: hl.layer_rule ok"
	exit 0
fi
# older config syntax
for r in "${legacy[@]}"; do hyprctl keyword layerrule "$r" >/dev/null 2>&1; done
log "$1: hl.layer_rule said '$out' — used hyprctl keyword layerrule instead"
